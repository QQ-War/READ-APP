package com.readapp.data.model

data class Chapter(
    val title: String,
    val url: String,
    val index: Int,
    val isVolume: Boolean? = null,
    val isPay: Boolean? = null,
    val content: String = "",
)
