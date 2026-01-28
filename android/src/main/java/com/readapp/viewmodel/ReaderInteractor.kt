package com.readapp.viewmodel

import android.util.Log
import com.readapp.data.ChapterContentPolicy
import com.readapp.data.model.Book
import kotlinx.coroutines.launch
import androidx.lifecycle.viewModelScope

internal class ReaderInteractor(private val viewModel: BookViewModel) {
    private companion object {
        private const val TAG = "ReaderInteractor"
    }
    private var mangaPrefetchNextIndex: Int? = null

    suspend fun loadChapters(book: Book) {
        val bookUrl = book.bookUrl ?: return
        viewModel._isChapterListLoading.value = true
        val chaptersResult = runCatching {
            viewModel.bookRepository.fetchChapterList(
                viewModel.currentServerEndpoint(),
                viewModel._publicServerAddress.value.ifBlank { null },
                viewModel._accessToken.value,
                bookUrl,
                book.origin
            )
        }.getOrElse { throwable ->
            Log.e(TAG, "加载章节列表失败", throwable)
            val cached = viewModel.loadChapterListFromCache(bookUrl)
            if (!cached.isNullOrEmpty()) {
                viewModel._chapters.value = cached
                viewModel._isChapterListLoading.value = false
                return
            }
            showReaderError("加载失败: 无法获取目录，请检查网络后重试")
            viewModel._isChapterListLoading.value = false
            return
        }
        chaptersResult.onSuccess { chapterList ->
            viewModel._chapters.value = chapterList
            viewModel.saveChapterListToCache(bookUrl, chapterList)
            if (chapterList.isNotEmpty()) {
                val index = viewModel._currentChapterIndex.value.coerceIn(0, chapterList.lastIndex)
                viewModel._currentChapterIndex.value = index
                loadChapterContent(index)
            }
            viewModel._isChapterListLoading.value = false
        }.onFailure { error ->
            Log.e(TAG, "加载章节列表失败", error)
            if (viewModel._chapters.value.isEmpty()) {
                showReaderError("加载失败: 无法获取目录，请检查网络后重试")
            } else {
                viewModel._errorMessage.value = error.message
            }
            viewModel._isChapterListLoading.value = false
        }
    }

    fun loadChapterContent(index: Int) {
        viewModel.viewModelScope.launch { loadChapterContentInternal(index) }
    }

    suspend fun loadChapterContentInternal(index: Int): String? {
        val book = viewModel._selectedBook.value ?: return null
        val chapter = viewModel._chapters.value.getOrNull(index)
        if (chapter == null) {
            showReaderError("加载失败: 章节信息为空，请检查网络后重试")
            return null
        }
        val bookUrl = book.bookUrl ?: return null

        val isManga = viewModel.manualMangaUrls.value.contains(bookUrl) || book.type == 2
        val effectiveType = when {
            book.type == 1 -> 1
            isManga -> 2
            else -> 0
        }

        if (viewModel._isChapterContentLoading.value) {
            return viewModel._currentChapterContent.value.ifBlank { null }
        }
        viewModel._isChapterContentLoading.value = true
        return try {
            val contentResult = viewModel.chapterContentRepository.loadChapterContent(
                serverEndpoint = viewModel.currentServerEndpoint(),
                publicServerEndpoint = viewModel._publicServerAddress.value.ifBlank { null },
                accessToken = viewModel._accessToken.value,
                bookUrl = bookUrl,
                bookOrigin = book.origin,
                chapterListIndex = index,
                chapterApiIndex = chapter.index,
                contentType = effectiveType,
                policy = ChapterContentPolicy.Default,
                cacheValidator = { cached -> !isManga || cached.contains("__IMG__") },
                cleaner = { raw -> viewModel.cleanChapterContent(raw) }
            )
            contentResult.error?.let { error ->
                viewModel._errorMessage.value = "加载失败: ${error.message}"
            }
            val resolvedContent = contentResult.content
            if (!resolvedContent.isNullOrBlank()) {
                updateChapterContent(index, resolvedContent)
                resolvedContent
            } else {
                val errorMessage = contentResult.error?.message ?: "内容为空"
                showReaderError("加载失败: $errorMessage，请检查网络后重试")
                null
            }
        } catch (e: Exception) {
            showReaderError("系统异常: ${e.localizedMessage}")
            Log.e(TAG, "加载章节内容异常", e)
            null
        } finally {
            viewModel._isChapterContentLoading.value = false
        }
    }

