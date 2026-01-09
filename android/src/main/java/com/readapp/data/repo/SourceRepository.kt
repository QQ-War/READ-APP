package com.readapp.data.repo

import android.content.Context
import com.readapp.data.ReadRepository
import com.readapp.data.model.BookSource

class SourceRepository(private val readRepository: ReadRepository) {
    fun getBookSources(context: Context, baseUrl: String, publicUrl: String?, accessToken: String) =
        readRepository.getBookSources(context, baseUrl, publicUrl, accessToken)

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
