package com.readapp.media

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.MediaItem
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ReadAudioService : MediaSessionService() {
    private var mediaSession: MediaSession? = null
    private lateinit var player: ExoPlayer

    private inner class TtsMediaSessionCallback : MediaSession.Callback {
        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>
        ): ListenableFuture<List<MediaItem>> {
            mediaItems.firstOrNull()?.let { prepareFromCache(it) }
            return Futures.immediateFuture(mediaItems)
        }

        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
            startIndex: Int,
            startPositionMs: Long
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            mediaItems.firstOrNull()?.let { prepareFromCache(it) }
            val result = MediaSession.MediaItemsWithStartPosition(mediaItems, startIndex, startPositionMs)
            return Futures.immediateFuture(result)
        }
    }

    private fun prepareFromCache(mediaItem: MediaItem) {
        val audioData = AudioCache.get(mediaItem.mediaId)
        if (audioData != null) {
            val safeItem = if (mediaItem.localConfiguration?.uri == null) {
                MediaItem.Builder()
                    .setMediaId(mediaItem.mediaId)
                    .setUri("https://localhost/")
                    .build()
            } else {
                mediaItem
            }
            val dataSourceFactory = DataSource.Factory { ByteArrayDataSource(audioData) }
            val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(safeItem)
            player.setMediaSource(mediaSource)
        } else {
            // If data is not in cache, we can't play it.
            // The ViewModel is responsible for putting it there first.
            // We'll just prepare the player with an empty source to avoid errors.
            player.clearMediaItems()
        }
    }

    override fun onCreate() {
        super.onCreate()
        appendLog("ReadAudioService onCreate")

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
            .build()

        player = ExoPlayer.Builder(this)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .build()

        mediaSession = MediaSession.Builder(this, player)
            .setCallback(TtsMediaSessionCallback())
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        appendLog("ReadAudioService onStartCommand action=${intent?.action} flags=$flags startId=$startId")
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onDestroy() {
        appendLog("ReadAudioService onDestroy")
        mediaSession?.release()
        mediaSession = null
        player.release()
        super.onDestroy()
    }

    private fun appendLog(message: String) {
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())
        val line = "[$timestamp] $message\n"
        runCatching {
            File(filesDir, "reader_logs.txt").appendText(line)
        }
        Log.d("ReadAudioService", message)
    }

    companion object {
        fun startService(context: Context) {
            runCatching {
                val file = File(context.filesDir, "reader_logs.txt")
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())
                file.appendText("[$timestamp] ReadAudioService startService\n")
            }
            context.startService(Intent(context, ReadAudioService::class.java))
        }
    }
}
