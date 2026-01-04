// ReadingScreen.kt - 阅读页面集成听书功能（段落高亮）
package com.readapp.ui.screens

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.graphicsLayer
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
import com.readapp.data.LocalCacheManager
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import com.readapp.data.ReadingMode
import com.readapp.data.DarkModeConfig
import com.readapp.ui.components.MangaNativeReader
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun ReadingScreen(
    book: Book,
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    currentChapterContent: String,
    isContentLoading: Boolean,
    readingFontSize: Float,
    readingHorizontalPadding: Float,
    errorMessage: String?,
    onClearError: () -> Unit,
    onChapterClick: (Int) -> Unit,
    onLoadChapterContent: (Int) -> Unit,
    onNavigateBack: () -> Unit,
    // TTS 相关状态
    isPlaying: Boolean = false,
    isPaused: Boolean = false,
    currentPlayingParagraph: Int = -1,
    currentParagraphStartOffset: Int = 0,
    playbackProgress: Float = 0f,
    preloadedParagraphs: Set<Int> = emptySet(),
    preloadedChapters: Set<Int> = emptySet(),
    showTtsControls: Boolean = false,
    onPlayPauseClick: () -> Unit = {},
    onStartListening: (Int, Int) -> Unit = { _, _ -> },
    onStopListening: () -> Unit = {},
    onPreviousParagraph: () -> Unit = {},
    onNextParagraph: () -> Unit = {},
    onReadingFontSizeChange: (Float) -> Unit = {},
    onReadingHorizontalPaddingChange: (Float) -> Unit = {},
    onHeaderClick: () -> Unit = {},
    onExit: () -> Unit = {},
    readingMode: ReadingMode = ReadingMode.Vertical,
    onReadingModeChange: (ReadingMode) -> Unit = {},
    lockPageOnTTS: Boolean = false,
    onLockPageOnTTSChange: (Boolean) -> Unit = {},
    pageTurningMode: com.readapp.data.PageTurningMode = com.readapp.data.PageTurningMode.Scroll,
    onPageTurningModeChange: (com.readapp.data.PageTurningMode) -> Unit = {},
    darkModeConfig: DarkModeConfig = DarkModeConfig.OFF,
    onDarkModeChange: (DarkModeConfig) -> Unit = {},
    firstVisibleParagraphIndex: Int = 0,
    onScrollUpdate: (Int) -> Unit = {},
    pendingScrollIndex: Int? = null,
    onScrollConsumed: () -> Unit = {},
    forceMangaProxy: Boolean = false,
    onForceMangaProxyChange: (Boolean) -> Unit = {},
    manualMangaUrls: Set<String> = emptySet(),
    serverUrl: String = "",
    modifier: Modifier = Modifier
) {
    var showControls by remember { mutableStateOf(false) }
    var showChapterList by remember { mutableStateOf(false) }
    var showFontDialog by remember { mutableStateOf(false) }
    var currentPageStartIndex by remember { mutableStateOf(0) }
    var currentPageStartOffset by remember { mutableStateOf(0) }
    var pausedPageStartIndex by remember { mutableStateOf<Int?>(null) }
    var pausedPageStartOffset by remember { mutableStateOf<Int?>(null) }
    var pendingJumpToLastPageTarget by remember { mutableStateOf<Int?>(null) }
    var lastHandledChapterIndex by remember { mutableStateOf(-1) }
    val scrollState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    val latestOnExit by rememberUpdatedState(onExit)
    var isAutoScrolling by remember { mutableStateOf(false) }
    var lastAutoScrollTarget by remember { mutableStateOf<Int?>(null) }
    var resolveCurrentPageStart by remember { mutableStateOf<(() -> Pair<Int, Int>?)?>(null) }
    var isExplicitlySwitchingChapter by remember { mutableStateOf(false) }

    val contentPadding = remember(readingHorizontalPadding) {
        PaddingValues(
            start = readingHorizontalPadding.dp,
            end = readingHorizontalPadding.dp,
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
    
    val displayContent = remember(currentChapterContent, currentChapterIndex, chapters) {
        if (currentChapterContent.isNotBlank()) {
            currentChapterContent
        } else {
            chapters.getOrNull(currentChapterIndex)?.content.orEmpty()
        }
    }

    val currentChapterUrl = remember(currentChapterIndex, chapters) {
        chapters.getOrNull(currentChapterIndex)?.url
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

    val isMangaMode = remember(paragraphs, book.type, manualMangaUrls) {
        if (manualMangaUrls.contains(book.bookUrl)) return@remember true
        val imageCount = paragraphs.count { it.contains("__IMG__") }
        book.type == 2 || (paragraphs.isNotEmpty() && imageCount.toFloat() / paragraphs.size > 0.1f)
    }

    // 监听滚动，上报可见进度
    LaunchedEffect(scrollState.firstVisibleItemIndex) {
        if (readingMode == ReadingMode.Vertical && !isMangaMode) {
            val index = (scrollState.firstVisibleItemIndex - 1).coerceAtLeast(0)
            onScrollUpdate(index)
        }
    }

    // 处理挂起的滚动请求 (垂直模式)
    LaunchedEffect(pendingScrollIndex, isMangaMode, readingMode) {
        if (readingMode == ReadingMode.Vertical && !isMangaMode && pendingScrollIndex != null) {
            scrollState.scrollToItem(pendingScrollIndex + 1)
            onScrollConsumed()
        }
    }

    // 当章节索引变化时，加载内容
    LaunchedEffect(currentChapterIndex, chapters.size) {
        if (chapters.isNotEmpty() && currentChapterIndex in chapters.indices) {
            onLoadChapterContent(currentChapterIndex)
            if (!isMangaMode && readingMode == ReadingMode.Vertical) {
                scrollState.scrollToItem(0)
            }
        }
    }
    
    // 当前播放段落变化时，自动滚动
    LaunchedEffect(currentPlayingParagraph) {
        if (currentPlayingParagraph >= 0 && currentPlayingParagraph < paragraphs.size) {
            coroutineScope.launch {
                if (!isMangaMode && readingMode == ReadingMode.Vertical) {
                    scrollState.animateScrollToItem(currentPlayingParagraph + 1)
                }
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
        if (isMangaMode) {
            MangaNativeReader(
                paragraphs = paragraphs,
                serverUrl = serverUrl,
                chapterUrl = currentChapterUrl,
                forceProxy = forceMangaProxy,
                pendingScrollIndex = pendingScrollIndex,
                onToggleControls = { showControls = !showControls },
                onScroll = { onScrollUpdate(it) },
                modifier = Modifier.fillMaxSize()
            )
            
            LaunchedEffect(pendingScrollIndex) {
                if (pendingScrollIndex != null) {
                    onScrollConsumed()
                }
            }
        } else if (readingMode == ReadingMode.Vertical) {
            LazyColumn(
                state = scrollState,
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() }
                    ) {
                        showControls = !showControls
                    },
                contentPadding = contentPadding
            ) {
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
                            modifier = Modifier.fillMaxWidth().padding(vertical = AppDimens.PaddingLarge),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            if (isContentLoading) {
                                CircularProgressIndicator()
                                Text(text = "正在加载章节内容...", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.customColors.textSecondary)
                            } else {
                                Text(text = displayContent.ifBlank { "暂无显示内容" }, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.customColors.textSecondary)
                            }
                        }
                    }
                } else {
                    itemsIndexed(
                        items = paragraphs,
                        key = { index, _ -> "${currentChapterIndex}_${index}" }
                    ) {
                        index, paragraph ->
                        ParagraphItem(
                            text = paragraph,
                            isPlaying = index == currentPlayingParagraph,
                            isPreloaded = preloadedParagraphs.contains(index),
                            fontSize = readingFontSize,
                            chapterUrl = currentChapterUrl,
                            serverUrl = serverUrl,
                            forceProxy = forceMangaProxy,
                            modifier = Modifier.fillMaxWidth().padding(bottom = AppDimens.PaddingMedium)
                        )
                    }
                }
            }
        } else { // Horizontal Pager 逻辑 (针对小说文本)
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val style = MaterialTheme.typography.bodyLarge.copy(
                    fontSize = readingFontSize.sp,
                    lineHeight = (readingFontSize * 1.8f).sp
                )
                val chapterTitle = chapters.getOrNull(currentChapterIndex)?.title.orEmpty()
                val headerText = if (chapterTitle.isNotBlank()) chapterTitle + "\n\n" else ""
                val headerFontSize = (readingFontSize + 6f).sp
                val lineHeightPx = with(LocalDensity.current) { style.lineHeight.toPx() }
                val pagePadding = contentPadding
                val density = LocalDensity.current
                val availableConstraints = remember(constraints, pagePadding, density) {
                    adjustedConstraints(constraints, pagePadding, density)
                }
                
                val paginatedPages = rememberPaginatedText(
                    paragraphs = paragraphs,
                    style = style,
                    constraints = availableConstraints,
                    lineHeightPx = lineHeightPx,
                    headerText = headerText,
                    headerFontSize = headerFontSize
                )
                
                val pagerState = rememberPagerState(
                    initialPage = 0,
                    pageCount = { paginatedPages.pages.size.coerceAtLeast(1) }
                )

                LaunchedEffect(pendingScrollIndex, paginatedPages) {
                    if (pendingScrollIndex != null && paginatedPages.pages.isNotEmpty()) {
                        val targetPage = paginatedPages.pages.indexOfFirst { it.startParagraphIndex >= pendingScrollIndex }
                            .coerceAtLeast(0)
                        pagerState.scrollToPage(targetPage)
                        onScrollConsumed()
                    }
                }

                val viewConfiguration = LocalViewConfiguration.current
                HorizontalPager(
                    state = pagerState,
                    userScrollEnabled = !(isPlaying && lockPageOnTTS),
                    modifier = Modifier
                        .fillMaxSize()
                        .pointerInput(showControls, paginatedPages, currentChapterIndex, isPlaying, lockPageOnTTS) {
                            detectTapGesturesWithoutConsuming(viewConfiguration) { offset, size ->
                                if (isPlaying && lockPageOnTTS) {
                                    val width = size.width.toFloat()
                                    if (offset.x in (width / 3f)..(width * 2f / 3f)) showControls = !showControls
                                    return@detectTapGesturesWithoutConsuming
                                }
                                handleHorizontalTap(
                                    offset = offset,
                                    size = size,
                                    showControls = showControls,
                                    pagerState = pagerState,
                                    paginatedPages = paginatedPages.pages,
                                    onPreviousChapter = {
                                        if (currentChapterIndex > 0) onChapterClick(currentChapterIndex - 1)
                                    },
                                    onNextChapter = {
                                        if (currentChapterIndex < chapters.size - 1) onChapterClick(currentChapterIndex + 1)
                                    },
                                    coroutineScope = coroutineScope,
                                    onToggleControls = { showControls = it }
                                )
                            }
                        }
                ) { page ->
                    val pageInfo = paginatedPages.getOrNull(page)
                    val pageText = pageInfo?.let { pi ->
                        remember(pi, currentPlayingParagraph, paginatedPages.fullText) {
                            val baseText = paginatedPages.fullText.subSequence(
                                pi.start.coerceAtLeast(0),
                                pi.end.coerceAtMost(paginatedPages.fullText.text.length)
                            )
                            if (currentPlayingParagraph == pi.startParagraphIndex) {
                                AnnotatedString.Builder(baseText).apply {
                                    addStyle(SpanStyle(background = Color.Blue.copy(alpha = 0.15f)), 0, baseText.length)
                                }.toAnnotatedString()
                            } else baseText
                        }
                    } ?: AnnotatedString("")
                    
                    Box(modifier = Modifier.fillMaxSize().padding(pagePadding)) {
                        SelectionContainer {
                            Text(text = pageText, style = style, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.fillMaxSize())
                        }
                    }
                }

                LaunchedEffect(pagerState.currentPage) {
                    if (paginatedPages.pages.isNotEmpty()) {
                        paginatedPages.getOrNull(pagerState.currentPage)?.let {
                            onScrollUpdate(it.startParagraphIndex)
                        }
                    }
                }
            }
        }
        
        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn() + slideInVertically(),
            exit = fadeOut() + slideOutVertically(),
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            TopControlBar(
                bookTitle = book.title,
                chapterTitle = if (currentChapterIndex < chapters.size) chapters[currentChapterIndex].title else "",
                onNavigateBack = onNavigateBack,
                onHeaderClick = onHeaderClick
            )
        }
        
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
                        if (readingMode == ReadingMode.Horizontal) pendingJumpToLastPageTarget = currentChapterIndex - 1
                        isExplicitlySwitchingChapter = true
                        onChapterClick(currentChapterIndex - 1)
                    }
                },
                onNextChapter = {
                    if (currentChapterIndex < chapters.size - 1) {
                        pendingJumpToLastPageTarget = null
                        isExplicitlySwitchingChapter = true
                        onChapterClick(currentChapterIndex + 1)
                    }
                },
                onShowChapterList = { showChapterList = true },
                onPlayPause = { onPlayPauseClick() },
                onStopListening = onStopListening,
                onPreviousParagraph = onPreviousParagraph,
                onNextParagraph = onNextParagraph,
                onFontSettings = { showFontDialog = true },
                canGoPrevious = currentChapterIndex > 0,
                canGoNext = currentChapterIndex < chapters.size - 1,
                showTtsControls = showTtsControls
            )
        }

        if (showChapterList) {
            ChapterListDialog(
                chapters = chapters,
                currentChapterIndex = currentChapterIndex,
                preloadedChapters = preloadedChapters,
                bookUrl = book.bookUrl ?: "",
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
                horizontalPadding = readingHorizontalPadding,
                onHorizontalPaddingChange = onReadingHorizontalPaddingChange,
                lockPageOnTTS = lockPageOnTTS,
                onLockPageOnTTSChange = onLockPageOnTTSChange,
                pageTurningMode = pageTurningMode,
                onPageTurningModeChange = onPageTurningModeChange,
                darkModeConfig = darkModeConfig,
                onDarkModeChange = onDarkModeChange,
                forceMangaProxy = forceMangaProxy,
                onForceMangaProxyChange = onForceMangaProxyChange,
                readingMode = readingMode,
                onReadingModeChange = onReadingModeChange,
                onDismiss = { showFontDialog = false }
            )
        }
    }
}

