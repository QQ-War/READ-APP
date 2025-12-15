package com.readapp.android.data

import com.readapp.android.model.Book
import com.readapp.android.model.BookChapter
import com.readapp.android.model.HttpTTS
import com.readapp.android.model.LoginResponse
import com.readapp.android.model.UserInfo
import okhttp3.HttpUrl
import retrofit2.Response

class ReadRepository(private val apiFactory: (String) -> ReadApiService) {

    suspend fun login(baseUrl: String, publicUrl: String?, username: String, password: String): Result<LoginResponse> {
        val endpoints = buildEndpoints(baseUrl, publicUrl)
        return executeWithFailover(endpoints) { api ->
            api.login(username, password)
        }
    }

    suspend fun fetchUserInfo(baseUrl: String, publicUrl: String?, accessToken: String): Result<UserInfo> {
        val endpoints = buildEndpoints(baseUrl, publicUrl)
        return executeWithFailover(endpoints) { api ->
            api.getUserInfo(accessToken)
        }
    }

    suspend fun fetchBooks(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<Book>> {
        val endpoints = buildEndpoints(baseUrl, publicUrl)
        return executeWithFailover(endpoints) { api ->
            api.getBookshelf(accessToken)
        }
    }

    suspend fun fetchChapterList(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?
    ): Result<List<BookChapter>> {
        val endpoints = buildEndpoints(baseUrl, publicUrl)
        return executeWithFailover(endpoints) { api ->
            api.getChapterList(accessToken, bookUrl, bookSourceUrl)
        }
    }

    suspend fun fetchChapterContent(
        baseUrl: String,
        publicUrl: String?,
        accessToken: String,
        bookUrl: String,
        bookSourceUrl: String?,
        index: Int
    ): Result<String> {
        val endpoints = buildEndpoints(baseUrl, publicUrl)
        return executeWithFailover(endpoints) { api ->
            api.getBookContent(accessToken, bookUrl, index, 0, bookSourceUrl)
        }
    }

    suspend fun saveBookProgress(
        baseUrl: String,
        accessToken: String,
        bookUrl: String,
        index: Int,
        pos: Double,
        title: String?
    ) {
        val endpoint = ensureTrailingSlash(baseUrl)
        val api = apiFactory(endpoint)
        runCatching {
            api.saveBookProgress(accessToken, bookUrl, index, pos, title)
        }
    }

    suspend fun fetchTtsEngines(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<HttpTTS>> {
        val endpoints = buildEndpoints(baseUrl, publicUrl)
        return executeWithFailover(endpoints) { api ->
            api.getAllTts(accessToken)
        }
    }

    suspend fun fetchDefaultTts(baseUrl: String, publicUrl: String?, accessToken: String): Result<String> {
        val endpoints = buildEndpoints(baseUrl, publicUrl)
        return executeWithFailover(endpoints) { api ->
            api.getDefaultTts(accessToken)
        }
    }

    fun buildTtsAudioUrl(baseUrl: String, accessToken: String, ttsId: String, text: String, speechRate: Double): String? {
        val normalized = ensureTrailingSlash(baseUrl)
        val url = HttpUrl.parse("${normalized}tts")?.newBuilder()
            ?.addQueryParameter("accessToken", accessToken)
            ?.addQueryParameter("id", ttsId)
            ?.addQueryParameter("speakText", text)
            ?.addQueryParameter("speechRate", speechRate.toString())
            ?.build()
        return url?.toString()
    }

    private fun buildEndpoints(primary: String, secondary: String?): List<String> {
        val normalizedPrimary = ensureTrailingSlash(primary)
        val endpoints = mutableListOf(normalizedPrimary)
        if (!secondary.isNullOrBlank()) {
            endpoints.add(ensureTrailingSlash(secondary))
        }
        return endpoints
    }

    private fun ensureTrailingSlash(url: String): String = if (url.endsWith('/')) url else "$url/"

    private suspend fun <T> executeWithFailover(
        endpoints: List<String>,
        block: suspend (ReadApiService) -> Response<com.readapp.android.model.ApiResponse<T>>
    ): Result<T> {
        var lastError: Throwable? = null
        for (endpoint in endpoints) {
            val api = apiFactory(endpoint)
            try {
                val response = block(api)
                if (response.isSuccessful) {
                    val body = response.body()
                    if (body != null && body.isSuccess && body.data != null) {
                        return Result.success(body.data)
                    }
                    lastError = IllegalStateException(body?.errorMsg ?: "未知错误")
                } else {
                    lastError = IllegalStateException("服务器返回状态码 ${response.code()}")
                }
            } catch (e: Exception) {
                lastError = e
            }
        }
        return Result.failure(lastError ?: IllegalStateException("未知错误"))
    }
}
