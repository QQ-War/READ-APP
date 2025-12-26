package com.readapp.data.model

import com.google.gson.annotations.SerializedName

data class ApiResponse<T>(
    @SerializedName("isSuccess") val isSuccess: Boolean,
    @SerializedName("errorMsg") val errorMsg: String?,
    @SerializedName("data") val data: T?,
)

data class HttpTTS(
    @SerializedName("id") val id: String,
    @SerializedName("userid") val userid: String? = null,
    @SerializedName("name") val name: String,
    @SerializedName("url") val url: String,
    @SerializedName("contentType") val contentType: String? = null,
    @SerializedName("concurrentRate") val concurrentRate: String? = null,
    @SerializedName("loginUrl") val loginUrl: String? = null,
    @SerializedName("loginUi") val loginUi: String? = null,
    @SerializedName("header") val header: String? = null,
    @SerializedName("enabledCookieJar") val enabledCookieJar: Boolean? = null,
    @SerializedName("loginCheckJs") val loginCheckJs: String? = null,
    @SerializedName("lastUpdateTime") val lastUpdateTime: Long? = null,
)

data class LoginResponse(
    @SerializedName("accessToken") val accessToken: String,
)

data class UserInfo(
    @SerializedName("username") val username: String? = null,
    @SerializedName("phone") val phone: String? = null,
    @SerializedName("email") val email: String? = null,
)
