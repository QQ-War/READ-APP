package com.readapp.android.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.TaskStackBuilder
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.readapp.android.MainActivity
import com.readapp.android.R

class ReadAudioService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var resumeOnFocusGain: Boolean = false
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: Intent?) {
            if (intent?.action == android.media.AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                mediaSession?.player?.pause()
            }
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        val player = mediaSession?.player ?: return@OnAudioFocusChangeListener
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (resumeOnFocusGain) {
                    player.play()
                    resumeOnFocusGain = false
                }
                player.volume = 1.0f
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeOnFocusGain = false
                player.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeOnFocusGain = player.isPlaying
                player.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                resumeOnFocusGain = player.isPlaying
                player.volume = 0.3f
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val player: ExoPlayer = PlayerHolder.get(this)
        mediaSession = MediaSession.Builder(this, player).build()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        requestFocus()
        ensureChannel()
        mediaSession?.let { session ->
            startForeground(NOTIFICATION_ID, buildNotification(session))
        }
        registerReceiver(
            noisyReceiver,
            IntentFilter(android.media.AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        )
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        mediaSession?.let { session ->
            startForeground(NOTIFICATION_ID, buildNotification(session))
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        runCatching { unregisterReceiver(noisyReceiver) }
        mediaSession?.run {
            player.release()
            release()
        }
        abandonFocus()
        mediaSession = null
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.app_name),
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun buildNotification(session: MediaSession): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent: PendingIntent? = TaskStackBuilder.create(this).run {
            addNextIntentWithParentStack(intent)
            getPendingIntent(0, PendingIntent.FLAG_IMMUTABLE)
        }

        val metadata = session.controller.mediaMetadata
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(metadata.title)
            .setContentText(metadata.subtitle)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(pendingIntent)
            .setStyle(MediaStyle().setMediaSession(session.sessionCompatToken))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun requestFocus() {
        val manager = audioManager ?: return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        focusRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener)
                .setAcceptsDelayedFocusGain(true)
                .build()
        } else null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { manager.requestAudioFocus(it) }
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }
    }

    private fun abandonFocus() {
        val manager = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { manager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(focusListener)
        }
        resumeOnFocusGain = false
    }

    companion object {
        private const val CHANNEL_ID = "read_audio"
        private const val NOTIFICATION_ID = 1001

        fun startService(context: android.content.Context) {
            val intent = Intent(context, ReadAudioService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
