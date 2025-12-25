package com.readapp.media

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.AudioManager.OnAudioFocusChangeListener
import android.util.Log
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ReadAudioService : MediaSessionService() {
    private var mediaSession: MediaSession? = null
    private var audioManager: AudioManager? = null
    private val focusListener = OnAudioFocusChangeListener { change ->
        val player = mediaSession?.player ?: return@OnAudioFocusChangeListener
        appendLog("Audio focus change=$change playWhenReady=${player.playWhenReady}")
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                appendLog("Audio focus loss -> pause")
                player.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                appendLog("Audio focus transient loss -> pause")
                player.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                appendLog("Audio focus duck -> volume 0.2")
                player.volume = 0.2f
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                appendLog("Audio focus gain -> volume 1.0")
                player.volume = 1f
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        appendLog("ReadAudioService onCreate")
        val player = PlayerHolder.get(this)
        mediaSession = MediaSession.Builder(this, player).build()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val focusResult = audioManager?.requestAudioFocus(
            focusListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN
        )
        appendLog("Audio focus request result=$focusResult")
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onDestroy() {
        appendLog("ReadAudioService onDestroy")
        mediaSession?.release()
        audioManager?.abandonAudioFocus(focusListener)
        mediaSession = null
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
