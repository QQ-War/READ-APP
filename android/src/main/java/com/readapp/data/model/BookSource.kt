package com.readapp.data.model

import com.google.gson.annotations.SerializedName

data class BookSource(
    @SerializedName("bookSourceName")
    val bookSourceName: String,

    @SerializedName("bookSourceGroup")
    val bookSourceGroup: String?,

    @SerializedName("bookSourceUrl")
    val bookSourceUrl: String,

    @SerializedName("bookSourceType")
    val bookSourceType: Int?,

    @SerializedName("customOrder")
    val customOrder: Int?,

    @SerializedName("enabled")
    val enabled: Boolean,

    @SerializedName("enabledExplore")
    val enabledExplore: Boolean?,

    @SerializedName("lastUpdateTime")
    val lastUpdateTime: Long?,

    @SerializedName("weight")
    val weight: Int?,

    @SerializedName("bookSourceComment")
    val bookSourceComment: String?,

    @SerializedName("exploreUrl")
    val exploreUrl: String? = null,

    @SerializedName("respondTime")
    val respondTime: Long?
) {
    data class ExploreKind(
        val title: String = "",
        val url: String = ""
    )
}

data class BookSourcePageInfo(
    @SerializedName("page")
    val page: Int,
    @SerializedName("md5")
    val md5: String
)