@Composable
private fun ZoomableImage(
    model: Any,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Fit
) {
    var scale by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val state = rememberTransformableState { zoomChange, offsetChange, _ ->
        scale = (scale * zoomChange).coerceIn(1f, 4f)
        if (scale > 1f) offset += offsetChange else offset = Offset.Zero
    }
    Box(
        modifier = modifier
            .clip(RectangleShape)
            .transformable(state = state)
            .pointerInput(Unit) {
                detectTapGestures(onDoubleTap = {
                    scale = if (scale > 1f) 1f else 2f
                    offset = Offset.Zero
                })
            }
    ) {
        AsyncImage(
            model = model,
            contentDescription = null,
            modifier = Modifier.fillMaxSize().graphicsLayer(scaleX = scale, scaleY = scale, translationX = offset.x, translationY = offset.y),
            contentScale = contentScale
        )
    }
}

@Composable
private fun ParagraphItem(
    text: String,
    isPlaying: Boolean,
    isPreloaded: Boolean,
    fontSize: Float,
    chapterUrl: String?,
    serverUrl: String,
    forceProxy: Boolean,
    modifier: Modifier = Modifier
) {
    val backgroundColor = when {
        isPlaying -> MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
        isPreloaded -> MaterialTheme.customColors.success.copy(alpha = 0.15f)
        else -> Color.Transparent
    }
    Surface(modifier = modifier, color = backgroundColor, shape = RoundedCornerShape(8.dp)) {
        val imgUrl = remember(text) {
            val pattern = """(?:__IMG__|<img[^>]+(?:src|data-src)=["']?)([^"'>\s\n]+)["']?""".toRegex()
            pattern.find(text)?.groupValues?.get(1)
        }
        if (imgUrl != null) {
            AsyncImage(
                model = imgUrl,
                contentDescription = null,
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                contentScale = ContentScale.FillWidth
            )
        } else {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = fontSize.sp),
                color = MaterialTheme.colorScheme.onSurface,
                lineHeight = (fontSize * 1.8f).sp,
                modifier = Modifier.padding(horizontal = if (isPlaying || isPreloaded) 12.dp else 0.dp, vertical = if (isPlaying || isPreloaded) 8.dp else 0.dp)
            )
        }
    }
}

