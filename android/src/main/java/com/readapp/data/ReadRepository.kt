package com.readapp.data

import android.content.Context
import android.net.Uri
import com.readapp.data.model.ApiResponse
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.ReplaceRule
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import retrofit2.Response
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import com.google.gson.Gson
import java.io.File

class ReadRepository(private val apiFactory: (String) -> ReadApiService) {

    private val gson = Gson()
    private val SOURCES_CACHE_FILE = "sources_cache.json"

    private fun saveSourcesToCache(context: Context, sources: List<com.readapp.data.model.BookSource>) {
        val json = gson.toJson(sources)
        File(context.filesDir, SOURCES_CACHE_FILE).writeText(json)
    }

    private fun loadSourcesFromCache(context: Context): List<com.readapp.data.model.BookSource>? {
        val file = File(context.filesDir, SOURCES_CACHE_FILE)
        if (!file.exists()) return null
        val json = file.readText()
        return gson.fromJson(json, Array<com.readapp.data.model.BookSource>::class.java)?.toList()
    }

    suspend fun login(baseUrl: String, publicUrl: String?, username: String, password: String): Result<BookLoginResult> =
        executeWithFailover<BookLoginResult> { api ->
            api.login(username, password)
        }(buildEndpoints(baseUrl, publicUrl))

    suspend fun fetchBooks(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<Book>> =
        executeWithFailover {
            it.getBookshelf(accessToken)
        }(buildEndpoints(baseUrl, publicUrl)).map { list -> list.map { book -> book.toUiModel() } }

    suspend fun fetchChapterList(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
    ): Result<List<Chapter>> = executeWithFailover {
        it.getChapterList(accessToken, bookUrl, bookSourceUrl)
    }(buildEndpoints(baseUrl, publicUrl))

    suspend fun fetchChapterContent(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
        index: Int,
    ): Result<String> = executeWithFailover {
        it.getBookContent(accessToken, bookUrl, index, 0, bookSourceUrl)
    }(buildEndpoints(baseUrl, publicUrl))

    suspend fun saveBookProgress(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        index: Int,
        pos: Double,
        title: String?,
    ): Result<String> = executeWithFailover {
        it.saveBookProgress(accessToken, bookUrl, index, pos, title)
    }(buildEndpoints(baseUrl, publicUrl))

    suspend fun fetchDefaultTts(baseUrl: String, publicUrl: String?, accessToken: String): Result<String> =
        executeWithFailover { it.getDefaultTts(accessToken) }(buildEndpoints(baseUrl, publicUrl))

    suspend fun fetchTtsEngines(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<HttpTTS>> =
        executeWithFailover { it.getAllTts(accessToken) }(buildEndpoints(baseUrl, publicUrl))

    suspend fun addTts(baseUrl: String, publicUrl: String?, accessToken: String, tts: HttpTTS): Result<String> =
        executeWithFailover { it.addTts(accessToken, tts) }(buildEndpoints(baseUrl, publicUrl))

    suspend fun deleteTts(baseUrl: String, publicUrl: String?, accessToken: String, id: String): Result<String> =
        executeWithFailover { it.delTts(accessToken, id) }(buildEndpoints(baseUrl, publicUrl))

    suspend fun importBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        fileUri: Uri,
        context: Context
    ): Result<Any> {
        val filePart = createMultipartBodyPart(fileUri, context)
            ?: return Result.failure(IllegalArgumentException("无法创建文件部分"))

        return executeWithFailover {
            it.importBook(accessToken, filePart)
        }(buildEndpoints(baseUrl, publicUrl))
    }
    
    // region Replace Rules
    suspend fun fetchReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<ReplaceRule>> {
        val pageInfoResult = executeWithFailover {
            it.getReplaceRulesPage(accessToken)
        }(buildEndpoints(baseUrl, publicUrl))

        if (pageInfoResult.isFailure) {
            return Result.failure(pageInfoResult.exceptionOrNull() ?: IllegalStateException("Failed to fetch page info"))
        }
        val pageInfo = pageInfoResult.getOrThrow()

        val totalPages = pageInfo.page
        if (totalPages <= 0 || pageInfo.md5.isBlank()) {
            return Result.success(emptyList())
        }

        val allRules = mutableListOf<ReplaceRule>()
        for (page in 1..totalPages) {
            val result = executeWithFailover {
                it.getReplaceRules(accessToken, pageInfo.md5, page)
            }(buildEndpoints(baseUrl, publicUrl))

            if (result.isSuccess) {
                allRules.addAll(result.getOrThrow())
            } else {
                return Result.failure(result.exceptionOrNull() ?: IllegalStateException("Failed to fetch page $page"))
            }
        }
        return Result.success(allRules)
    }

    suspend fun addReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule): Result<Any> =
        executeWithFailover { it.addReplaceRule(accessToken, rule) }(buildEndpoints(baseUrl, publicUrl))

