// ReadingScreen.kt - 阅读页面（点击中间显示操作按钮）
package com.readapp.ui.screens

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@Composable
fun ReadingScreen(
    book: Book,
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    currentChapterContent: String,
    onChapterClick: (Int) -> Unit,
    onStartListening: () -> Unit,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showControls by remember { mutableStateOf(false) }
    var showChapterList by remember { mutableStateOf(false) }
    val scrollState = rememberLazyListState()
    
    Box(
        modifier = modifier.fillMaxSize()
    ) {
        // 主要内容区域：显示章节正文
        Column(
            modifier = Modifier
                .fillMaxSize()
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) {
                    // 点击切换控制栏显示/隐藏
                    showControls = !showControls
                }
        ) {
            // 内容区域
            LazyColumn(
                state = scrollState,
                modifier = Modifier
                    .fillMaxSize()
                    .weight(1f),
                contentPadding = PaddingValues(
                    start = AppDimens.PaddingLarge,
                    end = AppDimens.PaddingLarge,
                    top = if (showControls) 80.dp else AppDimens.PaddingLarge,
                    bottom = if (showControls) 100.dp else AppDimens.PaddingLarge
                )
            ) {
                // 章节标题
                item {
                    Text(
                        text = if (currentChapterIndex < chapters.size) {
                            chapters[currentChapterIndex].title
                        } else {
                            "加载中..."
                        },
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(bottom = AppDimens.PaddingLarge)
                    )
                }
                
                // 章节内容（分段显示）
                if (currentChapterContent.isNotEmpty()) {
                    val paragraphs = currentChapterContent
                        .split("\n")
                        .filter { it.isNotBlank() }
                    
                    itemsIndexed(paragraphs) { index, paragraph ->
                        Text(
                            text = paragraph.trim(),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurface,
                            lineHeight = MaterialTheme.typography.bodyLarge.lineHeight * 1.8f,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(bottom = AppDimens.PaddingMedium)
                        )
                    }
                } else {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(200.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                }
            }
        }
        
        // 顶部控制栏（动画显示/隐藏）
        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn() + slideInVertically(),
            exit = fadeOut() + slideOutVertically(),
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            TopControlBar(
                bookTitle = book.title,
                chapterTitle = if (currentChapterIndex < chapters.size) {
                    chapters[currentChapterIndex].title
                } else {
                    ""
                },
                onNavigateBack = onNavigateBack
            )
        }
        
        // 底部控制栏（动画显示/隐藏）
        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn() + slideInVertically(initialOffsetY = { it }),
            exit = fadeOut() + slideOutVertically(targetOffsetY = { it }),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            BottomControlBar(
                onPreviousChapter = {
                    if (currentChapterIndex > 0) {
                        onChapterClick(currentChapterIndex - 1)
                    }
                },
                onNextChapter = {
                    if (currentChapterIndex < chapters.size - 1) {
                        onChapterClick(currentChapterIndex + 1)
                    }
                },
                onShowChapterList = {
                    showChapterList = true
                },
                onStartListening = onStartListening,
                canGoPrevious = currentChapterIndex > 0,
                canGoNext = currentChapterIndex < chapters.size - 1
            )
        }
        
        // 章节列表弹窗
        if (showChapterList) {
            ChapterListDialog(
                chapters = chapters,
                currentChapterIndex = currentChapterIndex,
                onChapterClick = { index ->
                    onChapterClick(index)
                    showChapterList = false
                },
                onDismiss = { showChapterList = false }
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TopControlBar(
    bookTitle: String,
    chapterTitle: String,
    onNavigateBack: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
        shadowElevation = 4.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppDimens.PaddingMedium, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onNavigateBack) {
                Icon(
                    imageVector = Icons.Default.ArrowBack,
                    contentDescription = "返回",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
            
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp)
            ) {
                Text(
                    text = bookTitle,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1
                )
                
                Text(
                    text = chapterTitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.customColors.textSecondary,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
private fun BottomControlBar(
    onPreviousChapter: () -> Unit,
    onNextChapter: () -> Unit,
    onShowChapterList: () -> Unit,
    onStartListening: () -> Unit,
    canGoPrevious: Boolean,
    canGoNext: Boolean
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
        shadowElevation = 8.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AppDimens.PaddingLarge),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 上一章
            ControlButton(
                icon = Icons.Default.SkipPrevious,
                label = "上一章",
                onClick = onPreviousChapter,
                enabled = canGoPrevious
            )
            
            // 目录
            ControlButton(
                icon = Icons.Default.List,
                label = "目录",
                onClick = onShowChapterList
            )
            
            // 听书（主按钮）
            FloatingActionButton(
                onClick = onStartListening,
                containerColor = MaterialTheme.customColors.gradientStart,
                elevation = FloatingActionButtonDefaults.elevation(
                    defaultElevation = 6.dp
                )
            ) {
                Icon(
                    imageVector = Icons.Default.VolumeUp,
                    contentDescription = "听书",
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(28.dp)
                )
            }
            
            // 下一章
            ControlButton(
                icon = Icons.Default.SkipNext,
                label = "下一章",
                onClick = onNextChapter,
                enabled = canGoNext
            )
            
            // 字体大小（TODO）
            ControlButton(
                icon = Icons.Default.FormatSize,
                label = "字体",
                onClick = { /* TODO */ }
            )
        }
    }
}

@Composable
private fun ControlButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        IconButton(
            onClick = onClick,
            enabled = enabled
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (enabled) {
                    MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.customColors.textSecondary.copy(alpha = 0.3f)
                },
                modifier = Modifier.size(24.dp)
            )
        }
        
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = if (enabled) {
                MaterialTheme.customColors.textSecondary
            } else {
                MaterialTheme.customColors.textSecondary.copy(alpha = 0.3f)
            }
        )
    }
}

@Composable
private fun ChapterListDialog(
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    onChapterClick: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = "章节列表",
                style = MaterialTheme.typography.titleLarge
            )
        },
        text = {
            LazyColumn(
                modifier = Modifier.fillMaxWidth()
            ) {
                itemsIndexed(chapters) { index, chapter ->
                    val isCurrentChapter = index == currentChapterIndex
                    
                    Surface(
                        onClick = { onChapterClick(index) },
                        color = if (isCurrentChapter) {
                            MaterialTheme.customColors.gradientStart.copy(alpha = 0.1f)
                        } else {
                            MaterialTheme.colorScheme.surface
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 12.dp, horizontal = 16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = chapter.title,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = if (isCurrentChapter) {
                                        MaterialTheme.customColors.gradientStart
                                    } else {
                                        MaterialTheme.colorScheme.onSurface
                                    }
                                )
                                
                                Text(
                                    text = "时长: ${chapter.duration}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.customColors.textSecondary
                                )
                            }
                            
                            if (isCurrentChapter) {
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.customColors.gradientStart
                                ) {
                                    Text(
                                        text = "当前",
                                        modifier = Modifier.padding(
                                            horizontal = 8.dp,
                                            vertical = 4.dp
                                        ),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onPrimary
                                    )
                                }
                            }
                        }
                    }
                    
                    if (index < chapters.size - 1) {
                        Divider(color = MaterialTheme.customColors.border)
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("关闭")
            }
        },
        shape = RoundedCornerShape(AppDimens.CornerRadiusLarge)
    )
}