@Composable
private fun rememberPaginatedText(
    paragraphs: List<String>,
    style: TextStyle,
    constraints: Constraints,
    lineHeightPx: Float,
    headerText: String,
    headerFontSize: TextUnit
): PaginationResult {
    val textMeasurer = rememberTextMeasurer()
    return remember(paragraphs, style, constraints, lineHeightPx, headerText, headerFontSize) {
        if (paragraphs.isEmpty() || constraints.maxWidth == 0 || constraints.maxHeight == 0) {
            return@remember PaginationResult(emptyList(), AnnotatedString(""))
        }
        val paragraphStartIndices = paragraphStartIndices(paragraphs, headerText.length)
        val fullText = fullContent(paragraphs, headerText, headerFontSize)
        val layout = textMeasurer.measure(text = fullText, style = style, constraints = Constraints(maxWidth = constraints.maxWidth))
        if (layout.lineCount == 0) return@remember PaginationResult(emptyList(), fullText)
        val pageHeight = constraints.maxHeight.toFloat()
        val pages = mutableListOf<PaginatedPage>()
        var startLine = 0
        while (startLine < layout.lineCount) {
            val pageTop = layout.getLineTop(startLine)
            var endLine = startLine
            while (endLine + 1 < layout.lineCount && layout.getLineBottom(endLine + 1) - pageTop <= pageHeight) {
                endLine++
            }
            val startOffset = layout.getLineStart(startLine)
            val endOffset = layout.getLineEnd(endLine, visibleEnd = true)
            val adjustedOffset = (startOffset - headerText.length).coerceAtLeast(0)
            val normalizedOffset = normalizePageOffset(fullText.text, adjustedOffset, headerText.length)
            val startParagraphIndex = paragraphIndexForOffset(normalizedOffset, paragraphStartIndices)
            val paragraphStart = paragraphStartIndices.getOrElse(startParagraphIndex) { 0 }
            pages.add(PaginatedPage(startOffset, endOffset, startParagraphIndex, (normalizedOffset - paragraphStart).coerceAtLeast(0)))
            startLine = endLine + 1
        }
        PaginationResult(pages, fullText)
    }
}

