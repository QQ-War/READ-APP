// ReadingScreen.kt - 阅读页面
package com.readapp.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.FormatListBulleted
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingScreen(
    book: Book,
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    content: String,
    isContentLoading: Boolean,
    onLoadContent: () -> Unit,
    onChapterClick: (Int) -> Unit,
    onStartListening: () -> Unit,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val chapterTitle = chapters.getOrNull(currentChapterIndex)?.title ?: book.title
    var showControls by remember { mutableStateOf(false) }
    var showChapterSheet by remember { mutableStateOf(false) }

    val paragraphs = remember(content) {
        content.split("\n\n", "\n")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
    }

    LaunchedEffect(book.id, currentChapterIndex) {
        onLoadContent()
    }

    if (showChapterSheet) {
        ChapterBottomSheet(
            chapters = chapters,
            currentChapterIndex = currentChapterIndex,
            onChapterSelected = { index ->
                onChapterClick(index)
                showChapterSheet = false
            },
            onDismiss = { showChapterSheet = false }
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(onTap = { showControls = !showControls })
            }
            .background(MaterialTheme.colorScheme.surface)
    ) {
        when {
            isContentLoading && content.isBlank() -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }

            content.isNotBlank() -> {
                ReadingContent(
                    chapterTitle = chapterTitle,
                    author = book.author,
                    paragraphs = paragraphs
                )
            }

            else -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "暂无章节内容",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.customColors.textSecondary
                    )
                }
            }
        }

        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            ReadingControlsOverlay(
                chapterTitle = chapterTitle,
                author = book.author,
                chapterPosition = "${currentChapterIndex + 1}/${chapters.size.coerceAtLeast(1)}",
                onNavigateBack = onNavigateBack,
                onShowChapters = { showChapterSheet = true },
                onStartListening = onStartListening
            )
        }
    }
}

@Composable
private fun ReadingContent(
    chapterTitle: String,
    author: String,
    paragraphs: List<String>
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = AppDimens.PaddingMedium),
        contentPadding = PaddingValues(vertical = AppDimens.PaddingLarge),
        verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = chapterTitle,
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onSurface
                )
                if (author.isNotBlank()) {
                    Text(
                        text = author,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.customColors.textSecondary
                    )
                }
            }
        }

        itemsIndexed(paragraphs) { _, paragraph ->
            Text(
                text = paragraph,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
    }
}

@Composable
private fun ReadingControlsOverlay(
    chapterTitle: String,
    author: String,
    chapterPosition: String,
    onNavigateBack: () -> Unit,
    onShowChapters: () -> Unit,
    onStartListening: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))
            .padding(AppDimens.PaddingMedium)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(AppDimens.PaddingSmall),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onNavigateBack) {
                    Icon(
                        imageVector = Icons.Default.ArrowBack,
                        contentDescription = "返回"
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = chapterTitle,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (author.isNotBlank()) {
                        Text(
                            text = author,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.customColors.textSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }

                Text(
                    text = chapterPosition,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.customColors.textSecondary
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedButton(
                    onClick = onShowChapters,
                    shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.FormatListBulleted,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(text = "章节")
                }

                Button(
                    onClick = onStartListening,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Headphones,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(text = "听书")
                }
            }
        }
    }
}

@Composable
private fun ChapterBottomSheet(
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    onChapterSelected: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { ModalBottomSheetDefaults.DragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AppDimens.PaddingMedium),
            verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium)
        ) {
            Text(
                text = "选择章节",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface
            )

            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingSmall)
            ) {
                itemsIndexed(chapters) { index, chapter ->
                    ChapterRow(
                        chapter = chapter,
                        isCurrent = index == currentChapterIndex,
                        onClick = {
                            onChapterSelected(index)
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun ChapterRow(
    chapter: Chapter,
    isCurrent: Boolean,
    onClick: () -> Unit
) {
    val backgroundColor = if (isCurrent) {
        MaterialTheme.customColors.gradientStart.copy(alpha = 0.1f)
    } else {
        MaterialTheme.colorScheme.surface
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(backgroundColor, RoundedCornerShape(AppDimens.CornerRadiusMedium))
            .clickable(onClick = onClick)
            .padding(horizontal = AppDimens.PaddingMedium, vertical = AppDimens.PaddingSmall),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = chapter.title,
                style = MaterialTheme.typography.bodyLarge,
                color = if (isCurrent) MaterialTheme.customColors.gradientStart else MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            if (chapter.duration.isNotBlank()) {
                Text(
                    text = chapter.duration,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.customColors.textSecondary
                )
            }
        }

        if (isCurrent) {
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.customColors.gradientStart
            ) {
                Text(
                    text = "当前",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimary
                )
            }
        }
    }
}
