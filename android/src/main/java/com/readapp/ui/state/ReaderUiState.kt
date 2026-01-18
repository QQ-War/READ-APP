package com.readapp.ui.state

import com.readapp.data.DarkModeConfig
import com.readapp.data.PageTurningMode
import com.readapp.data.ReadingMode
import com.readapp.data.ApiBackend
import com.readapp.data.ReaderTheme
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter

data class ReaderUiState(
    val book: Book?,
    val chapters: List<Chapter>,
    val currentChapterIndex: Int,
    val currentChapterContent: String,
    val isContentLoading: Boolean,
    val errorMessage: String?,
    val readingFontSize: Float,
    val readingFontPath: String,
    val readingFontName: String,
    val readingHorizontalPadding: Float,
    val readingMode: ReadingMode,
    val lockPageOnTTS: Boolean,
    val pageTurningMode: PageTurningMode,
    val darkModeConfig: DarkModeConfig,
    val readingTheme: ReaderTheme,
    val infiniteScrollEnabled: Boolean,
    val prevChapterContent: String?,
    val nextChapterContent: String?,
    val preloadedParagraphs: Set<Int>,
    val preloadedChapters: Set<Int>,
    val firstVisibleParagraphIndex: Int,
    val lastVisibleParagraphIndex: Int,
    val pendingScrollIndex: Int?,
    val forceMangaProxy: Boolean,
    val mangaSwitchThreshold: Int,
    val verticalDampingFactor: Float,
    val mangaMaxZoom: Float,
    val manualMangaUrls: Set<String>,
    val serverUrl: String,
    val apiBackend: ApiBackend
)