private data class PaginatedPage(val start: Int, val end: Int, val startParagraphIndex: Int, val startOffsetInParagraph: Int)
private data class PaginationResult(val pages: List<PaginatedPage>, val fullText: AnnotatedString) {
    val indices: IntRange get() = pages.indices
    fun isEmpty(): Boolean = pages.isEmpty()
    fun getOrNull(index: Int): PaginatedPage? = pages.getOrNull(index)
}

private fun fullContent(paragraphs: List<String>, headerText: String, headerFontSize: TextUnit): AnnotatedString {
    val body = paragraphs.joinToString(separator = "\n\n") { it.trim() }
    return AnnotatedString.Builder().apply {
        if (headerText.isNotBlank()) {
            pushStyle(SpanStyle(fontSize = headerFontSize, fontWeight = FontWeight.Bold))
            append(headerText)
            pop()
        }
        append(body)
    }.toAnnotatedString()
}

private fun paragraphStartIndices(paragraphs: List<String>, prefixLength: Int): List<Int> {
    val starts = mutableListOf<Int>()
    var currentIndex = prefixLength
    paragraphs.forEachIndexed {
        index, paragraph ->
        starts.add(currentIndex)
        currentIndex += paragraph.trim().length + if (index < paragraphs.lastIndex) 2 else 0
    }
    return starts
}

