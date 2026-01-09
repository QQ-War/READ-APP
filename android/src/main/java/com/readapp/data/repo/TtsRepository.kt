package com.readapp.data.repo

import com.readapp.data.ReadRepository
import com.readapp.data.model.HttpTTS

class TtsRepository(private val readRepository: ReadRepository) {
    suspend fun fetchTtsEngines(baseUrl: String, publicUrl: String?, accessToken: String) =
        readRepository.fetchTtsEngines(baseUrl, publicUrl, accessToken)

    suspend fun fetchDefaultTts(baseUrl: String, publicUrl: String?, accessToken: String) =
        readRepository.fetchDefaultTts(baseUrl, publicUrl, accessToken)

    suspend fun addTts(baseUrl: String, publicUrl: String?, accessToken: String, tts: HttpTTS) =
        readRepository.addTts(baseUrl, publicUrl, accessToken, tts)

    suspend fun deleteTts(baseUrl: String, publicUrl: String?, accessToken: String, id: String) =
        readRepository.deleteTts(baseUrl, publicUrl, accessToken, id)

    suspend fun saveTtsBatch(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String) =
        readRepository.saveTtsBatch(baseUrl, publicUrl, accessToken, jsonContent)

    fun buildTtsAudioUrl(baseUrl: String, accessToken: String, ttsId: String, text: String, speed: Float) =
        readRepository.buildTtsAudioUrl(baseUrl, accessToken, ttsId, text, speed)
}
