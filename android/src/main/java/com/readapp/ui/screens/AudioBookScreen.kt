package com.readapp.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import com.readapp.viewmodel.BookViewModel

@Composable
fun AudioBookScreen(
    bookViewModel: BookViewModel,
    onExit: () -> Unit
) {
    val selectedBook by bookViewModel.selectedBook.collectAsState()
    val chapterTitle by bookViewModel.audioChapterTitle.collectAsState()
    val progress by bookViewModel.audioProgress.collectAsState()
    val isPlaying by bookViewModel.audioIsPlaying.collectAsState()
    val speed by bookViewModel.audioSpeed.collectAsState()
    val currentIndex by bookViewModel.audioCurrentIndex.collectAsState()
    val chapters by bookViewModel.chapters.collectAsState()

    val currentTime = formatDurationMs((bookViewModel.audioPositionMs.collectAsState().value))
    val totalTime = formatDurationMs((bookViewModel.audioDurationMs.collectAsState().value))

    val book = selectedBook ?: return

    LaunchedEffect(book.bookUrl) {
        bookViewModel.startAudioBook()
    }

    PlayerScreen(
        book = book,
        chapterTitle = if (chapterTitle.isBlank()) "正在加载..." else chapterTitle,
        currentParagraph = currentIndex + 1,
        totalParagraphs = chapters.size.coerceAtLeast(1),
        currentTime = currentTime,
        totalTime = totalTime,
        progress = progress,
        isPlaying = isPlaying,
        playbackSpeed = speed,
        onPlayPauseClick = { bookViewModel.toggleAudioPlayPause() },
        onPreviousParagraph = { bookViewModel.previousAudioChapter() },
        onNextParagraph = { bookViewModel.nextAudioChapter() },
        onPreviousChapter = { bookViewModel.previousAudioChapter() },
        onNextChapter = { bookViewModel.nextAudioChapter() },
        onShowChapterList = { },
        onSpeedChange = { bookViewModel.setAudioSpeed(it) },
        onExit = onExit
    )
}

private fun formatDurationMs(duration: Long): String {
    if (duration <= 0) return "00:00"
    val totalSeconds = duration / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%02d:%02d".format(minutes, seconds)
}
