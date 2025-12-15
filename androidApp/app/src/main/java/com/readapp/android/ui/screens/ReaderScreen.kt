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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import com.readapp.android.model.Book
import com.readapp.android.model.BookChapter
import com.readapp.android.model.HttpTTS

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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            Button(onClick = onBack, enabled = !isLoading) { Text("返回书架") }
            Button(onClick = { onSelectChapter((safeIndex - 1).coerceAtLeast(0)) }, enabled = !isLoading && safeIndex > 0) {
                Text("上一章")
            }
            Button(onClick = { onSelectChapter((safeIndex + 1).coerceAtMost(chapters.lastIndex)) }, enabled = !isLoading && chapters.isNotEmpty() && safeIndex < chapters.lastIndex) {
                Text("下一章")
            }
            Button(onClick = onToggleTts, enabled = !isLoading) { Text(if (isSpeaking) "停止朗读" else "朗读本章") }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            Button(onClick = onToggleImmersive) { Text(if (isImmersive) "退出沉浸" else "沉浸模式") }
            if (preloadedChapters.isNotEmpty()) {
                Text(
                    text = "已预载: ${preloadedChapters.joinToString { "第${it + 1}章" }}",
                    color = MaterialTheme.colorScheme.tertiary
                )
            }
        }

        Text(text = book.name ?: "未命名", style = MaterialTheme.typography.titleLarge)
        Text(text = chapterTitle, style = MaterialTheme.typography.titleMedium)

        Divider()

        if (!isImmersive) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(text = "听书设置", style = MaterialTheme.typography.titleSmall)
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
                }
                Text(text = "语速 ${"%.1f".format(speechRate)}x")
                Slider(
                    value = speechRate.toFloat(),
                    onValueChange = { onSpeechRateChange(it.toDouble()) },
                    valueRange = 0.6f..2.0f,
                    steps = 7
                )
                Text(text = "预载章节数 $preloadSegments")
                Slider(
                    value = preloadSegments.toFloat(),
                    onValueChange = { onPreloadSegmentsChange(it.toInt()) },
                    valueRange = 0f..3f,
                    steps = 3
                )
            }

            Divider()

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = if (isChapterReversed) "章节倒序" else "章节正序")
                    Button(onClick = { onReverseChaptersChange(!isChapterReversed) }) { Text("切换章节顺序") }
                }
            }

            Divider()
        }

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

        val displayParagraphs = if (paragraphs.isNotEmpty()) paragraphs else listOf(content.ifBlank { "暂无内容，点击章节加载。" })
        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.weight(1f, fill = true)) {
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

        Divider()

        Text(text = "章节列表", style = MaterialTheme.typography.titleMedium)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.weight(0.8f, fill = false)) {
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
                    horizontalArrangement = Arrangement.SpaceBetween
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
