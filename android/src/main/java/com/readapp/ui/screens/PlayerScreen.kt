// PlayerScreen.kt - 听书播放器页面
package com.readapp.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.readapp.data.model.Book
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@Composable
fun PlayerScreen(
    book: Book,
    chapterTitle: String,
    currentParagraph: Int,
    totalParagraphs: Int,
    currentTime: String,
    totalTime: String,
    progress: Float,
    isPlaying: Boolean,
    onPlayPauseClick: () -> Unit,
    onPreviousParagraph: () -> Unit,
    onNextParagraph: () -> Unit,
    onPreviousChapter: () -> Unit,
    onNextChapter: () -> Unit,
    onShowChapterList: () -> Unit,
    onExit: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(AppDimens.PaddingLarge),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // 顶部工具栏
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onExit) {
                Icon(
                    imageVector = Icons.Default.KeyboardArrowDown,
                    contentDescription = "退出",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
            
            IconButton(onClick = { /* 更多选项 */ }) {
                Icon(
                    imageVector = Icons.Default.MoreVert,
                    contentDescription = "更多",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
        }
        
        Spacer(modifier = Modifier.height(32.dp))
        
        // 大封面
        BookCoverLarge(
            emoji = book.coverEmoji,
            isPlaying = isPlaying,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .padding(horizontal = 32.dp)
        )
        
        Spacer(modifier = Modifier.height(32.dp))
        
        // 播放信息
        PlaybackInfo(
            bookTitle = book.title,
            chapterTitle = chapterTitle,
            currentParagraph = currentParagraph,
            totalParagraphs = totalParagraphs
        )
        
        Spacer(modifier = Modifier.height(24.dp))
        
        // 进度条
        PlaybackProgress(
            progress = progress,
            currentTime = currentTime,
            totalTime = totalTime
        )
        
        Spacer(modifier = Modifier.height(32.dp))
        
        // 播放控制
        PlaybackControls(
            isPlaying = isPlaying,
            onPlayPauseClick = onPlayPauseClick,
            onPreviousChapter = onPreviousChapter,
            onNextChapter = onNextChapter
        )
        
        Spacer(modifier = Modifier.height(24.dp))
        
        // 快捷控制
        QuickControls(
            onPreviousParagraph = onPreviousParagraph,
            onShowChapterList = onShowChapterList,
            onNextParagraph = onNextParagraph
        )
    }
}

@Composable
private fun BookCoverLarge(
    emoji: String,
    isPlaying: Boolean,
    modifier: Modifier = Modifier
) {
    val scale by animateFloatAsState(
        targetValue = if (isPlaying) 1.05f else 1f,
        label = "cover scale"
    )
    
    Box(
        modifier = modifier
            .scale(scale)
            .clip(RoundedCornerShape(32.dp))
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(
                        MaterialTheme.customColors.gradientStart,
                        MaterialTheme.customColors.gradientEnd,
                        MaterialTheme.colorScheme.secondary
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = emoji,
            style = MaterialTheme.typography.displayLarge,
            fontSize = 120.sp
        )
    }
}

@Composable
private fun PlaybackInfo(
    bookTitle: String,
    chapterTitle: String,
    currentParagraph: Int,
    totalParagraphs: Int
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = bookTitle,
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center
        )
        
        Text(
            text = chapterTitle,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.customColors.textSecondary,
            textAlign = TextAlign.Center
        )
        
        Text(
            text = "段落 $currentParagraph/$totalParagraphs",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.customColors.textSecondary
        )
    }
}

@Composable
private fun PlaybackProgress(
    progress: Float,
    currentTime: String,
    totalTime: String
) {
    Column {
        Slider(
            value = progress,
            onValueChange = { /* 处理进度调整 */ },
            modifier = Modifier.fillMaxWidth(),
            colors = SliderDefaults.colors(
                thumbColor = MaterialTheme.customColors.gradientStart,
                activeTrackColor = MaterialTheme.customColors.gradientStart,
                inactiveTrackColor = MaterialTheme.customColors.border
            )
        )
        
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = currentTime,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.customColors.textSecondary
            )
            
            Text(
                text = totalTime,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.customColors.textSecondary
            )
        }
    }
}

@Composable
private fun PlaybackControls(
    isPlaying: Boolean,
    onPlayPauseClick: () -> Unit,
    onPreviousChapter: () -> Unit,
    onNextChapter: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 上一章按钮
        Surface(
            onClick = onPreviousChapter,
            shape = CircleShape,
            color = MaterialTheme.customColors.cardBackground,
            modifier = Modifier.size(64.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Default.SkipPrevious,
                    contentDescription = "上一章",
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(32.dp)
                )
            }
        }
        
        // 播放/暂停按钮
        Surface(
            onClick = onPlayPauseClick,
            shape = CircleShape,
            color = MaterialTheme.customColors.gradientStart,
            shadowElevation = 8.dp,
            modifier = Modifier.size(80.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = if (isPlaying) {
                        Icons.Default.Pause
                    } else {
                        Icons.Default.PlayArrow
                    },
                    contentDescription = if (isPlaying) "暂停" else "播放",
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(40.dp)
                )
            }
        }
        
        // 下一章按钮
        Surface(
            onClick = onNextChapter,
            shape = CircleShape,
            color = MaterialTheme.customColors.cardBackground,
            modifier = Modifier.size(64.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Default.SkipNext,
                    contentDescription = "下一章",
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(32.dp)
                )
            }
        }
    }
}

@Composable
private fun QuickControls(
    onPreviousParagraph: () -> Unit,
    onShowChapterList: () -> Unit,
    onNextParagraph: () -> Unit
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
            horizontalArrangement = Arrangement.SpaceAround
        ) {
            QuickControlButton(
                icon = Icons.Default.ArrowBack,
                label = "上一段",
                onClick = onPreviousParagraph
            )
            
            QuickControlButton(
                icon = Icons.Default.List,
                label = "目录",
                onClick = onShowChapterList
            )
            
            QuickControlButton(
                icon = Icons.Default.ArrowForward,
                label = "下一段",
                onClick = onNextParagraph
            )
        }
    }
}

@Composable
private fun QuickControlButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Surface(
            onClick = onClick,
            shape = CircleShape,
            color = MaterialTheme.customColors.border.copy(alpha = 0.3f),
            modifier = Modifier.size(48.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = icon,
                    contentDescription = label,
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(24.dp)
                )
            }
        }
        
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.customColors.textSecondary
        )
    }
}