private fun paragraphIndexForOffset(offset: Int, starts: List<Int>): Int = starts.indexOfLast { it <= offset }.coerceAtLeast(0)

private fun normalizePageOffset(fullText: String, bodyOffset: Int, headerLength: Int): Int {
    if (bodyOffset <= 0) return 0
    var absoluteOffset = (bodyOffset + headerLength).coerceIn(0, fullText.length)
    while (absoluteOffset < fullText.length && (fullText[absoluteOffset] == '\n' || fullText[absoluteOffset] == '\r')) {
        absoluteOffset++
    }
    return (absoluteOffset - headerLength).coerceAtLeast(0)
}

private fun adjustedConstraints(constraints: Constraints, paddingValues: PaddingValues, density: Density): Constraints {
    val hPadding = with(density) { (paddingValues.calculateLeftPadding(LayoutDirection.Ltr) + paddingValues.calculateRightPadding(LayoutDirection.Ltr)).toPx() }
    val vPadding = with(density) { (paddingValues.calculateTopPadding() + paddingValues.calculateBottomPadding()).toPx() }
    return Constraints(maxWidth = (constraints.maxWidth - hPadding).toInt().coerceAtLeast(0), maxHeight = (constraints.maxHeight - vPadding).toInt().coerceAtLeast(0))
}

