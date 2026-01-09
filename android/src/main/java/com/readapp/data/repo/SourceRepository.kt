package com.readapp.data.repo

import android.content.Context
import com.readapp.data.LocalSourceCache
import com.readapp.data.ReadRepository
import com.readapp.data.model.BookSource
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow

class SourceRepository(
    private val readRepository: ReadRepository,
    private val localCache: LocalSourceCache
) {
    fun getBookSources(context: Context, baseUrl: String, publicUrl: String?, accessToken: String): Flow<Result<List<BookSource>>> =
        flow {
            val cachedSources = localCache.loadSources()
            if (cachedSources != null) {
                emit(Result.success(cachedSources))
            }

        val remoteFlow = readRepository.getBookSources(context, baseUrl, publicUrl, accessToken)
        remoteFlow.collect { result ->
            emit(result)
            result.onSuccess { localCache.saveSources(it) }
        }
        }

    suspend fun deleteBookSource(context: Context, baseUrl: String, publicUrl: String?, accessToken: String, source: BookSource) =
        readRepository.deleteBookSource(context, baseUrl, publicUrl, accessToken, source)

    suspend fun toggleBookSource(context: Context, baseUrl: String, publicUrl: String?, accessToken: String, source: BookSource, isEnabled: Boolean) =
        readRepository.toggleBookSource(context, baseUrl, publicUrl, accessToken, source, isEnabled)

    suspend fun getBookSourceDetail(baseUrl: String, publicUrl: String?, accessToken: String, id: String) =
        readRepository.getBookSourceDetail(baseUrl, publicUrl, accessToken, id)

    suspend fun fetchExploreKinds(baseUrl: String, publicUrl: String?, accessToken: String, bookSourceUrl: String) =
        readRepository.fetchExploreKinds(baseUrl, publicUrl, accessToken, bookSourceUrl)

    suspend fun exploreBook(baseUrl: String, publicUrl: String?, accessToken: String, bookSourceUrl: String, ruleFindUrl: String, page: Int) =
        readRepository.exploreBook(baseUrl, publicUrl, accessToken, bookSourceUrl, ruleFindUrl, page)

    suspend fun saveBookSource(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String) =
        readRepository.saveBookSource(baseUrl, publicUrl, accessToken, jsonContent)
}
