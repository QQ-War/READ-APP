package com.readapp.data.model

data class Chapter(
    val id: String,
    val title: String,
    val duration: String,
    val content: String = ""
)
