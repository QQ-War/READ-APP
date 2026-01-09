package com.readapp.data

import android.content.Context
import android.net.Uri
import com.readapp.data.model.ApiResponse
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
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
import com.google.gson.JsonParser
import java.io.File

class ReadRepository(
    private val apiFactory: (String) -> ReadApiService,
    private val readerApiFactory: (String) -> ReaderApiService,
) {

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

    suspend fun login(baseUrl: String, publicUrl: String?, username: String, password: String): Result<BookLoginResult> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover<BookLoginResult> { api ->
                api.login(username, password)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader<BookLoginResult> { api ->
                api.login(ReaderLoginRequest(username = username, password = password, isLogin = true))
            }(endpoints)
        }
    }

    suspend fun getUserInfo(baseUrl: String, publicUrl: String?, accessToken: String): Result<com.readapp.data.model.UserInfo> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.getUserInfo(accessToken) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.getUserInfo(accessToken) }(endpoints)
        }
    }

    suspend fun changePassword(baseUrl: String, publicUrl: String?, accessToken: String, oldPass: String, newPass: String): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.changePassword(accessToken, oldPass, newPass) }(endpoints)
            ApiBackend.Reader -> Result.failure(UnsupportedOperationException("当前服务端不支持修改密码"))
        }
    }

    suspend fun fetchBooks(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<Book>> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        val result = when (backend) {
            ApiBackend.Read -> executeWithFailover { it.getBookshelf(accessToken) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.getBookshelf(accessToken) }(endpoints)
        }
        return result.map { list -> list.map { book -> book.toUiModel() } }
    }

    suspend fun fetchChapterList(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
    ): Result<List<Chapter>> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.getChapterList(accessToken, bookUrl, bookSourceUrl)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.getChapterList(accessToken, bookUrl, bookSourceUrl)
            }(endpoints)
        }
    }

    suspend fun fetchChapterContent(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
        index: Int,
        contentType: Int = 0
    ): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.getBookContent(accessToken, bookUrl, index, contentType, bookSourceUrl)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.getBookContent(accessToken, bookUrl, index, contentType, bookSourceUrl)
            }(endpoints)
        }
    }

    suspend fun saveBookProgress(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        index: Int,
        pos: Double,
        title: String?,
    ): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.saveBookProgress(accessToken, bookUrl, index, pos, title)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.saveBookProgress(
                    accessToken,
                    ReaderSaveBookProgressRequest(url = bookUrl, index = index, pos = pos, title = title)
                )
            }(endpoints)
        }
    }

    suspend fun setBookSource(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        newUrl: String,
        newBookSourceUrl: String
    ): Result<Book> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.setBookSource(accessToken, bookUrl, newUrl, newBookSourceUrl)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.setBookSource(
                    accessToken,
                    ReaderSetBookSourceRequest(bookUrl = bookUrl, newUrl = newUrl, bookSourceUrl = newBookSourceUrl)
                )
            }(endpoints)
        }
    }

    suspend fun fetchDefaultTts(baseUrl: String, publicUrl: String?, accessToken: String): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.getDefaultTts(accessToken) }(endpoints)
            ApiBackend.Reader -> Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))
        }
    }

    suspend fun fetchTtsEngines(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<HttpTTS>> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.getAllTts(accessToken) }(endpoints)
            ApiBackend.Reader -> Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))
        }
    }

    suspend fun addTts(baseUrl: String, publicUrl: String?, accessToken: String, tts: HttpTTS): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.addTts(accessToken, tts) }(endpoints)
            ApiBackend.Reader -> Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))
        }
    }

    suspend fun deleteTts(baseUrl: String, publicUrl: String?, accessToken: String, id: String): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.delTts(accessToken, id) }(endpoints)
            ApiBackend.Reader -> Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))
        }
    }

    suspend fun saveTtsBatch(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        if (backend == ApiBackend.Reader) {
            return Result.failure(UnsupportedOperationException("当前服务端不支持TTS"))
        }
        val requestBody = jsonContent.toRequestBody("text/plain".toMediaTypeOrNull())
        return executeWithFailover {
            it.saveTtsBatch(accessToken, requestBody)
        }(endpoints)
    }

    suspend fun importBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        fileUri: Uri,
        context: Context
    ): Result<Any> {
        val filePart = createMultipartBodyPart(fileUri, context)
            ?: return Result.failure(IllegalArgumentException("无法创建文件部分"))
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.importBook(accessToken, filePart)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.importBook(accessToken, filePart)
            }(endpoints)
        }
    }
    
    // region Replace Rules
    suspend fun fetchReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<ReplaceRule>> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> {
                val pageInfoResult = executeWithFailover {
                    it.getReplaceRulesPage(accessToken)
                }(endpoints)

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
                    }(endpoints)

                    if (result.isSuccess) {
                        allRules.addAll(result.getOrThrow())
                    } else {
                        return Result.failure(result.exceptionOrNull() ?: IllegalStateException("Failed to fetch page $page"))
                    }
                }
                Result.success(allRules)
            }
            ApiBackend.Reader -> executeWithFailoverReader {
                it.getReplaceRules(accessToken)
            }(endpoints)
        }
    }

    suspend fun addReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.addReplaceRule(accessToken, rule) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.saveReplaceRule(accessToken, rule) }(endpoints)
        }
    }

    suspend fun deleteReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.deleteReplaceRule(accessToken, rule.id) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.deleteReplaceRule(accessToken, rule) }(endpoints)
        }
    }

    suspend fun toggleReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule, isEnabled: Boolean): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.toggleReplaceRule(accessToken, rule.id, if (isEnabled) 1 else 0)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.saveReplaceRule(accessToken, rule.copy(isEnabled = isEnabled))
            }(endpoints)
        }
    }

    suspend fun saveReplaceRules(baseUrl: String, publicUrl: String?, accessToken: String, jsonContent: String): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        val requestBody = jsonContent.toRequestBody("text/plain".toMediaTypeOrNull())
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.saveReplaceRules(accessToken, requestBody)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.saveReplaceRules(accessToken, requestBody)
            }(endpoints)
        }
    }
    // endregion

    // region Book Sources
    fun getBookSources(context: Context, baseUrl: String, publicUrl: String?, accessToken: String): Flow<Result<List<com.readapp.data.model.BookSource>>> = flow {
        val cachedSources = loadSourcesFromCache(context)
        if (cachedSources != null) {
            emit(Result.success(cachedSources))
        }

        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        when (backend) {
            ApiBackend.Read -> {
                val pageInfoResult = executeWithFailover {
                    it.getBookSourcesPage(accessToken)
                }(endpoints)

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
                    }(endpoints)

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
            ApiBackend.Reader -> {
                val result = executeWithFailoverReader {
                    it.getBookSources(accessToken)
                }(endpoints)
                if (result.isSuccess) {
                    val sources = result.getOrThrow()
                    emit(Result.success(sources))
                    saveSourcesToCache(context, sources)
                } else if (cachedSources == null) {
                    emit(Result.failure(result.exceptionOrNull() ?: IllegalStateException("Failed to fetch sources")))
                }
            }
        }
    }

    suspend fun saveBookSource(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        jsonContent: String
    ): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        val mediaType = if (backend == ApiBackend.Read) "text/plain" else "application/json"
        val requestBody = jsonContent.toRequestBody(mediaType.toMediaTypeOrNull())
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.saveBookSource(accessToken, requestBody)
            }(endpoints)
            ApiBackend.Reader -> {
                val isArray = jsonContent.trimStart().startsWith("[")
                if (isArray) {
                    executeWithFailoverReader { it.saveBookSources(accessToken, requestBody) }(endpoints)
                } else {
                    executeWithFailoverReader { it.saveBookSource(accessToken, requestBody) }(endpoints)
                }
            }
        }
    }

    suspend fun deleteBookSource(
        context: Context,
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        source: BookSource
    ): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        val result = when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.deleteBookSource(accessToken, source.bookSourceUrl)
            }(endpoints)
            ApiBackend.Reader -> {
                val payload = gson.toJson(mapOf("bookSourceUrl" to source.bookSourceUrl))
                val requestBody = payload.toRequestBody("application/json".toMediaTypeOrNull())
                executeWithFailoverReader {
                    it.deleteBookSource(accessToken, requestBody)
                }(endpoints)
            }
        }

        if(result.isSuccess) {
            // Refresh cache
            loadSourcesFromCache(context)?.filter { it.bookSourceUrl != source.bookSourceUrl }?.let {
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
        source: BookSource,
        isEnabled: Boolean
    ): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        val result = when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.toggleBookSource(accessToken, source.bookSourceUrl, if (isEnabled) "1" else "0")
            }(endpoints)
            ApiBackend.Reader -> {
                val detailResult = executeWithFailoverReader {
                    it.getBookSource(accessToken, source.bookSourceUrl)
                }(endpoints)
                if (detailResult.isFailure) {
                    detailResult
                } else {
                    val detailJson = gson.toJson(detailResult.getOrThrow())
                    val updated = updateJsonBoolean(detailJson, "enabled", isEnabled)
                    val requestBody = updated.toRequestBody("application/json".toMediaTypeOrNull())
                    executeWithFailoverReader {
                        it.saveBookSource(accessToken, requestBody)
                    }(endpoints)
                }
            }
        }

        if(result.isSuccess) {
            // Refresh cache
            loadSourcesFromCache(context)?.map { if(it.bookSourceUrl == source.bookSourceUrl) it.copy(enabled = isEnabled) else it }?.let {
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
    ): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.getBookSourceDetail(accessToken, id)
            }(endpoints).map { map ->
                map["json"] as? String ?: ""
            }
            ApiBackend.Reader -> executeWithFailoverReader {
                it.getBookSource(accessToken, id)
            }(endpoints).map { json ->
                gson.toJson(json)
            }
        }
    }

    suspend fun fetchExploreKinds(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookSourceUrl: String
    ): Result<String> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.getExploreUrl(accessToken, bookSourceUrl)
            }(endpoints).map { map ->
                map["found"] ?: ""
            }
            ApiBackend.Reader -> executeWithFailoverReader {
                it.getBookSource(accessToken, bookSourceUrl)
            }(endpoints).map { json ->
                val exploreElement = json.get("exploreUrl")
                val exploreUrl = if (exploreElement != null && !exploreElement.isJsonNull) {
                    exploreElement.asString
                } else {
                    null
                }
                parseExploreKindsJson(exploreUrl)
            }
        }
    }

    suspend fun exploreBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookSourceUrl: String,
        ruleFindUrl: String,
        page: Int
    ): Result<List<Book>> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.exploreBook(accessToken, bookSourceUrl, ruleFindUrl, page)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.exploreBook(accessToken, bookSourceUrl, ruleFindUrl, page)
            }(endpoints)
        }
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
    ): Result<List<Book>> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.searchBook(accessToken, keyword, bookSourceUrl, page)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.searchBook(accessToken, keyword, bookSourceUrl, page)
            }(endpoints)
        }
    }

    suspend fun saveBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        book: Book
    ): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.saveBook(accessToken, book = book)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.saveBook(accessToken, book)
            }(endpoints)
        }
    }

    suspend fun deleteBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        book: Book
    ): Result<Any> {
        val (backend, endpoints) = resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.deleteBook(accessToken, book = book)
            }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader {
                it.deleteBook(accessToken, book)
            }(endpoints)
        }
    }
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
        if (detectApiBackend(baseUrl) == ApiBackend.Reader) {
            return null
        }
        val normalized = ensureTrailingSlash(baseUrl)
        return "${normalized}tts".toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("accessToken", accessToken)
            ?.addQueryParameter("id", ttsId)
            ?.addQueryParameter("speakText", text)
            ?.addQueryParameter("speechRate", speechRate.toString())
            ?.build()
            ?.toString()
    }

    private fun resolveBackend(baseUrl: String): ApiBackend = detectApiBackend(baseUrl)

    private fun buildEndpoints(primary: String, secondary: String?, backend: ApiBackend): List<String> {
        val endpoints = mutableListOf<String>()
        if (primary.isNotBlank()) {
            endpoints.add(ensureTrailingSlash(normalizeApiBaseUrl(primary, backend)))
        }
        if (!secondary.isNullOrBlank() && secondary != primary) {
            endpoints.add(ensureTrailingSlash(normalizeApiBaseUrl(secondary, backend)))
        }
        return endpoints
    }

    private fun resolveBackendAndEndpoints(baseUrl: String, publicUrl: String?): Pair<ApiBackend, List<String>> {
        val backend = resolveBackend(baseUrl)
        return backend to buildEndpoints(baseUrl, publicUrl, backend)
    }

    private fun ensureTrailingSlash(url: String): String = if (url.endsWith('/')) url else "$url/"

    private fun <T> executeWithFailover(block: suspend (ReadApiService) -> Response<ApiResponse<T>>):
            suspend (List<String>) -> Result<T> = lambda@ { endpoints: List<String> ->
        var lastError: Throwable? = null
        for (endpoint in endpoints) {
            val api = apiFactory(endpoint)
            try {
                val response = block(api)
                val result = handleResponse(response)
                if (result.isSuccess) {
                    return@lambda result
                }
                lastError = result.exceptionOrNull()
            } catch (e: Exception) {
                lastError = e
            }
        }
        Result.failure(lastError ?: IllegalStateException("未知错误"))
    }

    private fun <T> executeWithFailoverReader(block: suspend (ReaderApiService) -> Response<ApiResponse<T>>):
            suspend (List<String>) -> Result<T> = lambda@ { endpoints: List<String> ->
        var lastError: Throwable? = null
        for (endpoint in endpoints) {
            val api = readerApiFactory(endpoint)
            try {
                val response = block(api)
                val result = handleResponse(response)
                if (result.isSuccess) {
                    return@lambda result
                }
                lastError = result.exceptionOrNull()
            } catch (e: Exception) {
                lastError = e
            }
        }
        Result.failure(lastError ?: IllegalStateException("未知错误"))
    }

    private fun <T> handleResponse(response: Response<ApiResponse<T>>): Result<T> {
        if (response.isSuccessful) {
            val body = response.body()
            if (body != null) {
                if (body.isSuccess) {
                    @Suppress("UNCHECKED_CAST")
                    return Result.success(body.data ?: Unit as T)
                }
                return Result.failure(IllegalStateException(body.errorMsg ?: "未知错误"))
            }
            return Result.failure(IllegalStateException("响应体为空"))
        }
        return Result.failure(IllegalStateException("服务器返回状态码 ${response.code()}"))
    }

    private fun updateJsonBoolean(json: String, field: String, value: Boolean): String {
        return runCatching {
            val obj = JsonParser().parse(json).asJsonObject
            obj.addProperty(field, value)
            gson.toJson(obj)
        }.getOrDefault(json)
    }

    private fun parseExploreKindsJson(exploreUrl: String?): String {
        if (exploreUrl.isNullOrBlank()) return "[]"
        val trimmed = exploreUrl.trim()
        if (trimmed.startsWith("[")) {
            return trimmed
        }
        val separators = listOf("::", "##", "：")
        val entries = trimmed
            .split("\n", "&&")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        val kinds = entries.map { entry ->
            val parts = separators.firstNotNullOfOrNull { sep ->
                if (entry.contains(sep)) entry.split(sep, limit = 2) else null
            }
            val title = parts?.getOrNull(0)?.trim()?.ifBlank { entry } ?: entry
            val url = parts?.getOrNull(1)?.trim()?.ifBlank { entry } ?: entry
            BookSource.ExploreKind(title = title, url = url)
        }
        return gson.toJson(kinds)
    }
}

private typealias BookLoginResult = com.readapp.data.model.LoginResponse
