package com.readapp.viewmodel

import android.net.Uri
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

internal class AudioBookController(private val viewModel: BookViewModel) {
    private var mediaController: MediaController? = null
    private val listener = ControllerListener()
    private var progressJob: Job? = null

    fun bindMediaController(controller: MediaController) {
        mediaController?.removeListener(listener)
        mediaController = controller
        mediaController?.addListener(listener)
        viewModel._audioIsPlaying.value = controller.isPlaying
        startProgressUpdates()
    }

    fun release() {
        mediaController?.removeListener(listener)
        mediaController?.release()
        mediaController = null
        progressJob?.cancel()
        progressJob = null
    }

    fun playUrl(url: String, title: String?, artworkUrl: String?) {
        val metadataBuilder = MediaMetadata.Builder().setTitle(title ?: "")
        if (!artworkUrl.isNullOrBlank()) {
            metadataBuilder.setArtworkUri(Uri.parse(artworkUrl))
        }
        val item = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(metadataBuilder.build())
            .build()
        mediaController?.setMediaItem(item)
        mediaController?.prepare()
        mediaController?.play()
    }

    fun togglePlayPause() {
        val controller = mediaController ?: return
        if (controller.isPlaying) controller.pause() else controller.play()
    }

    fun seekTo(fraction: Float) {
        val controller = mediaController ?: return
        val duration = controller.duration
        if (duration > 0) {
            controller.seekTo((duration * fraction).toLong())
        }
    }

    fun setSpeed(speed: Float) {
        mediaController?.setPlaybackParameters(PlaybackParameters(speed))
    }

    private fun startProgressUpdates() {
        progressJob?.cancel()
        progressJob = viewModel.viewModelScope.launch {
            while (true) {
                val controller = mediaController
                if (controller != null) {
                    val duration = controller.duration.coerceAtLeast(0)
                    val position = controller.currentPosition.coerceAtLeast(0)
                    viewModel._audioDurationMs.value = duration
                    viewModel._audioPositionMs.value = position
                    viewModel._audioProgress.value = if (duration > 0) position.toFloat() / duration else 0f
                }
                delay(500)
            }
        }
    }

    private inner class ControllerListener : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            viewModel._audioIsPlaying.value = isPlaying
        }

        override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
            viewModel._audioSpeed.value = playbackParameters.speed
        }

        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
            viewModel._audioErrorMessage.value = error.message
        }
    }
}
