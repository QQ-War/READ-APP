// ReadingScreen.kt - 阅读页面集成听书功能（段落高亮）
package com.readapp.ui.screens

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.changedToUp
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.TextUnit
import coil.compose.AsyncImage
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors
import kotlinx.coroutines.launch
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import com.readapp.data.ReadingMode
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ReadingScreen(
    book: Book,
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    currentChapterContent: String,
    isContentLoading: Boolean,
    readingFontSize: Float,
    errorMessage: String?,
    onClearError: () -> Unit,
    onChapterClick: (Int) -> Unit,
    onLoadChapterContent: (Int) -> Unit,
    onNavigateBack: () -> Unit,
    // TTS 相关状态
    isPlaying: Boolean = false,
    currentPlayingParagraph: Int = -1,  // 当前播放的段落索引
    preloadedParagraphs: Set<Int> = emptySet(),  // 已预载的段落索引
    preloadedChapters: Set<Int> = emptySet(),
    showTtsControls: Boolean = false,
    onPlayPauseClick: () -> Unit = {},
    onStartListening: (Int) -> Unit = {},
    onStopListening: () -> Unit = {},
    onPreviousParagraph: () -> Unit = {},
    onNextParagraph: () -> Unit = {},
    onReadingFontSizeChange: (Float) -> Unit = {},
    onExit: () -> Unit = {},
    readingMode: com.readapp.data.ReadingMode = com.readapp.data.ReadingMode.Vertical,
    modifier: Modifier = Modifier
) {
    var showControls by remember { mutableStateOf(false) }
    var showChapterList by remember { mutableStateOf(false) }
    var showFontDialog by remember { mutableStateOf(false) }
    var currentPageStartIndex by remember { mutableStateOf(0) }
    var pendingJumpToLastPage by remember { mutableStateOf(false) }
    val scrollState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    val latestOnExit by rememberUpdatedState(onExit)
    val contentPadding = remember {
        PaddingValues(
            start = AppDimens.PaddingLarge,
            end = AppDimens.PaddingLarge,
            top = AppDimens.PaddingLarge,
            bottom = AppDimens.PaddingLarge
        )
    }
    
    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = onClearError,
            title = { Text("错误") },
            text = { Text(errorMessage) },
            confirmButton = {
                TextButton(onClick = onClearError) {
                    Text("好的")
                }
            }
        )
    }
    
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

    DisposableEffect(Unit) {
        onDispose {
            latestOnExit()
        }
    }
    
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // 主要内容区域：显示章节正文
        Column(
            modifier = Modifier
                .fillMaxSize()
                .clickable(
                    enabled = readingMode == ReadingMode.Vertical,
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) {
                    // 点击切换控制栏显示/隐藏
                    showControls = !showControls
                }
        ) {
            // 内容区域
            if (readingMode == com.readapp.data.ReadingMode.Vertical) {
                LazyColumn(
                    state = scrollState,
                    modifier = Modifier
                        .fillMaxSize()
                        .weight(1f),
                    contentPadding = contentPadding
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
                                if (isContentLoading) {
                                    CircularProgressIndicator()
                                    Text(
                                        text = "正在加载章节内容...",
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.customColors.textSecondary,
                                        textAlign = TextAlign.Center
                                    )
                                } else {
                                    Text(
                                        text = displayContent.ifBlank { "暂无可显示的内容" },
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.customColors.textSecondary,
                                        textAlign = TextAlign.Center
                                    )
                                }
                            }
                        }
                    } else {
                        // 章节内容（分段显示，带高亮）
                        itemsIndexed(paragraphs) { index, paragraph ->
                            ParagraphItem(
                                text = paragraph,
                                isPlaying = index == currentPlayingParagraph,
                                isPreloaded = preloadedParagraphs.contains(index),
                                fontSize = readingFontSize,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(bottom = AppDimens.PaddingMedium)
                            )
                        }
                    }
                }
            } else {
                BoxWithConstraints(
                    modifier = Modifier
                        .fillMaxSize()
                        .weight(1f)
                ) {
                    val style = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = readingFontSize.sp,
                        lineHeight = (readingFontSize * 1.8f).sp
                    )
                    val lineHeightPx = with(LocalDensity.current) {
                        val lineHeight = style.lineHeight
                        if (lineHeight.value.isNaN() || lineHeight.value <= 0f) {
                            (readingFontSize * 1.8f).sp.toPx()
                        } else {
                            lineHeight.toPx()
                        }
                    }
                    val pagePadding = contentPadding
                    val density = LocalDensity.current
                    val availableConstraints = remember(constraints, pagePadding, density) {
                        adjustedConstraints(constraints, pagePadding, density)
                    }
                    
                    val paginatedPages = rememberPaginatedText(
                        paragraphs = paragraphs,
                        style = style,
                        constraints = availableConstraints,
                        lineHeightPx = lineHeightPx
                    )
                    val pageTextCache = remember { mutableStateMapOf<Int, String>() }
                    val pagerState = rememberPagerState { paginatedPages.pages.size.coerceAtLeast(1) }
                    val viewConfiguration = LocalViewConfiguration.current
                    val onPreviousChapterFromPager = {
                        if (currentChapterIndex > 0) {
                            pendingJumpToLastPage = true
                            onChapterClick(currentChapterIndex - 1)
                        }
                    }
                                        val onNextChapterFromPager = {
                                            if (currentChapterIndex < chapters.size - 1) {
                                                onChapterClick(currentChapterIndex + 1)
                                            }
                                        }
                    
                                        Box(modifier = Modifier.fillMaxSize()) {
                                            HorizontalPager(
                                                state = pagerState,
                                                modifier = Modifier
                                                    .fillMaxSize()
                                                    .pointerInput(
                                                        showControls,
                                                        paginatedPages,
                                                        currentChapterIndex,
                                                        viewConfiguration
                                                    ) {
                                                        detectTapGesturesWithoutConsuming(viewConfiguration) { offset, size ->
                                                            handleHorizontalTap(
                                                                offset = offset,
                                                                size = size,
                                                                showControls = showControls,
                                                                pagerState = pagerState,
                                                                paginatedPages = paginatedPages.pages,
                                                                onPreviousChapter = onPreviousChapterFromPager,
                                                                onNextChapter = onNextChapterFromPager,
                                                                coroutineScope = coroutineScope,
                                                                onToggleControls = { showControls = it }
                                                            )
                                                        }
                                                    }
                                            ) { page ->
                                                val pageText = paginatedPages.getOrNull(page)?.let { pageInfo ->
                                                    pageTextCache[page] ?: run {
                                                        val safeStart = pageInfo.start.coerceAtLeast(0)
                                                        val safeEnd = pageInfo.end.coerceAtMost(paginatedPages.fullText.length)
                                                        val text = if (safeEnd > safeStart) {
                                                            paginatedPages.fullText.substring(safeStart, safeEnd)
                                                        } else {
                                                            ""
                                                        }
                                                        pageTextCache[page] = text
                                                        text
                                                    }
                                                }.orEmpty()
                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxSize()
                                                        .padding(pagePadding)
                                                ) {
                                                    Text(
                                                        text = pageText,
                                                        style = style
                                                    )
                                                }
                                            }
                    
                                            if (!showControls && pagerState.pageCount > 0) {
                                                val percentage = ((pagerState.currentPage + 1) * 100) / pagerState.pageCount
                                                Text(
                                                    text = "${pagerState.currentPage + 1}/${pagerState.pageCount} ($percentage%)",
                                                    modifier = Modifier
                                                        .align(Alignment.BottomEnd)
                                                        .padding(horizontal = 16.dp, vertical = 8.dp)
                                                        .background(
                                                            MaterialTheme.colorScheme.surface.copy(alpha = 0.5f),
                                                            RoundedCornerShape(8.dp)
                                                        )
                                                        .padding(horizontal = 8.dp, vertical = 4.dp),
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurface
                                                )
                                            }
                    
                                            LaunchedEffect(pagerState.currentPage, paginatedPages) {
                                                currentPageStartIndex = paginatedPages
                                                    .getOrNull(pagerState.currentPage)
                                                    ?.startParagraphIndex
                                                    ?: 0
                                            }
                                            
                                            LaunchedEffect(pagerState.currentPage, paginatedPages.fullText) {
                                                if (paginatedPages.isEmpty()) {
                                                    pageTextCache.clear()
                                                    return@LaunchedEffect
                                                }
                                                val current = pagerState.currentPage
                                                val indices = listOf(current - 1, current, current + 1)
                                                    .filter { it in paginatedPages.indices }
                                                    .toSet()
                                                for (index in indices) {
                                                    if (!pageTextCache.containsKey(index)) {
                                                        val pageInfo = paginatedPages[index]
                                                        val safeStart = pageInfo.start.coerceAtLeast(0)
                                                        val safeEnd = pageInfo.end.coerceAtMost(paginatedPages.fullText.length)
                                                        val text = if (safeEnd > safeStart) {
                                                            paginatedPages.fullText.substring(safeStart, safeEnd)
                                                        } else {
                                                            ""
                                                        }
                                                        pageTextCache[index] = text
                                                    }
                                                }
                                                val staleKeys = pageTextCache.keys.filter { it !in indices }
                                                for (key in staleKeys) {
                                                    pageTextCache.remove(key)
                                                }
                                            }
                    
                                            LaunchedEffect(pendingJumpToLastPage, paginatedPages, currentChapterIndex) {
                                                if (pendingJumpToLastPage && !paginatedPages.isEmpty()) {
                                                    pagerState.scrollToPage(paginatedPages.lastIndex)
                                                    pendingJumpToLastPage = false
                                                }
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
                isPlaying = isPlaying,
                onPreviousChapter = {
                    if (currentChapterIndex > 0) {
                        if (readingMode == ReadingMode.Horizontal) {
                            pendingJumpToLastPage = true
                        }
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
                            val pageStart = if (readingMode == ReadingMode.Horizontal) {
                                currentPageStartIndex
                            } else {
                                0
                            }
                            onStartListening(pageStart)
                        } else {
                            // 继续播放
                            onPlayPauseClick()
                        }
                    }
                },
                onStopListening = onStopListening,
                onPreviousParagraph = onPreviousParagraph,
                onNextParagraph = onNextParagraph,
                onFontSettings = { showFontDialog = true },
                canGoPrevious = currentChapterIndex > 0,
                canGoNext = currentChapterIndex < chapters.size - 1,
                showTtsControls = showTtsControls  // 仅在实际播放/保持播放时显示 TTS 控制
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
                preloadedChapters = preloadedChapters,
                onChapterClick = { index ->
                    onChapterClick(index)
                    showChapterList = false
                },
                onDismiss = { showChapterList = false }
            )
        }

        if (showFontDialog) {
            FontSizeDialog(
                value = readingFontSize,
                onValueChange = onReadingFontSizeChange,
                onDismiss = { showFontDialog = false }
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
    fontSize: Float,
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
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = fontSize.sp),
            color = MaterialTheme.colorScheme.onSurface,
            lineHeight = (fontSize * 1.8f).sp,
            modifier = Modifier.padding(
                horizontal = if (isPlaying || isPreloaded) 12.dp else 0.dp,
                vertical = if (isPlaying || isPreloaded) 8.dp else 0.dp
            )
        )
    }
}



