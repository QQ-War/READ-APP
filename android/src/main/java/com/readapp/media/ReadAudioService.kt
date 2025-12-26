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

class ReadAudioService : MediaSessionService(), OnAudioFocusChangeListener {
    private var mediaSession: MediaSession? = null
    private lateinit var audioManager: AudioManager

    override fun onCreate() {
        super.onCreate()
        appendLog("ReadAudioService onCreate")
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val player = PlayerPool.get(this)
        mediaSession = MediaSession.Builder(this, player).build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        appendLog("ReadAudioService onStartCommand action=${intent?.action} flags=$flags startId=$startId")
        val result = audioManager.requestAudioFocus(
            this,
            androidx.media3.common.C.STREAM_TYPE_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN
        )
        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            appendLog("Audio focus request granted")
        } else {
            appendLog("Audio focus request failed")
        }
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onDestroy() {
        appendLog("ReadAudioService onDestroy")
        audioManager.abandonAudioFocus(this)
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    override fun onAudioFocusChange(focusChange: Int) {
        val player = mediaSession?.player ?: return
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                appendLog("Audio focus lost permanently")
                player.pause() // ViewModel is responsible for stopping permanently
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                appendLog("Audio focus lost transiently")
                player.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                appendLog("Audio focus lost transiently (can duck)")
                player.volume = 0.3f
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                appendLog("Audio focus gained")
                player.volume = 1.0f // Restore volume
                // ExoPlayer will handle resuming if playWhenReady is true.
                // We don't call play() here as it would override user intent.
            }
        }
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