@OptIn(ExperimentalFoundationApi::class)
private suspend fun PointerInputScope.detectTapGesturesWithoutConsuming(viewConfiguration: androidx.compose.ui.platform.ViewConfiguration, onTap: (Offset, IntSize) -> Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        var isTap = true
        var tapPosition = down.position
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            if ((change.position - down.position).getDistance() > viewConfiguration.touchSlop) isTap = false
            if (change.changedToUp()) { tapPosition = change.position; break }
        }
        if (isTap) onTap(tapPosition, size)
    }
}

@OptIn(ExperimentalFoundationApi::class)
private fun handleHorizontalTap(offset: Offset, size: IntSize, showControls: Boolean, pagerState: androidx.compose.foundation.pager.PagerState, paginatedPages: List<PaginatedPage>, onPreviousChapter: () -> Unit, onNextChapter: () -> Unit, coroutineScope: kotlinx.coroutines.CoroutineScope, onToggleControls: (Boolean) -> Unit) {
    if (showControls) { onToggleControls(false); return }
    val width = size.width.toFloat()
    when {
        offset.x < width / 3f -> coroutineScope.launch { if (pagerState.currentPage > 0) pagerState.animateScrollToPage(pagerState.currentPage - 1) else onPreviousChapter() }
        offset.x < width * 2f / 3f -> onToggleControls(true)
        else -> coroutineScope.launch { if (pagerState.currentPage < paginatedPages.lastIndex) pagerState.animateScrollToPage(pagerState.currentPage + 1) else onNextChapter() }
    }
}

private val List<*>.lastIndex: Int get() = size - 1

@Composable
private fun TopControlBar(bookTitle: String, chapterTitle: String, onNavigateBack: () -> Unit, onHeaderClick: () -> Unit) {
    Surface(modifier = Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f), shadowElevation = 4.dp) {
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = AppDimens.PaddingMedium, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onNavigateBack) { Icon(Icons.Default.ArrowBack, "返回") }
            Column(modifier = Modifier.weight(1f).padding(horizontal = 8.dp).clickable(onClick = onHeaderClick)) {
                Text(text = bookTitle, style = MaterialTheme.typography.titleMedium, maxLines = 1)
                Text(text = chapterTitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.customColors.textSecondary, maxLines = 1)
            }
        }
    }
}

