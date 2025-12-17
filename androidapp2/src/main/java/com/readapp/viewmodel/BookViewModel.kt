package com.readapp.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min

class BookViewModel : ViewModel() {
    private val allBooks = listOf(
        Book(
            id = "1",
            title = "未来简史",
            author = "尤瓦尔·赫拉利",
            coverEmoji = "📘",
            progress = 0.35f,
            currentChapter = 3,
            totalChapters = 12
        ),
        Book(
            id = "2",
            title = "银河帝国",
            author = "阿西莫夫",
            coverEmoji = "🚀",
            progress = 0.62f,
            currentChapter = 7,
            totalChapters = 18
        ),
        Book(
            id = "3",
            title = "月亮与六便士",
            author = "毛姆",
            coverEmoji = "🌕",
            progress = 0.12f,
            currentChapter = 1,
            totalChapters = 10
        )
    )

    var books by mutableStateOf(allBooks)
        private set

    var selectedBook by mutableStateOf<Book?>(allBooks.first())
        private set

    var chapters by mutableStateOf(sampleChapters(selectedBook?.id))
        private set

    var currentChapterIndex by mutableStateOf(0)
        private set

    var currentParagraph by mutableStateOf(1)
        private set

    var totalParagraphs by mutableStateOf(12)
        private set

    var currentTime by mutableStateOf("00:00")
        private set

    var totalTime by mutableStateOf("12:00")
        private set

    var playbackProgress by mutableStateOf(0f)
        private set

    var isPlaying by mutableStateOf(false)
        private set

    var serverAddress by mutableStateOf("http://127.0.0.1:8080")
        private set

    var selectedTtsEngine by mutableStateOf("系统默认")
        private set

    var speechSpeed by mutableStateOf(20)
        private set

    var preloadCount by mutableStateOf(3)
        private set

    val currentChapterTitle: String
        get() = chapters.getOrNull(currentChapterIndex)?.title ?: ""

    fun searchBooks(query: String) {
        books = if (query.isBlank()) {
            allBooks
        } else {
            val lower = query.lowercase()
            allBooks.filter {
                it.title.lowercase().contains(lower) || it.author.lowercase().contains(lower)
            }
        }
    }

    fun selectBook(book: Book) {
        selectedBook = book
        chapters = sampleChapters(book.id)
        currentChapterIndex = min(book.currentChapter - 1, chapters.lastIndex.coerceAtLeast(0))
        resetPlayback()
    }

    fun setCurrentChapter(index: Int) {
        if (index in chapters.indices) {
            currentChapterIndex = index
            resetPlayback()
        }
    }

    fun togglePlayPause() {
        isPlaying = !isPlaying
        if (isPlaying) {
            simulatePlayback()
        }
    }

    fun previousParagraph() {
        currentParagraph = max(1, currentParagraph - 1)
        playbackProgress = max(0f, playbackProgress - 0.05f)
    }

    fun nextParagraph() {
        currentParagraph = min(totalParagraphs, currentParagraph + 1)
        playbackProgress = min(1f, playbackProgress + 0.05f)
    }

    fun previousChapter() {
        if (currentChapterIndex > 0) {
            setCurrentChapter(currentChapterIndex - 1)
        }
    }

    fun nextChapter() {
        if (currentChapterIndex < chapters.lastIndex) {
            setCurrentChapter(currentChapterIndex + 1)
        }
    }

    fun updateServerAddress(address: String) {
        serverAddress = address
    }

    fun updateSpeechSpeed(speed: Int) {
        speechSpeed = speed.coerceIn(5, 50)
    }

    fun updatePreloadCount(count: Int) {
        preloadCount = count.coerceIn(1, 10)
    }

    fun clearCache() {
        // 占位实现：实际清理缓存逻辑应在此处添加
    }

    fun logout() {
        selectedBook = null
        isPlaying = false
        playbackProgress = 0f
    }

    private fun resetPlayback() {
        currentParagraph = 1
        playbackProgress = 0f
        currentTime = "00:00"
        totalTime = "12:00"
        isPlaying = false
    }

    private fun simulatePlayback() {
        viewModelScope.launch {
            while (isPlaying && playbackProgress < 1f) {
                delay(500)
                playbackProgress = min(1f, playbackProgress + 0.02f)
                currentTime = formatTime(playbackProgress * 720) // 假设 12 分钟 = 720 秒
            }
        }
    }

    private fun formatTime(totalSeconds: Float): String {
        val minutes = (totalSeconds / 60).toInt()
        val seconds = (totalSeconds % 60).toInt()
        return String.format("%02d:%02d", minutes, seconds)
    }

    private fun sampleChapters(bookId: String?): List<Chapter> {
        val prefix = bookId ?: "0"
        return listOf(
            Chapter(id = "${prefix}_1", title = "序章", duration = "08:24"),
            Chapter(id = "${prefix}_2", title = "第一章", duration = "12:15"),
            Chapter(id = "${prefix}_3", title = "第二章", duration = "10:05"),
            Chapter(id = "${prefix}_4", title = "第三章", duration = "09:42")
        )
    }
}
