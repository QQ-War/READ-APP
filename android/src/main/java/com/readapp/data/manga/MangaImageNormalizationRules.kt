package com.readapp.data.manga

data class MangaImageHostRewrite(
    val fromSuffix: String,
    val toSuffix: String
)

object MangaImageNormalizationRules {
    val hostRewrites = listOf(
        MangaImageHostRewrite(fromSuffix = "bzmh.net", toSuffix = "bzcdn.net")
    )

    val preferSignedHosts = listOf(
        "kkmh.com"
    )
}
