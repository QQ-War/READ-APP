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

data class RssSourcesResponse(
    @SerializedName("sources") val sources: List<RssSourceItem> = emptyList(),
    @SerializedName("can") val can: Boolean = false,
)

data class RssSourcePayload(
    @SerializedName("sourceUrl") val sourceUrl: String,
    @SerializedName("sourceName") val sourceName: String?,
    @SerializedName("sourceIcon") val sourceIcon: String?,
    @SerializedName("sourceGroup") val sourceGroup: String?,
    @SerializedName("loginUrl") val loginUrl: String?,
    @SerializedName("loginUi") val loginUi: String?,
    @SerializedName("variableComment") val variableComment: String?,
    @SerializedName("enabled") val enabled: Boolean,
)

data class RssEditPayload(
    @SerializedName("json") val json: String,
    @SerializedName("id") val id: String? = null,
)

data class RssSourceItem(
    @SerializedName("sourceUrl") val sourceUrl: String,
    @SerializedName("sourceName") val sourceName: String? = null,
    @SerializedName("sourceIcon") val sourceIcon: String? = null,
    @SerializedName("sourceGroup") val sourceGroup: String? = null,
    @SerializedName("loginUrl") val loginUrl: String? = null,
    @SerializedName("loginUi") val loginUi: String? = null,
    @SerializedName("variableComment") val variableComment: String? = null,
    @SerializedName("enabled") val enabled: Boolean = false,
)
