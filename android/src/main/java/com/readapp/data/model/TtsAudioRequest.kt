package com.readapp.data.model

/**
 * Describes how to obtain the audio bytes for a paragraph.
 */
sealed interface TtsAudioRequest {
    data class Url(val url: String) : TtsAudioRequest
    data class Reader(
        val voiceName: String,
        val text: String,
        val speechRate: Double,
        val pitch: Double = 1.0
    ) : TtsAudioRequest
}
