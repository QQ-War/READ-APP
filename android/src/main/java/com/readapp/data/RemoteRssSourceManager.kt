package com.readapp.data

import com.readapp.data.model.RssEditPayload
import com.readapp.data.model.RssSourceItem
import com.readapp.data.model.RssSourcesResponse
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class RemoteRssSourceManager(
    private val repository: ReadRepository,
    private val preferences: UserPreferences,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    suspend fun fetchSources(): Result<RssSourcesResponse> {
        val (baseUrl, publicUrl, token) = preferences.getCredentials()
        val actualToken = token ?: return Result.failure(IllegalStateException("请先登录"))
        return withContext(ioDispatcher) {
            repository.fetchRssSources(baseUrl, publicUrl, actualToken)
        }
    }

    suspend fun toggleSource(sourceUrl: String, isEnabled: Boolean): Result<Any> {
        val (baseUrl, publicUrl, token) = preferences.getCredentials()
        val actualToken = token ?: return Result.failure(IllegalStateException("请先登录"))
        return withContext(ioDispatcher) {
            repository.toggleRssSource(baseUrl, publicUrl, actualToken, sourceUrl, isEnabled)
        }
    }

    suspend fun saveRemoteSource(
        remoteId: String?,
        source: RssSourceItem
    ): Result<Any> {
        val (baseUrl, publicUrl, token) = preferences.getCredentials()
        val actualToken = token ?: return Result.failure(IllegalStateException("请先登录"))
        return withContext(ioDispatcher) {
            repository.saveRssSource(
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = actualToken,
                remoteId = remoteId,
                source = source
            )
        }
    }

    suspend fun deleteRemoteSource(sourceUrl: String): Result<Any> {
        val (baseUrl, publicUrl, token) = preferences.getCredentials()
        val actualToken = token ?: return Result.failure(IllegalStateException("请先登录"))
        return withContext(ioDispatcher) {
            repository.deleteRssSource(
                baseUrl = baseUrl,
                publicUrl = publicUrl,
                accessToken = actualToken,
                sourceUrl = sourceUrl
            )
        }
    }
}
