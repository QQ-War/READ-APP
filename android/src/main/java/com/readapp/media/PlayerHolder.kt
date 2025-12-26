package com.readapp.media

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.exoplayer.ExoPlayer

object PlayerPool {
    @Volatile
    private var player: ExoPlayer? = null

    fun get(context: Context): ExoPlayer {
        return player ?: synchronized(this) {
            player ?: buildPlayer(context.applicationContext).also { player = it }
        }
    }

    fun release() {
        player?.release()
        player = null
    }

    private fun buildPlayer(context: Context): ExoPlayer {
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(androidx.media3.common.C.USAGE_MEDIA)
            .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_SPEECH)
            .build()

        return ExoPlayer.Builder(context)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .build()
    }
}