@Composable
private fun rememberPaginatedText(
    paragraphs: List<String>,
    style: TextStyle,
    constraints: Constraints,
    lineHeightPx: Float
): PaginationResult {
    val textMeasurer = rememberTextMeasurer()

    return remember(paragraphs, style, constraints, lineHeightPx) {
        if (paragraphs.isEmpty() || constraints.maxWidth == 0 || constraints.maxHeight == 0) {
            return@remember PaginationResult(emptyList(), "")
        }

        val paragraphStartIndices = paragraphStartIndices(paragraphs)
        val fullText = fullContent(paragraphs)
        val layout = textMeasurer.measure(
            text = AnnotatedString(fullText),
            style = style,
            constraints = Constraints(
                maxWidth = constraints.maxWidth,
                maxHeight = Constraints.Infinity
            )
        )
        if (layout.lineCount == 0) {
            return@remember PaginationResult(emptyList(), fullText)
        }
        val minPageHeight = if (lineHeightPx > 0f) lineHeightPx else 1f
        val pageHeight = constraints.maxHeight.toFloat().coerceAtLeast(minPageHeight)
        val pages = mutableListOf<PaginatedPage>()
        var startLine = 0
        while (startLine < layout.lineCount) {
            val pageTop = layout.getLineTop(startLine)
            var endLine = startLine
            while (endLine + 1 < layout.lineCount) {
                val nextBottom = layout.getLineBottom(endLine + 1)
                if (nextBottom - pageTop <= pageHeight) {
                    endLine++
                } else {
                    break
                }
            }
            val startOffset = layout.getLineStart(startLine)
            val endOffset = layout.getLineEnd(endLine, visibleEnd = true)
            if (endOffset <= startOffset) {
                break
            }
            val startParagraphIndex = paragraphIndexForOffset(startOffset, paragraphStartIndices)
            pages.add(PaginatedPage(start = startOffset, end = endOffset, startParagraphIndex = startParagraphIndex))
            startLine = endLine + 1
        }
        PaginationResult(pages, fullText)
    }
}