    fun updateChapterContent(index: Int, content: String) {
        viewModel._currentChapterContent.value = content
        viewModel.currentParagraphs = viewModel.parseParagraphs(content)
        viewModel.currentSentences = viewModel.currentParagraphs
        viewModel._totalParagraphs.value = viewModel.currentParagraphs.size.coerceAtLeast(1)
        viewModel.viewModelScope.launch { prefetchAdjacentChapters() }
    }

    fun clearAdjacentChapterCache() {
        viewModel._prevChapterIndex.value = null
        viewModel._nextChapterIndex.value = null
        viewModel._prevChapterContent.value = null
        viewModel._nextChapterContent.value = null
    }

    private fun isMangaBook(book: Book?): Boolean {
        val bookUrl = book?.bookUrl ?: return false
        return viewModel.manualMangaUrls.value.contains(bookUrl) || book.type == 2
    }

    suspend fun prefetchAdjacentChapters() {
        if (!viewModel.infiniteScrollEnabled.value) {
            clearAdjacentChapterCache()
            return
        }
        val book = viewModel._selectedBook.value ?: return
        if (isMangaBook(book)) {
            prefetchMangaNextChapter(book)
            return
        }
        val chapters = viewModel._chapters.value
        if (chapters.isEmpty()) return
        val current = viewModel._currentChapterIndex.value
        val prevIndex = if (current > 0) current - 1 else null
        val nextIndex = if (current < chapters.lastIndex) current + 1 else null

        viewModel._prevChapterIndex.value = prevIndex
        viewModel._nextChapterIndex.value = nextIndex

        val effectiveType = 0
        val prevContent = prevIndex?.let { fetchChapterContentForIndex(it, effectiveType) }
        val nextContent = nextIndex?.let { fetchChapterContentForIndex(it, effectiveType) }

        viewModel._prevChapterContent.value = prevContent
        viewModel._nextChapterContent.value = nextContent

        val preloaded = mutableSetOf<Int>()
        if (!prevContent.isNullOrBlank()) preloaded.add(prevIndex ?: -1)
        if (!nextContent.isNullOrBlank()) preloaded.add(nextIndex ?: -1)
        viewModel._preloadedChapters.value = preloaded.filter { it >= 0 }.toSet()
    }

    suspend fun fetchChapterContentForIndex(index: Int, effectiveType: Int): String? {
        val book = viewModel._selectedBook.value ?: return null
        val chapter = viewModel._chapters.value.getOrNull(index) ?: return null
        val bookUrl = book.bookUrl ?: return null
        return viewModel.chapterContentRepository.loadChapterContent(
            serverEndpoint = viewModel.currentServerEndpoint(),
            publicServerEndpoint = viewModel._publicServerAddress.value.ifBlank { null },
            accessToken = viewModel._accessToken.value,
            bookUrl = bookUrl,
            bookOrigin = book.origin,
            chapterListIndex = index,
            chapterApiIndex = chapter.index,
            contentType = effectiveType,
            policy = ChapterContentPolicy.Default,
            cacheValidator = { true },
            cleaner = { raw -> viewModel.cleanChapterContent(raw) }
        ).content
    }

    private fun showReaderError(message: String) {
        viewModel._currentChapterContent.value = message
        viewModel.currentParagraphs = viewModel.parseParagraphs(message)
        viewModel.currentSentences = viewModel.currentParagraphs
        viewModel._totalParagraphs.value = viewModel.currentParagraphs.size.coerceAtLeast(1)
        viewModel._preloadedChapters.value = emptySet()
        clearAdjacentChapterCache()
    }

    private suspend fun prefetchMangaNextChapter(book: Book) {
        val chapters = viewModel._chapters.value
        if (chapters.isEmpty()) {
            clearAdjacentChapterCache()
            return
        }
        val current = viewModel._currentChapterIndex.value
        val nextIndex = if (current < chapters.lastIndex) current + 1 else null
        if (nextIndex == null) {
            viewModel._nextChapterIndex.value = null
            viewModel._nextChapterContent.value = null
            viewModel._preloadedChapters.value = emptySet()
            return
        }
        if (mangaPrefetchNextIndex == nextIndex) return
        mangaPrefetchNextIndex = nextIndex
        try {
            val content = fetchChapterContentForIndex(nextIndex, 2)
            if (!content.isNullOrBlank()) {
                viewModel._nextChapterIndex.value = nextIndex
                viewModel._nextChapterContent.value = content
                viewModel._preloadedChapters.value = setOf(nextIndex)
                val chapter = chapters[nextIndex]
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    viewModel.cacheMangaImages(book, chapter, nextIndex, content)
                }
            }
        } finally {
            if (mangaPrefetchNextIndex == nextIndex) {
                mangaPrefetchNextIndex = null
            }
        }
    }
}
