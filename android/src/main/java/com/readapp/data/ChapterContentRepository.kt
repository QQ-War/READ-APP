package com.readapp.data

import android.util.Log

class ChapterContentRepository(
    private val repository: ReadRepository,
    private val localCache: LocalCacheManager
) {
    private val memoryCache = mutableMapOf<String, String>()

    fun clearMemoryCache() {
        memoryCache.clear()
    }

    fun cacheContent(bookUrl: String, index: Int, contentType: Int, content: String) {
        memoryCache[cacheKey(bookUrl, index, contentType)] = content
    }

    fun getMemoryCache(bookUrl: String, index: Int, contentType: Int): String? {
        return memoryCache[cacheKey(bookUrl, index, contentType)]
    }

    data class ChapterContentResult(
        val content: String?,
        val error: Throwable? = null
    )

    suspend fun loadChapterContent(
        serverEndpoint: String,
        publicServerEndpoint: String?,
        accessToken: String,
        bookUrl: String,
        bookOrigin: String?,
        chapterListIndex: Int,
        chapterApiIndex: Int,
        contentType: Int,
        policy: ChapterContentPolicy = ChapterContentPolicy.Default,
        cacheValidator: (String) -> Boolean = { true },
        cleaner: (String) -> String
    ): ChapterContentResult {
        val cacheKey = cacheKey(bookUrl, chapterListIndex, contentType)
        if (policy.useMemoryCache) {
            memoryCache[cacheKey]?.let { cached ->
                if (cacheValidator(cached)) {
                    return ChapterContentResult(content = cached)
                }
            }
        }

        if (policy.useDiskCache) {
            val cached = localCache.loadChapter(bookUrl, chapterListIndex)
            if (!cached.isNullOrBlank() && cacheValidator(cached)) {
                if (policy.useMemoryCache) {
                    memoryCache[cacheKey] = cached
                }
                return ChapterContentResult(content = cached)
            }
        }

        return try {
            val result = repository.fetchChapterContent(
                serverEndpoint,
                publicServerEndpoint,
                accessToken,
                bookUrl,
                bookOrigin,
                chapterApiIndex,
                contentType
            )
            result.fold(
                onSuccess = { raw ->
                    val cleaned = cleaner(raw)
                    val resolved = if (cleaned.isNotBlank()) cleaned else raw.trim()
                    if (policy.saveToCache) {
                        localCache.saveChapter(bookUrl, chapterListIndex, resolved)
                        if (policy.useMemoryCache) {
                            memoryCache[cacheKey] = resolved
                        }
                    }
                    ChapterContentResult(content = resolved)
                },
                onFailure = { error ->
                    ChapterContentResult(content = null, error = error)
                }
            )
        } catch (e: Exception) {
            Log.e("ChapterContentRepository", "Load chapter failed: $chapterListIndex", e)
            ChapterContentResult(content = null, error = e)
        }
    }

    private fun cacheKey(bookUrl: String, index: Int, contentType: Int): String {
        return "${bookUrl}_${index}_$contentType"
    }
}
