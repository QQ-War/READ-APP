package com.readapp.data

import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.data.model.HttpTTS
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import retrofit2.Response

class ReadRepository(private val apiFactory: (String) -> ReadApiService) {

    suspend fun login(baseUrl: String, publicUrl: String?, username: String, password: String) =
        executeWithFailover<BookLoginResult> {
            val api = it
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

    suspend fun fetchDefaultTts(baseUrl: String, publicUrl: String?, accessToken: String): Result<String> =
        executeWithFailover { it.getDefaultTts(accessToken) }(buildEndpoints(baseUrl, publicUrl))

    suspend fun fetchTtsEngines(baseUrl: String, publicUrl: String?, accessToken: String): Result<List<HttpTTS>> =
        executeWithFailover { it.getAllTts(accessToken) }(buildEndpoints(baseUrl, publicUrl))

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
        val normalizedPrimary = ensureTrailingSlash(primary)
        val endpoints = mutableListOf(normalizedPrimary)
        if (!secondary.isNullOrBlank()) {
            endpoints.add(ensureTrailingSlash(secondary))
        }
        return endpoints
    }

    private fun ensureTrailingSlash(url: String): String = if (url.endsWith('/')) url else "$url/"

    private fun <T> executeWithFailover(block: suspend (ReadApiService) -> Response<com.readapp.data.model.ApiResponse<T>>) =
        { endpoints: List<String> ->
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
            Result.failure(lastError ?: IllegalStateException("未知错误"))
        }
}

private typealias BookLoginResult = com.readapp.data.model.LoginResponse
