package com.readapp.media

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.AudioManager.OnAudioFocusChangeListener
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

class ReadAudioService : MediaSessionService() {
    private var mediaSession: MediaSession? = null
    private var audioManager: AudioManager? = null
    private val focusListener = OnAudioFocusChangeListener { change ->
        val player = mediaSession?.player ?: return@OnAudioFocusChangeListener
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> player.pause()
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> player.pause()
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> player.volume = 0.2f
            AudioManager.AUDIOFOCUS_GAIN -> player.volume = 1f
        }
    }

    override fun onCreate() {
        super.onCreate()
        val player = PlayerHolder.get(this)
        mediaSession = MediaSession.Builder(this, player).build()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager?.requestAudioFocus(
            focusListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN
        )
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onDestroy() {
        mediaSession?.release()
        audioManager?.abandonAudioFocus(focusListener)
        mediaSession = null
        super.onDestroy()
    }

    companion object {
        fun startService(context: Context) {
            context.startService(Intent(context, ReadAudioService::class.java))
        }
    }
}