    suspend fun deleteReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, id: String): Result<Any> =
        executeWithFailover { it.deleteReplaceRule(accessToken, id) }(buildEndpoints(baseUrl, publicUrl))

    suspend fun toggleReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, id: String, isEnabled: Boolean): Result<Any> =
        executeWithFailover { it.toggleReplaceRule(accessToken, id, if (isEnabled) 1 else 0) }(buildEndpoints(baseUrl, publicUrl))
    // endregion

    // region Book Sources
    fun getBookSources(context: Context, baseUrl: String, publicUrl: String?, accessToken: String): Flow<Result<List<com.readapp.data.model.BookSource>>> = flow {
        val cachedSources = loadSourcesFromCache(context)
        if (cachedSources != null) {
            emit(Result.success(cachedSources))
        }

        val pageInfoResult = executeWithFailover {
            it.getBookSourcesPage(accessToken)
        }(buildEndpoints(baseUrl, publicUrl))

        if (pageInfoResult.isFailure) {
            if (cachedSources == null) {
                emit(Result.failure(pageInfoResult.exceptionOrNull() ?: IllegalStateException("Failed to fetch page info")))
            }
            return@flow
        }
        val pageInfo = pageInfoResult.getOrThrow()

        val totalPages = pageInfo.page
        if (totalPages <= 0 || pageInfo.md5.isBlank()) {
            if (cachedSources == null) {
                emit(Result.success(emptyList()))
            }
            return@flow
        }

        val allSources = mutableListOf<com.readapp.data.model.BookSource>()
        for (page in 1..totalPages) {
            val result = executeWithFailover {
                it.getBookSourcesNew(accessToken, pageInfo.md5, page)
            }(buildEndpoints(baseUrl, publicUrl))

            if (result.isSuccess) {
                allSources.addAll(result.getOrThrow())
            } else {
                if (cachedSources == null) {
                    emit(Result.failure(result.exceptionOrNull() ?: IllegalStateException("Failed to fetch page $page")))
                }
                return@flow
            }
        }
        if (allSources != cachedSources) {
            emit(Result.success(allSources))
            saveSourcesToCache(context, allSources)
        }
    }

    suspend fun saveBookSource(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        jsonContent: String
    ): Result<Any> {
        val requestBody = jsonContent.toRequestBody("text/plain".toMediaTypeOrNull())
        return executeWithFailover {
            it.saveBookSource(accessToken, requestBody)
        }(buildEndpoints(baseUrl, publicUrl))
    }

    suspend fun deleteBookSource(
        context: Context,
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        id: String
    ): Result<Any> {
        val result = executeWithFailover {
            it.deleteBookSource(accessToken, id)
        }(buildEndpoints(baseUrl, publicUrl))

        if(result.isSuccess) {
            // Refresh cache
            loadSourcesFromCache(context)?.filter { it.bookSourceUrl != id }?.let {
                saveSourcesToCache(context, it)
            }
        }
        return result
    }

    suspend fun toggleBookSource(
        context: Context,
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        id: String,
        isEnabled: Boolean
    ): Result<Any> {
        val result = executeWithFailover {
            it.toggleBookSource(accessToken, id, if (isEnabled) "1" else "0")
        }(buildEndpoints(baseUrl, publicUrl))

        if(result.isSuccess) {
            // Refresh cache
            loadSourcesFromCache(context)?.map { if(it.bookSourceUrl == id) it.copy(enabled = isEnabled) else it }?.let {
                saveSourcesToCache(context, it)
            }
        }
        return result
    }

    suspend fun getBookSourceDetail(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        id: String
    ): Result<String> = executeWithFailover {
        it.getBookSourceDetail(accessToken, id)
    }(buildEndpoints(baseUrl, publicUrl)).map { map ->
        map["json"] as? String ?: ""
    }
    // endregion

    // region Book Search
    suspend fun searchBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        keyword: String,
        bookSourceUrl: String,
        page: Int
    ): Result<List<Book>> = executeWithFailover {
        it.searchBook(accessToken, keyword, bookSourceUrl, page)
    }(buildEndpoints(baseUrl, publicUrl))

    suspend fun saveBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        book: Book
    ): Result<Any> = executeWithFailover {
        it.saveBook(accessToken, book = book)
    }(buildEndpoints(baseUrl, publicUrl))
    // endregion

    private fun createMultipartBodyPart(fileUri: Uri, context: Context): MultipartBody.Part? {
        return context.contentResolver.openInputStream(fileUri)?.use { inputStream ->
            val fileBytes = inputStream.readBytes()
            val requestFile = fileBytes.toRequestBody(
                context.contentResolver.getType(fileUri)?.toMediaTypeOrNull()
            )
            MultipartBody.Part.createFormData(
                "file",
                getFileName(fileUri, context),
                requestFile
            )
        }
    }

    private fun getFileName(uri: Uri, context: Context): String? {
        var result: String? = null
        if (uri.scheme == "content") {
            val cursor = context.contentResolver.query(uri, null, null, null, null)
            try {
                if (cursor != null && cursor.moveToFirst()) {
                    val columnIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (columnIndex >= 0) {
                        result = cursor.getString(columnIndex)
                    }
                }
            } finally {
                cursor?.close()
            }
        }
        if (result == null) {
            result = uri.path
            val cut = result?.lastIndexOf('/')
            if (cut != -1) {
                if (cut != null) {
                    result = result?.substring(cut + 1)
                }
            }
        }
        return result
    }

    fun buildTtsAudioUrl(baseUrl: String, accessToken: String, ttsId: String, text: String, speechRate: Double): String? {
        val normalized = ensureTrailingSlash(baseUrl)
        return "${normalized}tts".toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("accessToken", accessToken)
            ?.addQueryParameter("id", ttsId)
            ?.addQueryParameter("speakText", text)
            ?.addQueryParameter("speechRate", speechRate.toString())
            ?.build()
            ?.toString()
    }

    private fun buildEndpoints(primary: String, secondary: String?): List<String> {
        val endpoints = mutableListOf<String>()
        if (primary.isNotBlank()) {
            endpoints.add(ensureTrailingSlash(primary))
        }
        if (!secondary.isNullOrBlank() && secondary != primary) {
            endpoints.add(ensureTrailingSlash(secondary))
        }
        return endpoints
    }

    private fun ensureTrailingSlash(url: String): String = if (url.endsWith('/')) url else "$url/"

    private fun <T> executeWithFailover(block: suspend (ReadApiService) -> Response<ApiResponse<T>>):
            suspend (List<String>) -> Result<T> = lambda@ { endpoints: List<String> ->
        var lastError: Throwable? = null
        for (endpoint in endpoints) {
            val api = apiFactory(endpoint)
            try {
                val response = block(api)
                if (response.isSuccessful) {
                    val body = response.body()
                    if (body != null) {
                        if (body.isSuccess) {
                            // API 有些data返回null表示成功，有些返回具体数据
                            @Suppress("UNCHECKED_CAST")
                            return@lambda Result.success(body.data ?: Unit as T)
                        }
                        lastError = IllegalStateException(body.errorMsg ?: "未知错误")
                    } else {
                        lastError = IllegalStateException("响应体为空")
                    }
                } else {
                    lastError = IllegalStateException("服务器返回状态码 ${response.code()}")
                }
            } catch (e: Exception) {
                lastError = e
            }
        }
        Result.failure(lastError ?: IllegalStateException("未知错误"))
    }
}

private typealias BookLoginResult = com.readapp.data.model.LoginResponse
