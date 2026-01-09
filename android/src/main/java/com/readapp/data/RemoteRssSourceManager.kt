package com.readapp.data

import com.readapp.data.model.RssSourceItem
import com.readapp.data.model.RssSourcesResponse
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class RemoteRssSourceManager(
    private val remoteDataSourceFactory: RemoteDataSourceFactory,
    private val preferences: UserPreferences,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    suspend fun fetchSources(): Result<RssSourcesResponse> = withRemoteSource { source, token ->
        source.fetchSources(token)
    }

    suspend fun toggleSource(sourceUrl: String, isEnabled: Boolean): Result<Any> = withRemoteSource { source, token ->
        source.toggleSource(token, sourceUrl, isEnabled)
    }

    suspend fun saveRemoteSource(remoteId: String?, source: RssSourceItem): Result<Any> = withRemoteSource { remote, token ->
        remote.saveSource(token, remoteId, source)
    }

    suspend fun deleteRemoteSource(sourceUrl: String): Result<Any> = withRemoteSource { remote, token ->
        remote.deleteSource(token, sourceUrl)
    }

    private suspend fun <T> withRemoteSource(action: suspend (RssRemoteDataSource, String) -> Result<T>): Result<T> {
        val (baseUrl, publicUrl, token) = preferences.getCredentials()
        val actualToken = token ?: return Result.failure(IllegalStateException("请先登录"))
        val source = remoteDataSourceFactory.createRssRemoteDataSource(baseUrl, publicUrl)
        return withContext(ioDispatcher) {
            action(source, actualToken)
        }
    }
}