private data class PaginatedPage(
    val start: Int,
    val end: Int,
    val startParagraphIndex: Int
)

private data class PaginationResult(
    val pages: List<PaginatedPage>,
    val fullText: String
) {
    val indices: IntRange
        get() = pages.indices

    val lastIndex: Int
        get() = pages.lastIndex

    fun isEmpty(): Boolean = pages.isEmpty()

    fun getOrNull(index: Int): PaginatedPage? = pages.getOrNull(index)

    operator fun get(index: Int): PaginatedPage = pages[index]
}

private fun fullContent(paragraphs: List<String>): String {
    return paragraphs.joinToString(separator = "\n\n") { it.trim() }
}

private fun paragraphStartIndices(paragraphs: List<String>): List<Int> {
    val starts = mutableListOf<Int>()
    var currentIndex = 0
    paragraphs.forEachIndexed { index, paragraph ->
        starts.add(currentIndex)
        currentIndex += paragraph.trim().length
        if (index < paragraphs.lastIndex) {
            currentIndex += 2
        }
    }
    return starts
}

private fun paragraphIndexForOffset(offset: Int, starts: List<Int>): Int {
    return starts.indexOfLast { it <= offset }.coerceAtLeast(0)
}

private fun lastVisibleOffset(result: androidx.compose.ui.text.TextLayoutResult): Int {
    if (result.lineCount == 0) {
        return 0
    }
    return result.getLineEnd(result.lineCount - 1, visibleEnd = true)
}