@Composable
private fun BottomControlBar(isPlaying: Boolean, onPreviousChapter: () -> Unit, onNextChapter: () -> Unit, onShowChapterList: () -> Unit, onPlayPause: () -> Unit, onStopListening: () -> Unit, onPreviousParagraph: () -> Unit, onNextParagraph: () -> Unit, onFontSettings: () -> Unit, canGoPrevious: Boolean, canGoNext: Boolean, showTtsControls: Boolean) {
    Surface(modifier = Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f), shadowElevation = 8.dp) {
        Column(modifier = Modifier.fillMaxWidth().padding(AppDimens.PaddingMedium)) {
            if (showTtsControls) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onPreviousParagraph) { Icon(Icons.Default.KeyboardArrowUp, "上一段") }
                    FloatingActionButton(onClick = onPlayPause, containerColor = MaterialTheme.customColors.gradientStart, modifier = Modifier.size(56.dp)) { Icon(imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = if (isPlaying) "暂停" else "播放", tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(28.dp)) }
                    IconButton(onClick = onNextParagraph) { Icon(Icons.Default.KeyboardArrowDown, "下一段") }
                    IconButton(onClick = onStopListening) { Icon(Icons.Default.Stop, "停止", tint = MaterialTheme.colorScheme.error) }
                }
                Spacer(modifier = Modifier.height(8.dp)); Divider(color = MaterialTheme.customColors.border); Spacer(modifier = Modifier.height(8.dp))
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                ControlButton(icon = Icons.Default.SkipPrevious, label = "上一章", onClick = onPreviousChapter, enabled = canGoPrevious)
                ControlButton(icon = Icons.Default.List, label = "目录", onClick = onShowChapterList)
                if (!showTtsControls) {
                    FloatingActionButton(onClick = onPlayPause, containerColor = MaterialTheme.customColors.gradientStart, elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 6.dp)) { Icon(Icons.Default.VolumeUp, "听书", tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(28.dp)) }
                }
                ControlButton(icon = Icons.Default.FormatSize, label = "字体", onClick = onFontSettings)
                ControlButton(icon = Icons.Default.SkipNext, label = "下一章", onClick = onNextChapter, enabled = canGoNext)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderOptionsDialog(fontSize: Float, onFontSizeChange: (Float) -> Unit, horizontalPadding: Float, onHorizontalPaddingChange: (Float) -> Unit, lockPageOnTTS: Boolean, onLockPageOnTTSChange: (Boolean) -> Unit, pageTurningMode: com.readapp.data.PageTurningMode, onPageTurningModeChange: (com.readapp.data.PageTurningMode) -> Unit, darkModeConfig: DarkModeConfig, onDarkModeChange: (DarkModeConfig) -> Unit, forceMangaProxy: Boolean, onForceMangaProxyChange: (Boolean) -> Unit, readingMode: ReadingMode, onReadingModeChange: (ReadingMode) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text("阅读选项") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("阅读模式", style = MaterialTheme.typography.labelMedium)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ReadingMode.values().forEach { mode ->
                        FilterChip(selected = readingMode == mode, onClick = { onReadingModeChange(mode) }, label = { Text(if (mode == ReadingMode.Vertical) "上下滚动" else "左右翻页") }, modifier = Modifier.weight(1f))
                    }
                }
            }
            Divider()
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("夜间模式", style = MaterialTheme.typography.labelMedium)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    DarkModeConfig.values().forEach { config ->
                        FilterChip(selected = darkModeConfig == config, onClick = { onDarkModeChange(config) }, label = { Text(when(config){ DarkModeConfig.ON->"开启"; DarkModeConfig.OFF->"关闭"; DarkModeConfig.AUTO->"系统"}) }, modifier = Modifier.weight(1f))
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clickable { onForceMangaProxyChange(!forceMangaProxy) }) {
                Column(modifier = Modifier.weight(1f)) { Text("强制服务器代理", style = MaterialTheme.typography.bodyLarge); Text("如果漫画图片无法加载，请开启此项", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline) }
                Switch(checked = forceMangaProxy, onCheckedChange = onForceMangaProxyChange)
            }
            Divider()
            Column { Text("字体大小: ${fontSize.toInt()}sp", style = MaterialTheme.typography.labelMedium); Slider(value = fontSize, onValueChange = onFontSizeChange, valueRange = 12f..30f) }
            Column { Text("页面边距: ${horizontalPadding.toInt()}dp", style = MaterialTheme.typography.labelMedium); Slider(value = horizontalPadding, onValueChange = onHorizontalPaddingChange, valueRange = 0f..50f) }
            Divider()
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clickable { onLockPageOnTTSChange(!lockPageOnTTS) }) { Checkbox(checked = lockPageOnTTS, onCheckedChange = onLockPageOnTTSChange); Text("播放时锁定翻页", modifier = Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyMedium) }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("完成") } })
}

