package com.readapp.data.repo

import android.content.Context
import android.net.Uri
import com.readapp.data.ReadRepository
import com.readapp.data.RemoteDataSourceFactory
import com.readapp.data.model.Book

class BookRepository(
    private val remoteDataSourceFactory: RemoteDataSourceFactory,
    private val readRepository: ReadRepository
) {
    private fun createSource(baseUrl: String, publicUrl: String?) =
        remoteDataSourceFactory.createBookRemoteDataSource(baseUrl, publicUrl)

    suspend fun fetchBooks(baseUrl: String, publicUrl: String?, accessToken: String) =
        createSource(baseUrl, publicUrl).fetchBooks(accessToken)

    suspend fun fetchChapterList(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?
    ) = createSource(baseUrl, publicUrl).fetchChapterList(accessToken, bookUrl, bookSourceUrl)

    suspend fun fetchChapterContent(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
        index: Int,
        contentType: Int
    ) = createSource(baseUrl, publicUrl).fetchChapterContent(accessToken, bookUrl, bookSourceUrl, index, contentType)

    suspend fun saveBookProgress(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        index: Int,
        pos: Double,
        title: String?
    ) = createSource(baseUrl, publicUrl).saveBookProgress(accessToken, bookUrl, index, pos, title)

    suspend fun saveBook(baseUrl: String, publicUrl: String?, accessToken: String, book: Book) =
        readRepository.saveBook(baseUrl, publicUrl, accessToken, book)

    suspend fun deleteBook(baseUrl: String, publicUrl: String?, accessToken: String, book: Book) =
        readRepository.deleteBook(baseUrl, publicUrl, accessToken, book)

    suspend fun setBookSource(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        oldUrl: String,
        newUrl: String,
        newBookSourceUrl: String
    ) = createSource(baseUrl, publicUrl).setBookSource(accessToken, oldUrl, newUrl, newBookSourceUrl)

    suspend fun searchBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        keyword: String,
        bookSourceUrl: String,
        page: Int
    ) = createSource(baseUrl, publicUrl).searchBook(accessToken, keyword, bookSourceUrl, page)

    suspend fun importBook(baseUrl: String, publicUrl: String?, accessToken: String, fileUri: Uri, context: Context) =
        readRepository.importBook(baseUrl, publicUrl, accessToken, fileUri, context)
}
