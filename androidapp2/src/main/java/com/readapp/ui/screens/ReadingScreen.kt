// ReadingScreen.kt - 阅读页面集成听书功能（段落高亮）
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors
import kotlinx.coroutines.launch

@Composable
fun ReadingScreen(
    book: Book,
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    currentChapterContent: String,
    isContentLoading: Boolean,
    onChapterClick: (Int) -> Unit,
    onLoadChapterContent: (Int) -> Unit,
    onNavigateBack: () -> Unit,
    // TTS 相关状态
    isPlaying: Boolean = false,
    currentPlayingParagraph: Int = -1,  // 当前播放的段落索引
    preloadedParagraphs: Set<Int> = emptySet(),  // 已预载的段落索引
    onPlayPauseClick: () -> Unit = {},
    onStartListening: () -> Unit = {},
    onStopListening: () -> Unit = {},
    onPreviousParagraph: () -> Unit = {},
    onNextParagraph: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    var showControls by remember { mutableStateOf(false) }
    var showChapterList by remember { mutableStateOf(false) }
    val scrollState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    
    // 分割段落
    val displayContent = remember(currentChapterContent, currentChapterIndex, chapters) {
        if (currentChapterContent.isNotBlank()) {
            currentChapterContent
        } else {
            chapters.getOrNull(currentChapterIndex)?.content.orEmpty()
        }
    }

    val paragraphs = remember(displayContent) {
        if (displayContent.isNotEmpty()) {
            displayContent
                .split("\n")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
        } else {
            emptyList()
        }
    }

    // 当章节索引变化或章节列表加载完成时，自动加载章节内容并回到顶部
    LaunchedEffect(currentChapterIndex, chapters.size) {
        if (chapters.isNotEmpty() && currentChapterIndex in chapters.indices) {
            onLoadChapterContent(currentChapterIndex)
            scrollState.scrollToItem(0)
        }
    }
    
    // 当前播放段落变化时，自动滚动到该段落
    LaunchedEffect(currentPlayingParagraph) {
        if (currentPlayingParagraph >= 0 && currentPlayingParagraph < paragraphs.size) {
            coroutineScope.launch {
                // +1 是因为第一个 item 是章节标题
                scrollState.animateScrollToItem(currentPlayingParagraph + 1)
            }
        }
    }
    
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
                    bottom = if (showControls) 120.dp else AppDimens.PaddingLarge
                )
            ) {
                // 章节标题
                item {
                    Text(
                        text = if (currentChapterIndex < chapters.size) {
                            chapters[currentChapterIndex].title
                        } else {
                            "章节"
                        },
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(bottom = AppDimens.PaddingLarge)
                    )
                }

                if (paragraphs.isEmpty()) {
                    item {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = AppDimens.PaddingLarge),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            CircularProgressIndicator()
                            Text(
                                text = if (isContentLoading) "正在加载章节内容..." else "暂无可显示的内容",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.customColors.textSecondary,
                                textAlign = TextAlign.Center
                            )
                        }
                    }
                } else {
                    // 章节内容（分段显示，带高亮）
                    itemsIndexed(paragraphs) { index, paragraph ->
                        ParagraphItem(
                            text = paragraph,
                            isPlaying = index == currentPlayingParagraph,
                            isPreloaded = preloadedParagraphs.contains(index),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(bottom = AppDimens.PaddingMedium)
                        )
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
                isPlaying = isPlaying,
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
                onPlayPause = {
                    if (isPlaying) {
                        onPlayPauseClick()
                    } else {
                        if (currentPlayingParagraph < 0) {
                            // 第一次点击，开始听书
                            onStartListening()
                        } else {
                            // 继续播放
                            onPlayPauseClick()
                        }
                    }
                },
                onStopListening = onStopListening,
                onPreviousParagraph = onPreviousParagraph,
                onNextParagraph = onNextParagraph,
                canGoPrevious = currentChapterIndex > 0,
                canGoNext = currentChapterIndex < chapters.size - 1,
                showTtsControls = currentPlayingParagraph >= 0  // 开始播放后显示TTS控制
            )
        }

        if (isContentLoading && paragraphs.isNotEmpty()) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
                    .size(40.dp),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(modifier = Modifier.fillMaxSize(), strokeWidth = 3.dp)
            }
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

/**
 * 段落项组件 - 带高亮效果
 */
@Composable
private fun ParagraphItem(
    text: String,
    isPlaying: Boolean,
    isPreloaded: Boolean,
    modifier: Modifier = Modifier
) {
    val backgroundColor = when {
        isPlaying -> MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)  // 当前播放：深蓝色高亮
        isPreloaded -> MaterialTheme.customColors.success.copy(alpha = 0.15f)  // 已预载：浅绿色标记
        else -> Color.Transparent
    }
    
    Surface(
        modifier = modifier,
        color = backgroundColor,
        shape = RoundedCornerShape(8.dp)
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface,
            lineHeight = MaterialTheme.typography.bodyLarge.lineHeight * 1.8f,
            modifier = Modifier.padding(
                horizontal = if (isPlaying || isPreloaded) 12.dp else 0.dp,
                vertical = if (isPlaying || isPreloaded) 8.dp else 0.dp
            )
        )
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
    isPlaying: Boolean,
    onPreviousChapter: () -> Unit,
    onNextChapter: () -> Unit,
    onShowChapterList: () -> Unit,
    onPlayPause: () -> Unit,
    onStopListening: () -> Unit,
    onPreviousParagraph: () -> Unit,
    onNextParagraph: () -> Unit,
    canGoPrevious: Boolean,
    canGoNext: Boolean,
    showTtsControls: Boolean
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
        shadowElevation = 8.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AppDimens.PaddingMedium)
        ) {
            // TTS 段落控制（播放时显示）
            if (showTtsControls) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // 上一段
                    IconButton(onClick = onPreviousParagraph) {
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowUp,
                            contentDescription = "上一段",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                    
                    // 播放/暂停
                    FloatingActionButton(
                        onClick = onPlayPause,
                        containerColor = MaterialTheme.customColors.gradientStart,
                        modifier = Modifier.size(56.dp)
                    ) {
                        Icon(
                            imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = if (isPlaying) "暂停" else "播放",
                            tint = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.size(28.dp)
                        )
                    }
                    
                    // 下一段
                    IconButton(onClick = onNextParagraph) {
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowDown,
                            contentDescription = "下一段",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                    
                    // 停止听书
                    IconButton(onClick = onStopListening) {
                        Icon(
                            imageVector = Icons.Default.Stop,
                            contentDescription = "停止",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
                
                Spacer(modifier = Modifier.height(8.dp))
                Divider(color = MaterialTheme.customColors.border)
                Spacer(modifier = Modifier.height(8.dp))
            }
            
            // 基础阅读控制
            Row(
                modifier = Modifier.fillMaxWidth(),
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
                
                // 听书按钮（未播放时显示）
                if (!showTtsControls) {
                    FloatingActionButton(
                        onClick = onPlayPause,
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
                                
                                if (chapter.duration.isNotEmpty()) {
                                    Text(
                                        text = "时长: ${chapter.duration}",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.customColors.textSecondary
                                    )
                                }
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
