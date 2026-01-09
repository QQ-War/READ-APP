package com.readapp.viewmodel

import com.readapp.data.DarkModeConfig
import com.readapp.data.PageTurningMode
import com.readapp.data.ReadingMode
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.state.ReaderUiState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

class ReaderStateReducer(
    scope: CoroutineScope,
    errorMessage: StateFlow<String?>,
    isContentLoading: StateFlow<Boolean>,
    readingFontSize: StateFlow<Float>,
    readingHorizontalPadding: StateFlow<Float>,
    readingMode: StateFlow<ReadingMode>,
    lockPageOnTTS: StateFlow<Boolean>,
    pageTurningMode: StateFlow<PageTurningMode>,
    darkMode: StateFlow<DarkModeConfig>,
    infiniteScrollEnabled: StateFlow<Boolean>,
    forceMangaProxy: StateFlow<Boolean>,
    manualMangaUrls: StateFlow<Set<String>>,
    serverAddress: StateFlow<String>,
    apiBackend: StateFlow<com.readapp.data.ApiBackend>
) {
    internal val books = MutableStateFlow<List<Book>>(emptyList())
    val booksFlow: StateFlow<List<Book>> = books.asStateFlow()

    internal val selectedBook = MutableStateFlow<Book?>(null)
    val selectedBookFlow: StateFlow<Book?> = selectedBook.asStateFlow()

    internal val chapters = MutableStateFlow<List<Chapter>>(emptyList())
    val chaptersFlow: StateFlow<List<Chapter>> = chapters.asStateFlow()

    internal val currentChapterIndex = MutableStateFlow(0)
    val currentChapterIndexFlow: StateFlow<Int> = currentChapterIndex.asStateFlow()

    internal val currentChapterContent = MutableStateFlow("")
    val currentChapterContentFlow: StateFlow<String> = currentChapterContent.asStateFlow()

    internal val currentParagraphIndex = MutableStateFlow(-1)
    val currentParagraphIndexFlow: StateFlow<Int> = currentParagraphIndex.asStateFlow()

    internal val firstVisibleParagraphIndex = MutableStateFlow(0)
    val firstVisibleParagraphIndexFlow: StateFlow<Int> = firstVisibleParagraphIndex.asStateFlow()

    internal val pendingScrollIndex = MutableStateFlow<Int?>(null)
    val pendingScrollIndexFlow: StateFlow<Int?> = pendingScrollIndex.asStateFlow()

    internal val currentParagraphStartOffset = MutableStateFlow(0)
    val currentParagraphStartOffsetFlow: StateFlow<Int> = currentParagraphStartOffset.asStateFlow()

    internal val totalParagraphs = MutableStateFlow(1)
    val totalParagraphsFlow: StateFlow<Int> = totalParagraphs.asStateFlow()

    internal val preloadedParagraphs = MutableStateFlow<Set<Int>>(emptySet())
    val preloadedParagraphsFlow: StateFlow<Set<Int>> = preloadedParagraphs.asStateFlow()

    internal val preloadedChapters = MutableStateFlow<Set<Int>>(emptySet())
    val preloadedChaptersFlow: StateFlow<Set<Int>> = preloadedChapters.asStateFlow()

    internal val prevChapterIndex = MutableStateFlow<Int?>(null)
    val prevChapterIndexFlow: StateFlow<Int?> = prevChapterIndex.asStateFlow()

    internal val nextChapterIndex = MutableStateFlow<Int?>(null)
    val nextChapterIndexFlow: StateFlow<Int?> = nextChapterIndex.asStateFlow()

    internal val prevChapterContent = MutableStateFlow<String?>(null)
    val prevChapterContentFlow: StateFlow<String?> = prevChapterContent.asStateFlow()

    internal val nextChapterContent = MutableStateFlow<String?>(null)
    val nextChapterContentFlow: StateFlow<String?> = nextChapterContent.asStateFlow()

    val readerUiState: StateFlow<ReaderUiState> = combine(
        selectedBookFlow,
        chaptersFlow,
        currentChapterIndexFlow,
        currentChapterContentFlow,
        isContentLoading,
        errorMessage,
        readingFontSize,
        readingHorizontalPadding,
        readingMode,
        lockPageOnTTS,
        pageTurningMode,
        darkMode,
        infiniteScrollEnabled,
        prevChapterContentFlow,
        nextChapterContentFlow,
        preloadedParagraphsFlow,
        preloadedChaptersFlow,
        firstVisibleParagraphIndexFlow,
        pendingScrollIndexFlow,
        forceMangaProxy,
        manualMangaUrls,
        serverAddress,
        apiBackend
    ) { values ->
        ReaderUiState(
            book = values[0] as Book?,
            chapters = values[1] as List<Chapter>,
            currentChapterIndex = values[2] as Int,
            currentChapterContent = values[3] as String,
            isContentLoading = values[4] as Boolean,
            errorMessage = values[5] as String?,
            readingFontSize = values[6] as Float,
            readingHorizontalPadding = values[7] as Float,
            readingMode = values[8] as ReadingMode,
            lockPageOnTTS = values[9] as Boolean,
            pageTurningMode = values[10] as PageTurningMode,
            darkModeConfig = values[11] as DarkModeConfig,
            infiniteScrollEnabled = values[12] as Boolean,
            prevChapterContent = values[13] as String?,
            nextChapterContent = values[14] as String?,
            preloadedParagraphs = values[15] as Set<Int>,
            preloadedChapters = values[16] as Set<Int>,
            firstVisibleParagraphIndex = values[17] as Int,
            pendingScrollIndex = values[18] as Int?,
            forceMangaProxy = values[19] as Boolean,
            manualMangaUrls = values[20] as Set<String>,
            serverUrl = values[21] as String,
            apiBackend = values[22] as com.readapp.data.ApiBackend
        )
    }.stateIn(scope, SharingStarted.Eagerly, ReaderUiState(
        book = null,
        chapters = emptyList(),
        currentChapterIndex = 0,
        currentChapterContent = "",
        isContentLoading = false,
        errorMessage = null,
        readingFontSize = 16f,
        readingHorizontalPadding = 24f,
        readingMode = ReadingMode.Vertical,
        lockPageOnTTS = false,
        pageTurningMode = PageTurningMode.Scroll,
        darkModeConfig = DarkModeConfig.OFF,
        infiniteScrollEnabled = true,
        prevChapterContent = null,
        nextChapterContent = null,
        preloadedParagraphs = emptySet(),
        preloadedChapters = emptySet(),
        firstVisibleParagraphIndex = 0,
        pendingScrollIndex = null,
        forceMangaProxy = false,
        manualMangaUrls = emptySet(),
        serverUrl = "",
        apiBackend = com.readapp.data.ApiBackend.Read
    ))
}
