package com.readapp.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.readapp.android.ui.screens.BookListScreen
import com.readapp.android.ui.screens.LoginScreen
import com.readapp.android.ui.screens.ReaderScreen

@Composable
fun ReadApp(
    uiState: ReadUiState,
    onLogin: (String, String) -> Unit,
    onServerChange: (String, String?) -> Unit,
    onNavigateBooks: () -> Unit,
    onRefreshBooks: () -> Unit,
    onBookSelected: (com.readapp.android.model.Book) -> Unit,
    onChapterSelect: (Int) -> Unit,
    onToggleTts: () -> Unit,
    onTtsEngineSelect: (String) -> Unit,
    onSpeechRateChange: (Double) -> Unit,
    onPreloadSegmentsChange: (Int) -> Unit,
    onBackToBooks: () -> Unit,
    onFontScaleChange: (Float) -> Unit,
    onLineSpacingChange: (Float) -> Unit,
    onSortByRecentChange: (Boolean) -> Unit,
    onSortAscendingChange: (Boolean) -> Unit,
    onSearchChange: (String) -> Unit,
    onReverseChaptersChange: (Boolean) -> Unit,
    onClearCaches: () -> Unit,
    onParagraphJump: (Int) -> Unit,
    onToggleImmersive: () -> Unit
) {
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let { snackbarHostState.showSnackbar(it) }
    }

    LaunchedEffect(uiState.isLoggedIn) {
        if (uiState.isLoggedIn) {
            onNavigateBooks()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        if (uiState.isLoggedIn && uiState.selectedBook != null) {
                ReaderScreen(
                    book = uiState.selectedBook,
                    chapters = uiState.chapters,
                    currentIndex = uiState.currentChapterIndex,
                    content = uiState.currentChapterContent,
                    paragraphs = uiState.currentParagraphs,
                    currentParagraphIndex = uiState.currentParagraphIndex,
                    isChapterReversed = uiState.reverseChapterList,
                    ttsEngines = uiState.ttsEngines,
                    selectedTtsId = uiState.selectedTtsId,
                    speechRate = uiState.speechRate,
                    preloadSegments = uiState.preloadSegments,
                    preloadedChapters = uiState.preloadedChapters,
                    fontScale = uiState.fontScale,
                    lineSpacing = uiState.lineSpacing,
                    isLoading = uiState.isLoading,
                    isSpeaking = uiState.isSpeaking,
                    isNearChapterEnd = uiState.isNearChapterEnd,
                    upcomingChapterIndex = uiState.upcomingChapterIndex,
                    onBack = onBackToBooks,
                    onSelectChapter = onChapterSelect,
                    onToggleTts = onToggleTts,
                    onTtsEngineSelect = onTtsEngineSelect,
                    onSpeechRateChange = onSpeechRateChange,
                    onPreloadSegmentsChange = onPreloadSegmentsChange,
                    onFontScaleChange = onFontScaleChange,
                    onLineSpacingChange = onLineSpacingChange,
                    onReverseChaptersChange = onReverseChaptersChange,
                    onParagraphJump = onParagraphJump,
                    onToggleImmersive = onToggleImmersive,
                    isImmersive = uiState.isImmersiveMode
                )
        } else if (uiState.isLoggedIn) {
            BookListScreen(
                books = uiState.books,
                searchQuery = uiState.searchQuery,
                serverUrl = uiState.serverUrl,
                publicServerUrl = uiState.publicServerUrl,
                isLoading = uiState.isLoading,
                onRefresh = onRefreshBooks,
                onServerSave = onServerChange,
                onBookClick = onBookSelected,
                sortByRecent = uiState.sortByRecent,
                sortAscending = uiState.sortAscending,
                onSortByRecentChange = onSortByRecentChange,
                onSortAscendingChange = onSortAscendingChange,
                onSearchChange = onSearchChange,
                onClearCaches = onClearCaches
            )
        } else {
            LoginScreen(
                isLoading = uiState.isLoading,
                serverUrl = uiState.serverUrl,
                publicServerUrl = uiState.publicServerUrl,
                onLogin = onLogin,
                onServerSave = onServerChange
            )
        }

        if (uiState.isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = MaterialTheme.colorScheme.primary
            )
        }

        SnackbarHost(hostState = snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
    }
}
