package com.readapp.data.repo

import com.readapp.data.ReadRepository
import com.readapp.data.RemoteDataSourceFactory
import com.readapp.data.model.HttpTTS

class TtsRepository(
    private val remoteDataSourceFactory: RemoteDataSourceFactory,
    private val readRepository: ReadRepository
) {
    private fun createSource(baseUrl: String, publicUrl: String?) =
        remoteDataSourceFactory.createTtsRemoteDataSource(baseUrl, publicUrl)

    suspend fun fetchTtsEngines(baseUrl: String, publicUrl: String?, accessToken: String) =
        createSource(baseUrl, publicUrl).fetchTtsEngines(accessToken)

    suspend fun fetchDefaultTts(baseUrl: String, publicUrl: String?, accessToken: String) =
        createSource(baseUrl, publicUrl).fetchDefaultTts(accessToken)

    suspend fun addTts(baseUrl: String, publicUrl: String?, accessToken: String, tts: HttpTTS) =
        createSource(baseUrl, publicUrl).addTts(accessToken, tts)

    suspend fun deleteTts(baseUrl: String, publicUrl: String?, accessToken: String, id: String) =
        createSource(baseUrl, publicUrl).deleteTts(accessToken, id)

    suspend fun saveTtsBatch(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String) =
        createSource(baseUrl, publicUrl).saveTtsBatch(accessToken, jsonContent)

    fun buildTtsAudioUrl(baseUrl: String, accessToken: String, ttsId: String, text: String, speed: Double) =
        readRepository.buildTtsAudioUrl(baseUrl, accessToken, ttsId, text, speed)
}
