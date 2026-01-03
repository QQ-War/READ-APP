package com.readapp.data.model

import com.google.gson.annotations.SerializedName

data class FullBookSource(
    @SerializedName("bookSourceName")
    var bookSourceName: String = "",
    @SerializedName("bookSourceGroup")
    var bookSourceGroup: String? = null,
    @SerializedName("bookSourceUrl")
    var bookSourceUrl: String = "",
    @SerializedName("bookSourceType")
    var bookSourceType: Int = 0,
    @SerializedName("bookUrlPattern")
    var bookUrlPattern: String? = null,
    @SerializedName("customOrder")
    var customOrder: Int = 0,
    @SerializedName("enabled")
    var enabled: Boolean = true,
    @SerializedName("enabledExplore")
    var enabledExplore: Boolean = true,
    @SerializedName("concurrentRate")
    var concurrentRate: String? = null,
    @SerializedName("header")
    var header: String? = null,
    @SerializedName("loginUrl")
    var loginUrl: String? = null,
    @SerializedName("loginCheckJs")
    var loginCheckJs: String? = null,
    @SerializedName("lastUpdateTime")
    var lastUpdateTime: Long = 0,
    @SerializedName("weight")
    var weight: Int = 0,
    @SerializedName("exploreUrl")
    var exploreUrl: String? = null,
    @SerializedName("ruleExplore")
    var ruleExplore: ExploreRule? = null,
    @SerializedName("searchUrl")
    var searchUrl: String? = null,
    @SerializedName("ruleSearch")
    var ruleSearch: SearchRule? = null,
    @SerializedName("ruleBookInfo")
    var ruleBookInfo: BookInfoRule? = null,
    @SerializedName("ruleToc")
    var ruleToc: TocRule? = null,
    @SerializedName("ruleContent")
    var ruleContent: ContentRule? = null,
    @SerializedName("bookSourceComment")
    var bookSourceComment: String? = null,
    @SerializedName("respondTime")
    var respondTime: Long = 180000,
    @SerializedName("enabledCookieJar")
    var enabledCookieJar: Boolean? = false
)

data class SearchRule(
    var bookList: String? = null,
    var name: String? = null,
    var author: String? = null,
    var intro: String? = null,
    var kind: String? = null,
    var lastChapter: String? = null,
    var updateTime: String? = null,
    var bookUrl: String? = null,
    var coverUrl: String? = null,
    var wordCount: String? = null
)

data class ExploreRule(
    var bookList: String? = null,
    var name: String? = null,
    var author: String? = null,
    var intro: String? = null,
    var kind: String? = null,
    var lastChapter: String? = null,
    var updateTime: String? = null,
    var bookUrl: String? = null,
    var coverUrl: String? = null,
    var wordCount: String? = null
)

data class BookInfoRule(
    var name: String? = null,
    var author: String? = null,
    var intro: String? = null,
    var kind: String? = null,
    var lastChapter: String? = null,
    var updateTime: String? = null,
    var coverUrl: String? = null,
    var tocUrl: String? = null,
    var wordCount: String? = null
)

data class TocRule(
    var chapterList: String? = null,
    var chapterName: String? = null,
    var chapterUrl: String? = null,
    var isVolume: String? = null,
    var isVip: String? = null,
    var updateTime: String? = null,
    var nextTocUrl: String? = null
)

data class ContentRule(
    var content: String? = null,
    var nextContentUrl: String? = null,
    var sourceRegex: String? = null,
    var replaceRegex: String? = null,
    var imageDecode: String? = null
)
