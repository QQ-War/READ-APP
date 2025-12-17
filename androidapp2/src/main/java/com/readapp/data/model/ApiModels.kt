package com.readapp.data.model

import com.squareup.moshi.Json

data class ApiResponse<T>(
    @Json(name = "isSuccess") val isSuccess: Boolean,
    @Json(name = "errorMsg") val errorMsg: String?,
    @Json(name = "data") val data: T?,
)

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
    val lastUpdateTime: Long? = null,
)

data class LoginResponse(
    @Json(name = "accessToken") val accessToken: String,
)

data class UserInfo(
    val username: String? = null,
    val phone: String? = null,
    val email: String? = null,
)
