// ReadingScreen.kt - 闃呰椤甸潰闆嗘垚鍚功鍔熻兘锛堟钀介珮浜級
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

@OptIn(ExperimentalFoundationApi::class)
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
    // TTS 鐩稿叧鐘舵€?
    isPlaying: Boolean = false,
    isPaused: Boolean = false,
    currentPlayingParagraph: Int = -1,  // 当前播放的段落索引
    currentParagraphStartOffset: Int = 0,
    playbackProgress: Float = 0f,
    preloadedParagraphs: Set<Int> = emptySet(),  // 宸查杞界殑娈佃惤绱㈠紩
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
    readingMode: com.readapp.data.ReadingMode = com.readapp.data.ReadingMode.Vertical,
    onReadingModeChange: (com.readapp.data.ReadingMode) -> Unit = {},
    lockPageOnTTS: Boolean = false,
    onLockPageOnTTSChange: (Boolean) -> Unit = {},
    pageTurningMode: com.readapp.data.PageTurningMode = com.readapp.data.PageTurningMode.Scroll,
    onPageTurningModeChange: (com.readapp.data.PageTurningMode) -> Unit = {},
    darkModeConfig: com.readapp.data.DarkModeConfig = com.readapp.data.DarkModeConfig.OFF,
    onDarkModeChange: (com.readapp.data.DarkModeConfig) -> Unit = {},
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
    
    // 鍒嗗壊娈佃惤
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

    // 褰撶珷鑺傜储寮曞彉鍖TargetFramework) { // 鏇存柊鍐呭
        if (readingMode == com.readapp.data.ReadingMode.Vertical && displayContent.isNotEmpty() && isExplicitlySwitchingChapter) {
            kotlinx.coroutines.delay(200) 
            scrollState.scrollToItem(0)
            isExplicitlySwitchingChapter = false // 消费掉标记
        }
    }

    // 褰撳墠鎾斁娈佃惤鍙樺寲鏃讹紝鑷姩婊氬姩鍒拌娈佃惤
    LaunchedEffect(currentPlayingParagraph) {
        if (currentPlayingParagraph >= 0 && currentPlayingParagraph < paragraphs.size) {
            coroutineScope.launch {
                // +1 鏄洜涓虹涓€涓?item 鏄珷鑺傛爣棰?
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
        // 主要内容区域
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
            
            // 消费滚动标记
            LaunchedEffect(pendingScrollIndex) {
                if (pendingScrollIndex != null) {
                    onScrollConsumed()
                }
            }
        } else if (readingMode == com.readapp.data.ReadingMode.Vertical) {
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
                                    text = displayContent.ifBlank { "暂无显示内容" },
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.customColors.textSecondary,
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    }
                } else {
                    // 章节内容（分段显示，带高亮）
                    itemsIndexed(
                        items = paragraphs,
                        key = { index, _ -> "${currentChapterIndex}_${index}" }
                    ) { index, paragraph ->
                        ParagraphItem(
                            text = paragraph,
                            isPlaying = index == currentPlayingParagraph,
                            isPreloaded = preloadedParagraphs.contains(index),
                            fontSize = readingFontSize,
                            chapterUrl = currentChapterUrl,
                            serverUrl = serverUrl,
                            forceProxy = forceMangaProxy,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(bottom = AppDimens.PaddingMedium)
                        )
                    }
                }
            }
        } else { // Horizontal Pager 逻辑 (针对小说文本)
            BoxWithConstraints(
                modifier = Modifier.fillMaxSize()
            ) {
                val style = MaterialTheme.typography.bodyLarge.copy(
                    fontSize = readingFontSize.sp,
                    lineHeight = (readingFontSize * 1.8f).sp
                )
                val chapterTitle = chapters.getOrNull(currentChapterIndex)?.title.orEmpty()
                val headerText = if (chapterTitle.isNotBlank()) {
                    chapterTitle + "\n\n"
                } else {
                    ""
                }
                val headerFontSize = (readingFontSize + 6f).sp
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
                    lineHeightPx = lineHeightPx,
                    headerText = headerText,
                    headerFontSize = headerFontSize
                )
                
                val pagerState = rememberPagerState(
                    initialPage = 0,
                    pageCount = { paginatedPages.pages.size.coerceAtLeast(1) }
                )

                // 处理挂起的滚动请求 (水平模式)
                LaunchedEffect(pendingScrollIndex, paginatedPages) {
                    if (pendingScrollIndex != null && paginatedPages.pages.isNotEmpty()) {
                        val targetPage = paginatedPages.pages.indexOfFirst { it.startParagraphIndex >= pendingScrollIndex }
                            .coerceAtLeast(0)
                        pagerState.scrollToPage(targetPage)
                        onScrollConsumed()
                    }
                }

                HorizontalPager(
                    state = pagerState,
                    userScrollEnabled = !(isPlaying && lockPageOnTTS),
                    modifier = Modifier
                        .fillMaxSize()
                        .pointerInput(showControls, paginatedPages, currentChapterIndex, isPlaying, lockPageOnTTS) { // 移除不必要的参数
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
                        remember(pi, currentPlayingParagraph, paginatedPages.fullText) { // 移除不必要的参数
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

                // 上报翻页后的进度
                LaunchedEffect(pagerState.currentPage) {
                    if (paginatedPages.pages.isNotEmpty()) {
                        paginatedPages.getOrNull(pagerState.currentPage)?.let {
                            onScrollUpdate(it.startParagraphIndex)
                        }
                    }
                }
            }
        }
        
        // 椤堕儴鎺у埗鏍忥紙鍔ㄧ敾鏄剧ず/闅愯棌锛?
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
                onNavigateBack = onNavigateBack,
                onHeaderClick = onHeaderClick
            )
        }
        
        // 搴曢儴鎺у埗鏍忥紙鍔ㄧ敾鏄剧ず/闅愯棌锛?
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
                            pendingJumpToLastPageTarget = currentChapterIndex - 1
                        }
                        isExplicitlySwitchingChapter = true // 标记开始切章动作
                        onChapterClick(currentChapterIndex - 1)
                    }
                },
                onNextChapter = {
                    if (currentChapterIndex < chapters.size - 1) {
                        pendingJumpToLastPageTarget = null
                        isExplicitlySwitchingChapter = true // 标记开始切章动作
                        onChapterClick(currentChapterIndex + 1)
                    }
                },
                onShowChapterList = {
                    showChapterList = true
                },
                onPlayPause = {
                    if (isPlaying) {
                        val pageStart = if (readingMode == ReadingMode.Horizontal) {
                            resolveCurrentPageStart?.invoke()?.first ?: currentPageStartIndex
                        } else {
                            (scrollState.firstVisibleItemIndex - 1).coerceAtLeast(0)
                        }
                        val pageStartOffset = if (readingMode == ReadingMode.Horizontal) {
                            resolveCurrentPageStart?.invoke()?.second ?: currentPageStartOffset
                        } else {
                            0
                        }
                        pausedPageStartIndex = pageStart
                        pausedPageStartOffset = pageStartOffset
                        onPlayPauseClick()
                    } else if (isPaused) {
                        val pageStart = if (readingMode == ReadingMode.Horizontal) {
                            resolveCurrentPageStart?.invoke()?.first ?: currentPageStartIndex
                        } else {
                            (scrollState.firstVisibleItemIndex - 1).coerceAtLeast(0)
                        }
                        val pageStartOffset = if (readingMode == ReadingMode.Horizontal) {
                            resolveCurrentPageStart?.invoke()?.second ?: currentPageStartOffset
                        } else {
                            0
                        }
                        if (pausedPageStartIndex == pageStart && pausedPageStartOffset == pageStartOffset) {
                            onPlayPauseClick()
                        } else {
                            onStartListening(pageStart, pageStartOffset)
                        }
                    } else {
                        val pageStart = if (readingMode == ReadingMode.Horizontal) {
                            resolveCurrentPageStart?.invoke()?.first ?: currentPageStartIndex
                        } else {
                            (scrollState.firstVisibleItemIndex - 1).coerceAtLeast(0)
                        }
                        val pageStartOffset = if (readingMode == ReadingMode.Horizontal) {
                            resolveCurrentPageStart?.invoke()?.second ?: currentPageStartOffset
                        } else {
                            0
                        }
                        onStartListening(pageStart, pageStartOffset)
                    }
                },
                onStopListening = onStopListening,
                onPreviousParagraph = onPreviousParagraph,
                onNextParagraph = onNextParagraph,
                onFontSettings = { showFontDialog = true },
                canGoPrevious = currentChapterIndex > 0,
                canGoNext = currentChapterIndex < chapters.size - 1,
                showTtsControls = showTtsControls  // 浠呭湪瀹為檯鎾斁/淇濇寔鎾斁鏃舵樉绀?TTS 鎺у埗
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

        // 绔犺妭鍒楄〃寮圭獥
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

