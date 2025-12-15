package com.readapp.android.model

import com.squareup.moshi.Json

// MARK: - API Response

data class ApiResponse<T>(
    @Json(name = "isSuccess") val isSuccess: Boolean,
    @Json(name = "errorMsg") val errorMsg: String?,
    @Json(name = "data") val data: T?
)

// MARK: - Book Model

data class Book(
    val name: String? = null,
    val author: String? = null,
    val bookUrl: String? = null,
    val origin: String? = null,
    val originName: String? = null,
    val coverUrl: String? = null,
    val intro: String? = null,
    val durChapterTitle: String? = null,
    val durChapterIndex: Int? = null,
    val durChapterPos: Double? = null,
    val totalChapterNum: Int? = null,
    val latestChapterTitle: String? = null,
    val kind: String? = null,
    val type: Int? = null,
    val durChapterTime: Long? = null
) {
    val id: String = bookUrl ?: name.orEmpty()
}

// MARK: - Chapter Model

data class BookChapter(
    val title: String,
    val url: String,
    val index: Int,
    val isVolume: Boolean? = null,
    val isPay: Boolean? = null
)

// MARK: - HttpTTS Model

data class HttpTTS(
    val id: String,
    val userid: String? = null,
    val name: String,
    val url: String,
    val contentType: String? = null,
    val concurrentRate: String? = null,
    val loginUrl: String? = null,
    val loginUi: String? = null,
    val header: String? = null,
    val enabledCookieJar: Boolean? = null,
    val loginCheckJs: String? = null,
    val lastUpdateTime: Long? = null
)

// MARK: - Login Response

data class LoginResponse(
    @Json(name = "accessToken") val accessToken: String
)

// MARK: - User Info

data class UserInfo(
    val username: String? = null,
    val phone: String? = null,
    val email: String? = null
)