@Composable
private fun FontSizeDialog(value: Float, onValueChange: (Float) -> Unit, horizontalPadding: Float, onHorizontalPaddingChange: (Float) -> Unit, lockPageOnTTS: Boolean, onLockPageOnTTSChange: (Boolean) -> Unit, pageTurningMode: com.readapp.data.PageTurningMode, onPageTurningModeChange: (com.readapp.data.PageTurningMode) -> Unit, darkModeConfig: DarkModeConfig, onDarkModeChange: (DarkModeConfig) -> Unit, forceMangaProxy: Boolean, onForceMangaProxyChange: (Boolean) -> Unit, readingMode: ReadingMode, onReadingModeChange: (ReadingMode) -> Unit, onDismiss: () -> Unit) {
    ReaderOptionsDialog(fontSize = value, onFontSizeChange = onValueChange, horizontalPadding = horizontalPadding, onHorizontalPaddingChange = onHorizontalPaddingChange, lockPageOnTTS = lockPageOnTTS, onLockPageOnTTSChange = onLockPageOnTTSChange, pageTurningMode = pageTurningMode, onPageTurningModeChange = onPageTurningModeChange, darkModeConfig = darkModeConfig, onDarkModeChange = onDarkModeChange, forceMangaProxy = forceMangaProxy, onForceMangaProxyChange = onForceMangaProxyChange, readingMode = readingMode, onReadingModeChange = onReadingModeChange, onDismiss = onDismiss)
}

@Composable
private fun ControlButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit, enabled: Boolean = true) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        IconButton(onClick = onClick, enabled = enabled) { Icon(imageVector = icon, contentDescription = label, tint = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.customColors.textSecondary.copy(alpha = 0.3f), modifier = Modifier.size(24.dp)) }
        Text(text = label, style = MaterialTheme.typography.labelSmall, color = if (enabled) MaterialTheme.customColors.textSecondary else MaterialTheme.customColors.textSecondary.copy(alpha = 0.3f))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChapterListDialog(chapters: List<Chapter>, currentChapterIndex: Int, preloadedChapters: Set<Int>, bookUrl: String, onChapterClick: (Int) -> Unit, onDismiss: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val localCache = remember { LocalCacheManager(context) }
    var currentGroupIndex by remember(chapters.size) { mutableStateOf(currentChapterIndex / 50) }
    val groupCount = (chapters.size + 49) / 50
    AlertDialog(onDismissRequest = onDismiss, title = { Text("章节列表 (${chapters.size})", style = MaterialTheme.typography.titleLarge) }, text = {
        Column {
            if (groupCount > 1) {
                androidx.compose.foundation.lazy.LazyRow(modifier = Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(groupCount) { 
                        val start = it * 50 + 1; val end = minOf((it + 1) * 50, chapters.size)
                        FilterChip(selected = currentGroupIndex == it, onClick = { currentGroupIndex = it }, label = { Text("$start-$end") })
                    }
                }
            }
            LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f, fill = false)) {
                val start = currentGroupIndex * 50; val end = minOf((currentGroupIndex + 1) * 50, chapters.size)
                itemsIndexed(chapters.subList(start, end)) { relativeIndex, chapter ->
                    val index = start + relativeIndex
                    val isCurrent = index == currentChapterIndex
                    Surface(onClick = { onChapterClick(index) }, color = if (isCurrent) MaterialTheme.customColors.gradientStart.copy(alpha = 0.25f) else if (preloadedChapters.contains(index)) MaterialTheme.customColors.success.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) {
                        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp, horizontal = 16.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text(text = chapter.title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, color = if (isCurrent) MaterialTheme.customColors.gradientStart else MaterialTheme.colorScheme.onSurface)
                            if (isCurrent) Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.customColors.gradientStart) { Text("当前", modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimary) }
                        }
                    }
                    if (index < chapters.size - 1) Divider(color = MaterialTheme.customColors.border)
                }
            }
        }
    }, confirmButton = {}, dismissButton = { TextButton(onClick = onDismiss) { Text("关闭") } }, shape = RoundedCornerShape(AppDimens.CornerRadiusLarge))
}
