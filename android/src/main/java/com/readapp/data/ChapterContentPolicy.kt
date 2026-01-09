package com.readapp.data

data class ChapterContentPolicy(
    val useMemoryCache: Boolean = true,
    val useDiskCache: Boolean = true,
    val saveToCache: Boolean = true
) {
    companion object {
        val Default = ChapterContentPolicy()
        val Refresh = ChapterContentPolicy(useMemoryCache = false, useDiskCache = false, saveToCache = true)
    }
}
