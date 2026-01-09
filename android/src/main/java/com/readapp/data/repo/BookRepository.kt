package com.readapp.data.repo

import android.content.Context
import android.net.Uri
import com.readapp.data.ReadRepository
import com.readapp.data.model.Book

class BookRepository(private val readRepository: ReadRepository) {
    suspend fun fetchBooks(baseUrl: String, publicUrl: String?, accessToken: String) =
        readRepository.fetchBooks(baseUrl, publicUrl, accessToken)

    suspend fun fetchChapterList(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?
    ) = readRepository.fetchChapterList(baseUrl, publicUrl, accessToken, bookUrl, bookSourceUrl)

    suspend fun fetchChapterContent(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
        index: Int,
        contentType: Int
    ) = readRepository.fetchChapterContent(baseUrl, publicUrl, accessToken, bookUrl, bookSourceUrl, index, contentType)

    suspend fun saveBookProgress(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        index: Int,
        pos: Double,
        title: String?
    ) = readRepository.saveBookProgress(baseUrl, publicUrl, accessToken, bookUrl, index, pos, title)

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
    ) = readRepository.setBookSource(baseUrl, publicUrl, accessToken, oldUrl, newUrl, newBookSourceUrl)

    suspend fun searchBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        keyword: String,
        bookSourceUrl: String,
        page: Int
    ) = readRepository.searchBook(baseUrl, publicUrl, accessToken, keyword, bookSourceUrl, page)

    suspend fun importBook(baseUrl: String, publicUrl: String?, accessToken: String, fileUri: Uri, context: Context) =
        readRepository.importBook(baseUrl, publicUrl, accessToken, fileUri, context)
}
