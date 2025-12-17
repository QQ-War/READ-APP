package com.readapp.data.model

data class Book(
    val id: String,
    val title: String,
    val author: String,
    val coverEmoji: String,
    val progress: Float,
    val currentChapter: Int,
    val totalChapters: Int
)
