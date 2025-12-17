// ReadingScreen.kt - 阅读页面
package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextOverflow
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
    onChapterClick: (Int) -> Unit,
    onStartListening: () -> Unit,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showChapterList by remember { mutableStateOf(true) }
    
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(AppDimens.PaddingMedium)
    ) {
        // 返回按钮
        IconButton(
            onClick = onNavigateBack,
            modifier = Modifier.size(40.dp)
        ) {
            Icon(
                imageVector = Icons.Default.ArrowBack,
                contentDescription = "返回",
                tint = MaterialTheme.colorScheme.onSurface
            )
        }
        
        Spacer(modifier = Modifier.height(AppDimens.PaddingMedium))
        
        // 书籍信息卡片
        BookInfoCard(
            book = book,
            onContinueReading = { /* 继续阅读 */ },
            onStartListening = onStartListening
        )
        
        Spacer(modifier = Modifier.height(AppDimens.PaddingMedium))
        
        // 章节列表
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "章节列表",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
            IconButton(onClick = { showChapterList = !showChapterList }) {
                Icon(
                    imageVector = if (showChapterList) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (showChapterList) "折叠章节列表" else "展开章节列表"
                )
            }
        }

        if (showChapterList) {
            ChapterListCard(
                chapters = chapters,
                currentChapterIndex = currentChapterIndex,
                onChapterClick = onChapterClick,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun BookInfoCard(
    book: Book,
    onContinueReading: () -> Unit,
    onStartListening: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.customColors.cardBackground
        ),
        elevation = CardDefaults.cardElevation(
            defaultElevation = AppDimens.ElevationSmall
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AppDimens.PaddingMedium),
            horizontalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium)
        ) {
            // 封面
            Box(
                modifier = Modifier
                    .width(80.dp)
                    .height(110.dp)
                    .clip(RoundedCornerShape(AppDimens.CornerRadiusMedium))
                    .background(
                        brush = Brush.linearGradient(
                            colors = listOf(
                                MaterialTheme.customColors.gradientStart,
                                MaterialTheme.customColors.gradientEnd
                            )
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = book.coverEmoji,
                    style = MaterialTheme.typography.displayMedium
                )
            }
            
            // 书籍信息
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = book.title,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                
                Text(
                    text = book.author,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.customColors.textSecondary
                )
                
                Spacer(modifier = Modifier.height(4.dp))
                
                // 操作按钮
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = onContinueReading,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.customColors.gradientStart
                        ),
                        shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                        contentPadding = PaddingValues(
                            horizontal = 16.dp,
                            vertical = 8.dp
                        )
                    ) {
                        Text(
                            text = "继续阅读",
                            style = MaterialTheme.typography.labelMedium
                        )
                    }
                    
                    OutlinedButton(
                        onClick = onStartListening,
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.customColors.success
                        ),
                        shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                        contentPadding = PaddingValues(
                            horizontal = 16.dp,
                            vertical = 8.dp
                        )
                    ) {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "听书",
                            style = MaterialTheme.typography.labelMedium
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ChapterListCard(
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    onChapterClick: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val listState = rememberLazyListState()
    
    LaunchedEffect(currentChapterIndex) {
        listState.animateScrollToItem(currentChapterIndex)
    }
    
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.customColors.cardBackground
        ),
        elevation = CardDefaults.cardElevation(
            defaultElevation = AppDimens.ElevationSmall
        )
    ) {
        Column {
            // 标题栏
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(AppDimens.PaddingMedium),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "章节列表",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
                
                Text(
                    text = "${currentChapterIndex + 1}/${chapters.size}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.customColors.textSecondary
                )
            }
            
            Divider(color = MaterialTheme.customColors.border)
            
            // 章节列表
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxWidth()
            ) {
                itemsIndexed(chapters) { index, chapter ->
                    ChapterItem(
                        chapter = chapter,
                        isCurrentChapter = index == currentChapterIndex,
                        onClick = { onChapterClick(index) }
                    )
                    
                    if (index < chapters.size - 1) {
                        Divider(
                            color = MaterialTheme.customColors.border,
                            modifier = Modifier.padding(horizontal = AppDimens.PaddingMedium)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ChapterItem(
    chapter: Chapter,
    isCurrentChapter: Boolean,
    onClick: () -> Unit
) {
    val backgroundColor = if (isCurrentChapter) {
        MaterialTheme.customColors.gradientStart.copy(alpha = 0.2f)
    } else {
        MaterialTheme.colorScheme.surface
    }
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(backgroundColor)
            .clickable(onClick = onClick)
            .padding(AppDimens.PaddingMedium),
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
            
            Spacer(modifier = Modifier.height(4.dp))
            
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

// 数据模型定义移动到 data/model 包
