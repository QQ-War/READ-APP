package com.readapp.data

import android.content.Context
import android.net.Uri
import com.readapp.data.model.ApiResponse
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import com.readapp.data.model.LoginResponse
import com.readapp.data.model.ReplaceRule
import com.readapp.data.model.RssEditPayload
import com.readapp.data.model.RssSourceItem
import com.readapp.data.model.RssSourcePayload
import com.readapp.data.model.ReaderBookTtsRequest
import com.readapp.data.model.TtsAudioRequest
import com.readapp.data.model.toPayload
import com.readapp.data.model.RssSourcesResponse
import android.util.Base64
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import retrofit2.Response
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import com.google.gson.Gson
import com.google.gson.JsonParser
import java.io.File
import java.util.Locale

class ReadRepository(
    private val apiFactory: (String) -> ReadApiService,
    private val readerApiFactory: (String) -> ReaderApiService,
) {

    private val gson = Gson()
    private val httpClient = okhttp3.OkHttpClient.Builder().build()
    private val SOURCES_CACHE_FILE = "sources_cache.json"
    private val failoverClient = FailoverClient(apiFactory, readerApiFactory)

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

    suspend fun login(baseUrl: String, publicUrl: String?, username: String, password: String): Result<LoginResponse> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> failoverClient.runRead(endpoints) { api ->
                api.login(username, password)
            }
            ApiBackend.Reader -> failoverClient.runReader(endpoints) { api ->
                api.login(ReaderLoginRequest(username = username, password = password, isLogin = true))
            }
        }
    }

    suspend fun getUserInfo(baseUrl: String, publicUrl: String?, accessToken: String): Result<com.readapp.data.model.UserInfo> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> failoverClient.runRead(endpoints) { it.getUserInfo(accessToken) }
            ApiBackend.Reader -> failoverClient.runReader(endpoints) { it.getUserInfo(accessToken) }
        }
    }

    suspend fun changePassword(baseUrl: String, publicUrl: String?, accessToken: String, oldPass: String, newPass: String): Result<String> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> failoverClient.runRead(endpoints) { it.changePassword(accessToken, oldPass, newPass) }
            ApiBackend.Reader -> Result.failure(UnsupportedOperationException("当前服务端不支持修改密码"))
        }
    }

    suspend fun fetchBooks(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<Book>> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        val result = when (backend) {
            ApiBackend.Read -> executeWithFailover { it.getBookshelf(accessToken) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.getBookshelf(accessToken) }(endpoints)
        }
        return result.map { list ->
            list.map { book ->
                val resolvedCover = resolveCoverUrl(baseUrl, book.coverUrl)
                book.copy(coverUrl = resolvedCover).toUiModel()
            }
        }
    }

    suspend fun fetchChapterList(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
    ): Result<List<Chapter>> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.getBookContent(accessToken, bookUrl, index, contentType, bookSourceUrl)
            }(endpoints)
            ApiBackend.Reader -> {
                val result = executeWithFailoverReader {
                    it.getBookContent(accessToken, bookUrl, index, contentType, bookSourceUrl)
                }(endpoints)
                result.fold(
                    onSuccess = { raw ->
                        val resolved = resolveReaderLocalContentIfNeeded(raw, baseUrl, publicUrl)
                        Result.success(resolved)
                    },
                    onFailure = { error -> Result.failure(error) }
                )
            }
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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

    suspend fun importBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        fileUri: Uri,
        context: Context
    ): Result<Any> {
        val filePart = FileUploadHelper.createMultipartBodyPart(fileUri, context)
            ?: return Result.failure(IllegalArgumentException("无法创建文件部分"))
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.addReplaceRule(accessToken, rule) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.saveReplaceRule(accessToken, rule) }(endpoints)
        }
    }

    suspend fun deleteReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule): Result<Any> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.deleteReplaceRule(accessToken, rule.id) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.deleteReplaceRule(accessToken, rule) }(endpoints)
        }
    }

    suspend fun toggleReplaceRule(baseUrl: String, publicUrl: String?, accessToken: String, rule: ReplaceRule, isEnabled: Boolean): Result<Any> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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

        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.exploreBook(accessToken, bookSourceUrl, ruleFindUrl, page)
            }(endpoints).map { list ->
                list.map { book ->
                    val resolvedCover = resolveCoverUrl(baseUrl, book.coverUrl)
                    book.copy(coverUrl = resolvedCover)
                }
            }
            ApiBackend.Reader -> executeWithFailoverReader {
                it.exploreBook(accessToken, bookSourceUrl, ruleFindUrl, page)
            }(endpoints).map { list ->
                list.map { book ->
                    val resolvedCover = resolveCoverUrl(baseUrl, book.coverUrl)
                    book.copy(coverUrl = resolvedCover)
                }
            }
        }
    }

    // region RSS Sources
    suspend fun fetchRssSources(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String
    ): Result<RssSourcesResponse> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.getRssSources(accessToken) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.getRssSources(accessToken) }(endpoints)
        }
    }

    suspend fun toggleRssSource(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        sourceUrl: String,
        isEnabled: Boolean
    ): Result<Any> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        val status = if (isEnabled) 1 else 0
        return when (backend) {
            ApiBackend.Read -> executeWithFailover { it.stopRssSource(accessToken, sourceUrl, status) }(endpoints)
            ApiBackend.Reader -> executeWithFailoverReader { it.stopRssSource(accessToken, sourceUrl, status) }(endpoints)
        }
    }

    suspend fun saveRssSource(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        remoteId: String?,
        source: RssSourceItem
    ): Result<Any> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        if (backend != ApiBackend.Read) {
            return Result.failure(UnsupportedOperationException("当前服务端不支持编辑订阅源"))
        }
        val payload = RssEditPayload(
            json = gson.toJson(source.toPayload()),
            id = remoteId
        )
        return executeWithFailover { it.editRssSources(accessToken, payload) }(endpoints)
    }

    suspend fun deleteRssSource(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        sourceUrl: String
    ): Result<Any> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        if (backend != ApiBackend.Read) {
            return Result.failure(UnsupportedOperationException("当前服务端不支持删除订阅源"))
        }
        return executeWithFailover { it.deleteRssSource(accessToken, sourceUrl) }(endpoints)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
        return when (backend) {
            ApiBackend.Read -> executeWithFailover {
                it.searchBook(accessToken, keyword, bookSourceUrl, page)
            }(endpoints).map { list ->
                list.map { book ->
                    val resolvedCover = resolveCoverUrl(baseUrl, book.coverUrl)
                    book.copy(coverUrl = resolvedCover)
                }
            }
            ApiBackend.Reader -> executeWithFailoverReader {
                it.searchBook(accessToken, keyword, bookSourceUrl, page)
            }(endpoints).map { list ->
                list.map { book ->
                    val resolvedCover = resolveCoverUrl(baseUrl, book.coverUrl)
                    book.copy(coverUrl = resolvedCover)
                }
            }
        }
    }

    suspend fun saveBook(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        book: Book
    ): Result<Any> {
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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
        val (backend, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, publicUrl)
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

    fun buildTtsAudioRequest(
        baseUrl: String,
        accessToken: String,
        tts: HttpTTS,
        text: String,
        speechRate: Double,
        isChapterTitle: Boolean
    ): TtsAudioRequest? {
        val backend = detectApiBackend(baseUrl)
        return when (backend) {
            ApiBackend.Read -> {
                val normalized = BackendResolver.ensureTrailingSlash(baseUrl)
                val url = "${normalized}tts".toHttpUrlOrNull()?.newBuilder()
                    ?.addQueryParameter("accessToken", accessToken)
                    ?.addQueryParameter("id", tts.id)
                    ?.addQueryParameter("speakText", text)
                    ?.addQueryParameter("speechRate", speechRate.toString())
                    ?.build()
                    ?.toString()
                url?.let { TtsAudioRequest.Url(it) }
            }
            ApiBackend.Reader -> {
                val voiceName = tts.name.takeIf { it.isNotBlank() } ?: return null
                val normalizedRate = speechRate.coerceIn(0.2, 4.0)
                val pitch = if (isChapterTitle) 1.05 else 1.0
                TtsAudioRequest.Reader(
                    voiceName = voiceName,
                    text = text,
                    speechRate = normalizedRate,
                    pitch = pitch
                )
            }
        }
    }

    suspend fun fetchReaderTtsAudio(
        baseUrl: String,
        accessToken: String,
        request: TtsAudioRequest.Reader
    ): Result<ByteArray> {
        if (detectApiBackend(baseUrl) != ApiBackend.Reader) {
            return Result.failure(IllegalStateException("当前服务端不支持TTS"))
        }
        val (_, endpoints) = BackendResolver.resolveBackendAndEndpoints(baseUrl, null)
        val payload = ReaderBookTtsRequest(
            text = request.text,
            voice = request.voiceName,
            pitch = formatDecimal(request.pitch),
            rate = formatDecimal(request.speechRate),
            accessToken = accessToken
        )
        val timestamp = System.currentTimeMillis()
        return executeWithFailoverReader {
            it.requestBookTts(accessToken, timestamp, payload)
        }(endpoints).mapCatching { base64 ->
            if (base64.isBlank()) throw IllegalStateException("TTS返回空音频数据")
            Base64.decode(base64, Base64.DEFAULT)
        }
    }

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

    private fun formatDecimal(value: Double): String =
        String.format(Locale.US, "%.2f", value)

    private fun resolveCoverUrl(baseUrl: String, coverUrl: String?): String? {
        if (coverUrl.isNullOrBlank()) return coverUrl
        val trimmed = coverUrl.trim()
        if (trimmed.equals("null", true) || trimmed.equals("nil", true) || trimmed.equals("undefined", true)) {
            return null
        }
        val root = stripApiBasePath(baseUrl)
        return when {
            trimmed.startsWith("baseurl/") -> "$root/$trimmed"
            trimmed.startsWith("/") -> root + trimmed
            trimmed.startsWith("assets/") || trimmed.startsWith("book-assets/") -> "$root/$trimmed"
            else -> trimmed
        }
    }

    private suspend fun resolveReaderLocalContentIfNeeded(rawContent: String, baseUrl: String, publicUrl: String?): String {
        if (rawContent.isBlank()) return rawContent
        val trimmed = rawContent.trim()
        if (trimmed.isEmpty()) return rawContent
        if (trimmed.contains("<")) return rawContent

        val looksLikeAsset = trimmed.contains("/book-assets/")
        val looksLikeHtml = trimmed.contains(".xhtml", ignoreCase = true) || trimmed.contains(".html", ignoreCase = true)
        if (!looksLikeAsset && !looksLikeHtml) return rawContent

        val baseRoot = stripApiBasePath(baseUrl)
        val publicRoot = publicUrl?.takeIf { it.isNotBlank() }?.let { stripApiBasePath(it) }
        var normalized = trimmed
        if (normalized.startsWith("__API_ROOT__")) {
            normalized = normalized.removePrefix("__API_ROOT__")
        }
        val path = if (normalized.startsWith("/")) normalized else "/$normalized"

        val candidates = mutableListOf<String>()
        if (normalized.contains("://")) {
            candidates.add(buildEncodedAbsoluteUrl(normalized))
            if (publicRoot != null && normalized.startsWith(baseRoot)) {
                candidates.add(buildEncodedAbsoluteUrl(normalized.replaceFirst(baseRoot, publicRoot)))
            }
        } else {
            candidates.add(baseRoot + customURLEncodePath(path))
            if (publicRoot != null) {
                candidates.add(publicRoot + customURLEncodePath(path))
            }
        }

        for (url in candidates.distinct()) {
            val fetched = fetchTextContent(url)
            if (!fetched.isNullOrBlank()) return fetched
        }
        return rawContent
    }

    private fun buildEncodedAbsoluteUrl(urlString: String): String {
        val schemeIndex = urlString.indexOf("://")
        if (schemeIndex <= 0) return customURLEncodePath(urlString)
        val scheme = urlString.substring(0, schemeIndex + 3)
        val rest = urlString.substring(schemeIndex + 3)
        val slashIndex = rest.indexOf('/')
        if (slashIndex < 0) return urlString
        val host = rest.substring(0, slashIndex)
        val path = rest.substring(slashIndex)
        return scheme + host + customURLEncodePath(path)
    }

    private fun customURLEncodePath(input: String): String {
        val allowed = "-._~,!*'()/?&=:@"
        val sb = StringBuilder(input.length)
        input.forEach { ch ->
            val isAllowed = ch.isLetterOrDigit() || allowed.indexOf(ch) >= 0
            if (isAllowed) {
                sb.append(ch)
            } else {
                ch.toString().toByteArray().forEach { byte ->
                    sb.append(String.format("%%%02X", byte))
                }
            }
        }
        return sb.toString()
    }

    private suspend fun fetchTextContent(url: String): String? = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        runCatching {
            val request = okhttp3.Request.Builder().url(url).get().build()
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use null
                response.body?.string()
            }
        }.getOrNull()
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
