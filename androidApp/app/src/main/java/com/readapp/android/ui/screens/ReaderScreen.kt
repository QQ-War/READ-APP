package com.readapp.android.ui.screens

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.NavigateBefore
import androidx.compose.material.icons.outlined.NavigateNext
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import com.readapp.android.model.Book
import com.readapp.android.model.BookChapter
import com.readapp.android.model.HttpTTS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(
    book: Book,
    chapters: List<BookChapter>,
    currentIndex: Int?,
    content: String,
    paragraphs: List<String>,
    currentParagraphIndex: Int,
    isChapterReversed: Boolean,
    ttsEngines: List<HttpTTS>,
    selectedTtsId: String?,
    speechRate: Double,
    preloadSegments: Int,
    preloadedChapters: List<Int>,
    fontScale: Float,
    lineSpacing: Float,
    isLoading: Boolean,
    isSpeaking: Boolean,
    isNearChapterEnd: Boolean,
    upcomingChapterIndex: Int?,
    onBack: () -> Unit,
    onSelectChapter: (Int) -> Unit,
    onToggleTts: () -> Unit,
    onTtsEngineSelect: (String) -> Unit,
    onSpeechRateChange: (Double) -> Unit,
    onPreloadSegmentsChange: (Int) -> Unit,
    onFontScaleChange: (Float) -> Unit,
    onLineSpacingChange: (Float) -> Unit,
    onReverseChaptersChange: (Boolean) -> Unit,
    onParagraphJump: (Int) -> Unit,
    onToggleImmersive: () -> Unit,
    isImmersive: Boolean
) {
    val safeIndex = remember(currentIndex) { currentIndex ?: 0 }
    val chapterTitle = chapters.getOrNull(safeIndex)?.title ?: book.durChapterTitle.orEmpty()
    val bodyStyle = MaterialTheme.typography.bodyLarge
    val contentStyle = bodyStyle.copy(
        fontSize = bodyStyle.fontSize * fontScale,
        lineHeight = if (bodyStyle.lineHeight.isSpecified) {
            bodyStyle.lineHeight * lineSpacing
        } else {
            bodyStyle.fontSize * lineSpacing
        }
    )
    var ttsMenuExpanded by remember { mutableStateOf(false) }
    val selectedTtsName = ttsEngines.firstOrNull { it.id == selectedTtsId }?.name
    val highlightColor = MaterialTheme.colorScheme.secondary.copy(alpha = 0.2f)
    val preloadColor = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.18f)
    var paragraphSlider by remember(currentParagraphIndex, paragraphs.size) { mutableStateOf(currentParagraphIndex.toFloat()) }
    val upcomingTitle = upcomingChapterIndex?.let { idx -> chapters.getOrNull(idx)?.title }
    val isDark = isSystemInDarkTheme()
    val transition = rememberInfiniteTransition(label = "paragraph_pulse")
    val pulseAlpha by transition.animateFloat(
        initialValue = 0.16f,
        targetValue = 0.28f,
        animationSpec = infiniteRepeatable(tween(1200), repeatMode = RepeatMode.Reverse),
        label = "paragraph_alpha"
    )
    val displayParagraphs = if (paragraphs.isNotEmpty()) paragraphs else listOf(content.ifBlank { "暂无内容，点击章节加载。" })

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                navigationIcon = {
                    IconButton(onClick = onBack, enabled = !isLoading) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回书架")
                    }
                },
                title = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = book.name ?: "未命名",
                            style = MaterialTheme.typography.titleMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = chapterTitle,
                            style = MaterialTheme.typography.bodyMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onToggleImmersive) {
                        Icon(
                            imageVector = if (isImmersive) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                            contentDescription = if (isImmersive) "退出沉浸" else "沉浸模式"
                        )
                    }
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = MaterialTheme.colorScheme.surface)
            )
        },
        bottomBar = {
            Surface(tonalElevation = 6.dp) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = { onSelectChapter((safeIndex - 1).coerceAtLeast(0)) },
                        enabled = !isLoading && safeIndex > 0
                    ) {
                        Icon(Icons.Outlined.NavigateBefore, contentDescription = "上一章")
                    }
                    Button(
                        modifier = Modifier.weight(1f),
                        onClick = onToggleTts,
                        enabled = !isLoading
                    ) {
                        Icon(
                            if (isSpeaking) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                            contentDescription = null
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(if (isSpeaking) "暂停朗读" else "播放本章")
                    }
                    IconButton(
                        onClick = { onSelectChapter((safeIndex + 1).coerceAtMost(chapters.lastIndex)) },
                        enabled = !isLoading && chapters.isNotEmpty() && safeIndex < chapters.lastIndex
                    ) {
                        Icon(Icons.Outlined.NavigateNext, contentDescription = "下一章")
                    }
                }
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssistChip(
                    onClick = { onReverseChaptersChange(!isChapterReversed) },
                    label = { Text(if (isChapterReversed) "章节倒序" else "章节正序") }
                )
                if (preloadedChapters.isNotEmpty()) {
                    AssistChip(onClick = {}, label = { Text("已预载: ${preloadedChapters.joinToString { "第${it + 1}章" }}") })
                }
            }

            ElevatedCard {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(text = "听书与阅读", style = MaterialTheme.typography.titleMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        Button(onClick = { ttsMenuExpanded = true }, enabled = ttsEngines.isNotEmpty()) {
                            Text(selectedTtsName ?: "选择 TTS 引擎")
                        }
                        DropdownMenu(expanded = ttsMenuExpanded, onDismissRequest = { ttsMenuExpanded = false }) {
                            ttsEngines.forEach { tts ->
                                DropdownMenuItem(
                                    text = { Text(tts.name) },
                                    onClick = {
                                        onTtsEngineSelect(tts.id)
                                        ttsMenuExpanded = false
                                    }
                                )
                            }
                        }
                        Text(text = "语速 ${"%.1f".format(speechRate)}x", style = MaterialTheme.typography.labelMedium)
                    }
                    Slider(
                        value = speechRate.toFloat(),
                        onValueChange = { onSpeechRateChange(it.toDouble()) },
                        valueRange = 0.6f..2.0f,
                        steps = 7
                    )
                    Text(text = "预载章节数 $preloadSegments", style = MaterialTheme.typography.labelMedium)
                    Slider(
                        value = preloadSegments.toFloat(),
                        onValueChange = { onPreloadSegmentsChange(it.toInt()) },
                        valueRange = 0f..3f,
                        steps = 3
                    )

                    Divider()

                    Text(text = "阅读设置", style = MaterialTheme.typography.titleSmall)
                    Text(text = "字体大小 ${"%.1f".format(fontScale)}x")
                    Slider(
                        value = fontScale,
                        onValueChange = onFontScaleChange,
                        valueRange = 0.8f..1.6f,
                        steps = 7
                    )
                    Text(text = "行间距 ${"%.1f".format(lineSpacing)}x")
                    Slider(
                        value = lineSpacing,
                        onValueChange = onLineSpacingChange,
                        valueRange = 1.0f..2.0f,
                        steps = 9
                    )

                    if (paragraphs.isNotEmpty()) {
                        Text(text = "段落进度 ${currentParagraphIndex + 1}/${paragraphs.size}")
                        Slider(
                            value = paragraphSlider,
                            onValueChange = { paragraphSlider = it },
                            onValueChangeFinished = { onParagraphJump(paragraphSlider.toInt().coerceIn(0, paragraphs.lastIndex)) },
                            valueRange = 0f..paragraphs.lastIndex.toFloat(),
                            steps = (paragraphs.size - 2).coerceAtLeast(0)
                        )
                        if (isNearChapterEnd && upcomingChapterIndex != null) {
                            Row(
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(preloadColor.copy(alpha = if (isDark) 0.3f else 0.22f))
                                    .padding(12.dp)
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(text = "章节即将结束，已预载下一章", style = MaterialTheme.typography.titleSmall)
                                    Text(text = upcomingTitle ?: "第${upcomingChapterIndex + 1}章", maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                                Button(onClick = { onSelectChapter(upcomingChapterIndex) }) { Text("提前跳转") }
                            }
                        }
                    }
                }
            }

            ElevatedCard(modifier = Modifier.weight(1f, fill = true)) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(text = "本章内容", style = MaterialTheme.typography.titleMedium)
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(bottom = 8.dp),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        itemsIndexed(displayParagraphs) { index, paragraph ->
                            val isCurrent = index == currentParagraphIndex && isSpeaking
                            val isEndCue = paragraphs.isNotEmpty() && index >= paragraphs.size - 2
                            val baseColor = when {
                                isCurrent -> highlightColor.copy(alpha = 0.4f)
                                isEndCue -> preloadColor.copy(alpha = 0.3f)
                                else -> MaterialTheme.colorScheme.surface
                            }
                            val animatedBackground by animateColorAsState(
                                targetValue = baseColor.copy(alpha = if (isCurrent || isEndCue) pulseAlpha + baseColor.alpha else baseColor.alpha),
                                label = "paragraph_bg"
                            )
                            val brush = if (isEndCue) {
                                Brush.verticalGradient(
                                    colors = listOf(
                                        animatedBackground,
                                        MaterialTheme.colorScheme.surface
                                    )
                                )
                            } else null
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(4.dp)
                            ) {
                                Text(
                                    text = paragraph,
                                    style = contentStyle,
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(8.dp)
                                        .clip(RoundedCornerShape(8.dp))
                                        .then(
                                            if (brush != null) {
                                                Modifier.background(brush)
                                            } else {
                                                Modifier.background(animatedBackground)
                                            }
                                        ),
                                    maxLines = Int.MAX_VALUE
                                )
                            }
                            Divider()
                        }
                    }
                }
            }

            ElevatedCard(modifier = Modifier.heightIn(min = 200.dp)) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(text = "章节列表", style = MaterialTheme.typography.titleMedium)
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(chapters, key = { it.index }) { chapter ->
                            val isNextUp = upcomingChapterIndex == chapter.index
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(4.dp)
                                    .background(
                                        when {
                                            isNextUp -> highlightColor.copy(alpha = 0.25f)
                                            preloadedChapters.contains(chapter.index) -> preloadColor
                                            else -> MaterialTheme.colorScheme.surface
                                        }
                                    ),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = chapter.title,
                                    modifier = Modifier.weight(1f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Button(onClick = { onSelectChapter(chapter.index) }, enabled = !isLoading) {
                                    Text(if (chapter.index == safeIndex) "阅读中" else "阅读")
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
