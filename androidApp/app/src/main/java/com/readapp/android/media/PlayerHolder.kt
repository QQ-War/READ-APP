package com.readapp.android.media

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.exoplayer.ExoPlayer

object PlayerHolder {
    @Volatile
    private var sharedPlayer: ExoPlayer? = null

    fun get(context: Context): ExoPlayer {
        return sharedPlayer ?: synchronized(this) {
            sharedPlayer ?: ExoPlayer.Builder(context.applicationContext)
                .setHandleAudioBecomingNoisy(true)
                .build()
                .also { player ->
                    val audioAttributes = AudioAttributes.Builder()
                        .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
                        .setUsage(androidx.media3.common.C.USAGE_MEDIA)
                        .build()
                    player.setAudioAttributes(audioAttributes, true)
                    sharedPlayer = player
                }
        }
    }
}