private fun adjustedConstraints(
    constraints: Constraints,
    paddingValues: PaddingValues,
    density: Density
): Constraints {
    val horizontalPaddingPx = with(density) {
        paddingValues.calculateLeftPadding(LayoutDirection.Ltr).toPx() +
            paddingValues.calculateRightPadding(LayoutDirection.Ltr).toPx()
    }
    val verticalPaddingPx = with(density) {
        paddingValues.calculateTopPadding().toPx() +
            paddingValues.calculateBottomPadding().toPx()
    }
    val maxWidth = (constraints.maxWidth - horizontalPaddingPx).toInt().coerceAtLeast(0)
    val maxHeight = (constraints.maxHeight - verticalPaddingPx).toInt().coerceAtLeast(0)
    return Constraints(
        minWidth = 0,
        maxWidth = maxWidth,
        minHeight = 0,
        maxHeight = maxHeight
    )
}

@OptIn(ExperimentalFoundationApi::class)
private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.detectTapGesturesWithoutConsuming(
    viewConfiguration: androidx.compose.ui.platform.ViewConfiguration,
    onTap: (Offset, IntSize) -> Unit
) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        var isTap = true
        var tapPosition = down.position
        val slop = viewConfiguration.touchSlop
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            if (change.positionChanged()) {
                val distance = (change.position - down.position).getDistance()
                if (distance > slop) {
                    isTap = false
                }
            }
            if (change.changedToUp()) {
                tapPosition = change.position
                break
            }
        }
        if (isTap) {
            onTap(tapPosition, size)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
private fun handleHorizontalTap(
    offset: Offset,
    size: IntSize,
    showControls: Boolean,
    pagerState: androidx.compose.foundation.pager.PagerState,
    paginatedPages: List<PaginatedPage>,
    onPreviousChapter: () -> Unit,
    onNextChapter: () -> Unit,
    coroutineScope: kotlinx.coroutines.CoroutineScope,
    onToggleControls: (Boolean) -> Unit
) {
    if (showControls) {
        onToggleControls(false)
        return
    }

    val width = size.width.toFloat()
    when {
        offset.x < width / 3f -> {
            coroutineScope.launch {
                if (pagerState.currentPage > 0) {
                    pagerState.animateScrollToPage(pagerState.currentPage - 1)
                } else {
                    onPreviousChapter()
                }
            }
        }
        offset.x < width * 2f / 3f -> {
            onToggleControls(true)
        }
        else -> {
            coroutineScope.launch {
                if (pagerState.currentPage < paginatedPages.lastIndex) {
                    pagerState.animateScrollToPage(pagerState.currentPage + 1)
                } else {
                    onNextChapter()
                }
            }
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
    isPlaying: Boolean,
    onPreviousChapter: () -> Unit,
    onNextChapter: () -> Unit,
    onShowChapterList: () -> Unit,
    onPlayPause: () -> Unit,
    onStopListening: () -> Unit,
    onPreviousParagraph: () -> Unit,
    onNextParagraph: () -> Unit,
    onFontSettings: () -> Unit,
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
                    onClick = onFontSettings
                )
            }
        }
    }
}

@Composable
private fun FontSizeDialog(
    value: Float,
    onValueChange: (Float) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = "字体大小") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(text = "当前: ${value.toInt()}sp")
                Slider(
                    value = value,
                    onValueChange = onValueChange,
                    valueRange = 12f..28f,
                    steps = 7
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("完成")
            }
        }
    )
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
    preloadedChapters: Set<Int>,
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
                            MaterialTheme.customColors.gradientStart.copy(alpha = 0.25f)
                        } else if (preloadedChapters.contains(index)) {
                            MaterialTheme.customColors.success.copy(alpha = 0.12f)
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