/**
 * 娈佃惤椤圭粍浠?- 甯﹂珮浜晥鏋?
 */
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
        // 只有在放大时才允许偏移
        if (scale > 1f) {
            offset += offsetChange
        } else {
            offset = Offset.Zero
        }
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
        coil.compose.AsyncImage(
            model = model,
            contentDescription = null,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer(
                    scaleX = scale,
                    scaleY = scale,
                    translationX = offset.x,
                    translationY = offset.y
                ),
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
    // ... (backgroundColor logic unchanged)
    val backgroundColor = when {
        isPlaying -> MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
        isPreloaded -> MaterialTheme.customColors.success.copy(alpha = 0.15f)
        else -> Color.Transparent
    }
    
    Surface(
        modifier = modifier,
        color = backgroundColor,
        shape = RoundedCornerShape(8.dp)
    ) {
        val imgUrl = remember(text) {
            val pattern = """(?:__IMG__|<img[^>]+(?:src|data-src)=["']?)(["'>\s\n]+)["']?"""\.toRegex()
            pattern.find(text)?.groupValues?.get(1)
        }

        if (imgUrl != null) {
            val context = androidx.compose.ui.platform.LocalContext.current
            val finalUrl = remember(imgUrl, serverUrl) {
                if (imgUrl.startsWith("http")) imgUrl
                else {
                    val base = serverUrl.replace("/api/5", "")
                    if (imgUrl.startsWith("/")) "$base$imgUrl" else "$base/$imgUrl"
                }
            }
            
            val proxyUrl = remember(finalUrl, serverUrl) {
                android.net.Uri.parse(serverUrl).buildUpon()
                    .path("api/5/proxypng")
                    .appendQueryParameter("url", finalUrl)
                    .appendQueryParameter("accessToken", "")
                    .build().toString()
            }

            val finalReferer = remember(chapterUrl) {
                chapterUrl?.replace("http://", "https://")?.let {
                    if (it.contains("kuaikanmanhua.com") && !it.endsWith("/")) "$it/" else it
                }
            }

            var currentRequestUrl by remember(finalUrl, forceProxy) { 
                mutableStateOf(if (forceProxy) proxyUrl else finalUrl) 
            }
            var hasTriedProxy by remember(finalUrl, forceProxy) { 
                mutableStateOf(forceProxy) 
            }

            val imageRequest = coil.request.ImageRequest.Builder(context)
                .data(currentRequestUrl)
                .addHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36")
                .apply { if (finalReferer != null) addHeader("Referer", finalReferer) }
                .listener(onError = { _, _ -> 
                    if (!hasTriedProxy && proxyUrl != null) {
                        currentRequestUrl = proxyUrl
                        hasTriedProxy = true
                    }
                })
                .crossfade(true)
                .build()

            coil.compose.AsyncImage(
                model = imageRequest,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                contentScale = ContentScale.FillWidth
            )
        } else {
            // ... (text rendering unchanged)
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
        val layout = textMeasurer.measure(
            text = fullText,
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
            val adjustedOffset = (startOffset - headerText.length).coerceAtLeast(0)
            val normalizedOffset = normalizePageOffset(fullText.text, adjustedOffset, headerText.length)
            val startParagraphIndex = paragraphIndexForOffset(normalizedOffset, paragraphStartIndices)
            val paragraphStart = paragraphStartIndices.getOrElse(startParagraphIndex) { 0 }
            val startOffsetInParagraph = (normalizedOffset - paragraphStart).coerceAtLeast(0)
            pages.add(
                PaginatedPage(
                    start = startOffset,
                    end = endOffset,
                    startParagraphIndex = startParagraphIndex,
                    startOffsetInParagraph = startOffsetInParagraph
                )
            )
            startLine = endLine + 1
        }
        PaginationResult(pages, fullText)
    }
}

private data class PaginatedPage(
    val start: Int,
    val end: Int,
    val startParagraphIndex: Int,
    val startOffsetInParagraph: Int
)

private data class PaginationResult(
    val pages: List<PaginatedPage>,
    val fullText: AnnotatedString
) {
    val indices: IntRange
        get() = pages.indices

    val lastIndex: Int
        get() = pages.lastIndex

    fun isEmpty(): Boolean = pages.isEmpty()

    fun getOrNull(index: Int): PaginatedPage? = pages.getOrNull(index)

    operator fun get(index: Int): PaginatedPage = pages[index]
}

private fun fullContent(paragraphs: List<String>, headerText: String, headerFontSize: TextUnit): AnnotatedString {
    val body = paragraphs.joinToString(separator = "\n\n") { it.trim() }
    val builder = AnnotatedString.Builder()
    if (headerText.isNotBlank()) {
        builder.pushStyle(SpanStyle(fontSize = headerFontSize, fontWeight = FontWeight.Bold))
        builder.append(headerText)
        builder.pop()
    }
    builder.append(body)
    return builder.toAnnotatedString()
}

private fun paragraphStartIndices(paragraphs: List<String>, prefixLength: Int): List<Int> {
    val starts = mutableListOf<Int>()
    var currentIndex = prefixLength
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

private fun normalizePageOffset(fullText: String, bodyOffset: Int, headerLength: Int): Int {
    if (bodyOffset <= 0) return 0
    val absoluteStart = (bodyOffset + headerLength).coerceIn(0, fullText.length)
    var absoluteOffset = absoluteStart
    while (absoluteOffset < fullText.length) {
        val ch = fullText[absoluteOffset]
        if (ch != '\n' && ch != '\r') {
            break
        }
        absoluteOffset++
    }
    return (absoluteOffset - headerLength).coerceAtLeast(0)
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


@Composable
private fun TopControlBar(
    bookTitle: String,
    chapterTitle: String,
    onNavigateBack: () -> Unit,
    onHeaderClick: () -> Unit
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
                    contentDescription = "杩斿洖",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
            
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp)
                    .clickable(onClick = onHeaderClick)
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
            // TTS 娈佃惤鎺у埗锛堟挱鏀炬椂鏄剧ず锛?
            if (showTtsControls) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // 涓婁竴娈?
                    IconButton(onClick = onPreviousParagraph) {
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowUp,
                            contentDescription = "\u4e0a\u4e00\u6bb5",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                    
                    // 鎾斁/鏆傚仠
                    FloatingActionButton(
                        onClick = onPlayPause,
                        containerColor = MaterialTheme.customColors.gradientStart,
                        modifier = Modifier.size(56.dp)
                    ) {
                        Icon(
                            imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = if (isPlaying) "\u6688\u505c" else "\u64ad\u653e",
                            tint = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.size(28.dp)
                        )
                    }
                    
                    // 涓嬩竴娈?
                    IconButton(onClick = onNextParagraph) {
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowDown,
                            contentDescription = "\u4e0b\u4e00\u6bb5",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                    
                    // 鍋滄鍚功
                    IconButton(onClick = onStopListening) {
                        Icon(
                            imageVector = Icons.Default.Stop,
                            contentDescription = "\u505c\u6b62",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
                
                Spacer(modifier = Modifier.height(8.dp))
                Divider(color = MaterialTheme.customColors.border)
                Spacer(modifier = Modifier.height(8.dp))
            }
            
            // 鍩虹闃呰鎺у埗
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // 涓婁竴绔?
                ControlButton(
                    icon = Icons.Default.SkipPrevious,
                    label = "\u4e0a\u4e00\u7ae0",
                    onClick = onPreviousChapter,
                    enabled = canGoPrevious
                )
                
                // 鐩綍
                ControlButton(
                    icon = Icons.Default.List,
                    label = "\u76ee\u5f55",
                    onClick = onShowChapterList
                )
                
                // 鍚功鎸夐挳锛堟湭鎾斁鏃舵樉绀猴級
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
                            contentDescription = "\u542c\u4e66",
                            tint = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.size(28.dp)
                        )
                    }
                }
                
                // 涓嬩竴绔?
                ControlButton(
                    icon = Icons.Default.FormatSize,
                    label = "\u5b57\u4f53",
                    onClick = onFontSettings
                )
                
                // 瀛椾綋澶у皬锛圱ODO锛?
                ControlButton(
                    icon = Icons.Default.SkipNext,
                    label = "\u4e0b\u4e00\u7ae0",
                    onClick = onNextChapter,
                    enabled = canGoNext
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderOptionsDialog(
    fontSize: Float,
    onFontSizeChange: (Float) -> Unit,
    horizontalPadding: Float,
    onHorizontalPaddingChange: (Float) -> Unit,
    lockPageOnTTS: Boolean,
    onLockPageOnTTSChange: (Boolean) -> Unit,
    pageTurningMode: com.readapp.data.PageTurningMode,
    onPageTurningModeChange: (com.readapp.data.PageTurningMode) -> Unit,
    darkModeConfig: com.readapp.data.DarkModeConfig,
    onDarkModeChange: (com.readapp.data.DarkModeConfig) -> Unit,
    forceMangaProxy: Boolean,
    onForceMangaProxyChange: (Boolean) -> Unit,
    readingMode: com.readapp.data.ReadingMode,
    onReadingModeChange: (com.readapp.data.ReadingMode) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = "阅读选项") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                // 阅读模式
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("阅读模式", style = MaterialTheme.typography.labelMedium)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        com.readapp.data.ReadingMode.values().forEach { mode ->
                            val isSelected = readingMode == mode
                            val label = when(mode) {
                                com.readapp.data.ReadingMode.Vertical -> "上下滚动"
                                com.readapp.data.ReadingMode.Horizontal -> "左右翻页"
                            }
                            FilterChip(
                                selected = isSelected,
                                onClick = { onReadingModeChange(mode) },
                                label = { Text(label) },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }

                Divider()

                // 夜间模式 (三状态)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("夜间模式", style = MaterialTheme.typography.labelMedium)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        com.readapp.data.DarkModeConfig.values().forEach { config ->
                            val isSelected = darkModeConfig == config
                            val label = when(config) {
                                com.readapp.data.DarkModeConfig.ON -> "开启"
                                com.readapp.data.DarkModeConfig.OFF -> "关闭"
                                com.readapp.data.DarkModeConfig.AUTO -> "跟随系统"
                            }
                            FilterChip(
                                selected = isSelected,
                                onClick = { onDarkModeChange(config) },
                                label = { Text(label) },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }

                // 强制代理
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().clickable { onForceMangaProxyChange(!forceMangaProxy) }
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("强制服务器代理", style = MaterialTheme.typography.bodyLarge)
                        Text("如果漫画图片无法加载，请开启此项", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                    }
                    Switch(checked = forceMangaProxy, onCheckedChange = onForceMangaProxyChange)
                }

                Divider()

                // 字体大小
                Column {
                    Text(text = "字体大小: ${fontSize.toInt()}sp", style = MaterialTheme.typography.labelMedium)
                    Slider(
                        value = fontSize,
                        onValueChange = onFontSizeChange,
                        valueRange = 12f..30f
                    )
                }

                // 左右间距
                Column {
                    Text(text = "页面边距: ${horizontalPadding.toInt()}dp", style = MaterialTheme.typography.labelMedium)
                    Slider(
                        value = horizontalPadding,
                        onValueChange = onHorizontalPaddingChange,
                        valueRange = 0f..50f
                    )
                }

                Divider()

                // 翻页效果
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("翻页动画 (仅限左右翻页)", style = MaterialTheme.typography.labelMedium)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        com.readapp.data.PageTurningMode.values().forEach { mode ->
                            val isSelected = pageTurningMode == mode
                            val label = when(mode) {
                                com.readapp.data.PageTurningMode.Scroll -> "平滑滑动"
                                com.readapp.data.PageTurningMode.Simulation -> "仿真翻页"
                            }
                            FilterChip(
                                selected = isSelected,
                                onClick = { onPageTurningModeChange(mode) },
                                label = { Text(label) },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().clickable { onLockPageOnTTSChange(!lockPageOnTTS) }
                ) {
                    Checkbox(checked = lockPageOnTTS, onCheckedChange = onLockPageOnTTSChange)
                    Text("播放时锁定翻页", modifier = Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyMedium)
                }
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
private fun FontSizeDialog(
    value: Float,
    onValueChange: (Float) -> Unit,
    horizontalPadding: Float,
    onHorizontalPaddingChange: (Float) -> Unit,
    lockPageOnTTS: Boolean,
    onLockPageOnTTSChange: (Boolean) -> Unit,
    pageTurningMode: com.readapp.data.PageTurningMode,
    onPageTurningModeChange: (com.readapp.data.PageTurningMode) -> Unit,
    darkModeConfig: com.readapp.data.DarkModeConfig,
    onDarkModeChange: (com.readapp.data.DarkModeConfig) -> Unit,
    forceMangaProxy: Boolean,
    onForceMangaProxyChange: (Boolean) -> Unit,
    readingMode: com.readapp.data.ReadingMode,
    onReadingModeChange: (com.readapp.data.ReadingMode) -> Unit,
    onDismiss: () -> Unit
) {
    ReaderOptionsDialog(
        fontSize = value,
        onFontSizeChange = onValueChange,
        horizontalPadding = horizontalPadding,
        onHorizontalPaddingChange = onHorizontalPaddingChange,
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
        onDismiss = onDismiss
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChapterListDialog(
    chapters: List<Chapter>,
    currentChapterIndex: Int,
    preloadedChapters: Set<Int>,
    bookUrl: String,
    onChapterClick: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val localCache = remember { com.readapp.data.LocalCacheManager(context) }
    var currentGroupIndex by remember(chapters.size) {
        mutableStateOf(currentChapterIndex / 50)
    }
    val groupCount = (chapters.size + 49) / 50
    
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = "章节列表 (${chapters.size})",
                style = MaterialTheme.typography.titleLarge
            )
        },
        text = {
            Column {
                if (groupCount > 1) {
                    androidx.compose.foundation.lazy.LazyRow(
                        modifier = Modifier.padding(bottom = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(groupCount) {
                            val start = it * 50 + 1
                            val end = minOf((it + 1) * 50, chapters.size)
                            FilterChip(
                                selected = currentGroupIndex == it,
                                onClick = { currentGroupIndex = it },
                                label = { Text("$start-$end") }
                            )
                        }
                    }
                }
                
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false)
                ) {
                    val start = currentGroupIndex * 50
                    val end = minOf((currentGroupIndex + 1) * 50, chapters.size)
                    val visibleChapters = chapters.subList(start, end)
                    
                    itemsIndexed(visibleChapters) { relativeIndex, chapter ->
                        val index = start + relativeIndex
                        val isCurrentChapter = index == currentChapterIndex
                        val isCached = remember(bookUrl, index) { localCache.isChapterCached(bookUrl, index) }
                        
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
                                
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    if (isCached) {
                                        Icon(
                                            imageVector = Icons.Default.CheckCircle,
                                            contentDescription = "已缓存",
                                            tint = MaterialTheme.customColors.success,
                                            modifier = Modifier.size(16.dp).padding(end = 4.dp)
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
                        }
                        
                        if (index < chapters.size - 1) {
                            Divider(color = MaterialTheme.customColors.border)
                        }
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