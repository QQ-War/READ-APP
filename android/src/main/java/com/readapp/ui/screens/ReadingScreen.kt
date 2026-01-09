// ReadingScreen.kt - 阅读页面集成听书功能（段落高亮与翻页优化）
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.TextUnit
import com.readapp.data.LocalCacheManager
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors
import com.readapp.data.normalizeApiBaseUrl
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import com.readapp.data.ReadingMode
import com.readapp.data.DarkModeConfig
import com.readapp.data.model.Chapter
import com.readapp.ui.components.EdgeHint
import com.readapp.ui.components.MangaNativeReader
import com.readapp.ui.state.ReaderUiState
import com.readapp.ui.reader.SectionOffsets
import com.readapp.ui.reader.ChapterTransitionPolicy
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration

private enum class ChapterNavIntent {
    NONE, FIRST, LAST
}

private data class ChapterSection(
    val chapterIndex: Int,
    val title: String,
    val paragraphs: List<String>,
    val isCurrent: Boolean
)

private sealed class ReadingListItem {
    data class ChapterTitle(val chapterIndex: Int, val title: String, val isCurrent: Boolean) : ReadingListItem()
    data class ParagraphItem(val chapterIndex: Int, val paragraphIndex: Int, val text: String, val isCurrent: Boolean) : ReadingListItem()
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun ReadingScreen(
    readerState: ReaderUiState,
    onClearError: () -> Unit,
    onChapterClick: (Int) -> Unit,
    onLoadChapterContent: (Int) -> Unit,
    onNavigateBack: () -> Unit,
    // TTS 状态
    isPlaying: Boolean = false,
    isPaused: Boolean = false,
    currentPlayingParagraph: Int = -1,
    currentParagraphStartOffset: Int = 0,
    playbackProgress: Float = 0f,
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
    onReadingModeChange: (ReadingMode) -> Unit = {},
    onInfiniteScrollEnabledChange: (Boolean) -> Unit = {},
    onLockPageOnTTSChange: (Boolean) -> Unit = {},
    onPageTurningModeChange: (com.readapp.data.PageTurningMode) -> Unit = {},
    onDarkModeChange: (DarkModeConfig) -> Unit = {},
    onScrollUpdate: (Int) -> Unit = {},
    onScrollConsumed: () -> Unit = {},
    onForceMangaProxyChange: (Boolean) -> Unit = {},
    onInfiniteScrollSwitch: (Int, Int) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier
) {
    val book = readerState.book ?: return
    val chapters = readerState.chapters
    val currentChapterIndex = readerState.currentChapterIndex
    val currentChapterContent = readerState.currentChapterContent
    val isContentLoading = readerState.isContentLoading
    val readingFontSize = readerState.readingFontSize
    val readingHorizontalPadding = readerState.readingHorizontalPadding
    val errorMessage = readerState.errorMessage
    val readingMode = readerState.readingMode
    val isInfiniteScrollEnabled = readerState.infiniteScrollEnabled
    val prevChapterContent = readerState.prevChapterContent
    val nextChapterContent = readerState.nextChapterContent
    val lockPageOnTTS = readerState.lockPageOnTTS
    val pageTurningMode = readerState.pageTurningMode
    val darkModeConfig = readerState.darkModeConfig
    val pendingScrollIndex = readerState.pendingScrollIndex
    val forceMangaProxy = readerState.forceMangaProxy
    val manualMangaUrls = readerState.manualMangaUrls
    val serverUrl = readerState.serverUrl
    val serverEndpoint = remember(serverUrl, readerState.apiBackend) {
        normalizeApiBaseUrl(serverUrl, readerState.apiBackend)
    }
    val preloadedParagraphs = readerState.preloadedParagraphs
    val preloadedChapters = readerState.preloadedChapters
    var showControls by remember { mutableStateOf(false) }
    var showChapterList by remember { mutableStateOf(false) }
    var showFontDialog by remember { mutableStateOf(false) }
    
    // 状态机记录翻页意图
    var navIntent by remember { mutableStateOf(ChapterNavIntent.NONE) }
    var lastChapterIndex by remember { mutableStateOf(-1) }
    var mangaNavIntent by remember { mutableStateOf(ChapterNavIntent.NONE) }
    var mangaPendingScrollIndex by remember { mutableStateOf<Int?>(null) }
    var mangaEdgeHint by remember { mutableStateOf<EdgeHint?>(null) }
    val transitionPolicy = remember { ChapterTransitionPolicy() }
    
    // 强制旋转状态
    var isForceLandscape by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    
    // 处理强制旋转逻辑
    DisposableEffect(isForceLandscape) {
        val activity = context as? android.app.Activity
        if (isForceLandscape) {
            activity?.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        } else {
            activity?.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        onDispose {
            if (isForceLandscape) {
                activity?.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
        }
    }
    
    val scrollState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    val latestOnExit by rememberUpdatedState(onExit)

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
            confirmButton = { TextButton(onClick = onClearError) { Text("好的") } }
        )
    }
    
    val displayContent = remember(currentChapterContent, currentChapterIndex, chapters) {
        if (currentChapterContent.isNotBlank()) currentChapterContent
        else chapters.getOrNull(currentChapterIndex)?.content.orEmpty()
    }

    val currentChapterUrl = remember(currentChapterIndex, chapters) {
        chapters.getOrNull(currentChapterIndex)?.url
    }

    val currentParagraphs = remember(displayContent) {
        parseDisplayParagraphs(displayContent)
    }

    val isMangaMode = remember(currentParagraphs, book.type, manualMangaUrls) {
        if (manualMangaUrls.contains(book.bookUrl)) return@remember true
        val imageCount = currentParagraphs.count { it.contains("__IMG__") }
        book.type == 2 || (currentParagraphs.isNotEmpty() && imageCount.toFloat() / currentParagraphs.size > 0.1f)
    }

    val prevParagraphs = remember(prevChapterContent) {
        parseDisplayParagraphs(prevChapterContent.orEmpty())
    }
    val nextParagraphs = remember(nextChapterContent) {
        parseDisplayParagraphs(nextChapterContent.orEmpty())
    }

    val chapterSections = remember(
        isInfiniteScrollEnabled,
        currentChapterIndex,
        chapters,
        currentParagraphs,
        prevParagraphs,
        nextParagraphs,
        prevChapterContent,
        nextChapterContent,
        isMangaMode
    ) {
        if (!isInfiniteScrollEnabled || isMangaMode || currentParagraphs.isEmpty()) {
            listOf(
                ChapterSection(
                    chapterIndex = currentChapterIndex,
                    title = chapters.getOrNull(currentChapterIndex)?.title ?: "章节",
                    paragraphs = currentParagraphs,
                    isCurrent = true
                )
            )
        } else {
            buildList {
                val prevIndex = currentChapterIndex - 1
                if (prevIndex >= 0 && prevChapterContent != null && prevParagraphs.isNotEmpty()) {
                    add(
                        ChapterSection(
                            chapterIndex = prevIndex,
                            title = chapters.getOrNull(prevIndex)?.title ?: "上一章",
                            paragraphs = prevParagraphs,
                            isCurrent = false
                        )
                    )
                }
                add(
                    ChapterSection(
                        chapterIndex = currentChapterIndex,
                        title = chapters.getOrNull(currentChapterIndex)?.title ?: "章节",
                        paragraphs = currentParagraphs,
                        isCurrent = true
                    )
                )
                val nextIndex = currentChapterIndex + 1
                if (nextIndex < chapters.size && nextChapterContent != null && nextParagraphs.isNotEmpty()) {
                    add(
                        ChapterSection(
                            chapterIndex = nextIndex,
                            title = chapters.getOrNull(nextIndex)?.title ?: "下一章",
                            paragraphs = nextParagraphs,
                            isCurrent = false
                        )
                    )
                }
            }
        }
    }

    val listItems = remember(chapterSections) {
        buildList {
            chapterSections.forEach { section ->
                add(ReadingListItem.ChapterTitle(section.chapterIndex, section.title, section.isCurrent))
                section.paragraphs.forEachIndexed { index, text ->
                    add(ReadingListItem.ParagraphItem(section.chapterIndex, index, text, section.isCurrent))
                }
            }
        }
    }

    val sectionOffsets = remember(chapterSections, currentChapterIndex) {
        var offset = 0
        var currentStart = 0
        var currentEnd = 0
        var prevStart: Int? = null
        var nextStart: Int? = null
        chapterSections.forEach { section ->
            val start = offset
            val count = 1 + section.paragraphs.size
            val end = start + count
            if (section.isCurrent) {
                currentStart = start
                currentEnd = end
            } else if (section.chapterIndex < currentChapterIndex) {
                prevStart = start
            } else if (section.chapterIndex > currentChapterIndex) {
                nextStart = start
            }
            offset = end
        }
        SectionOffsets(currentStart, currentEnd, prevStart, nextStart)
    }

    // 监听切章并分发意图
    LaunchedEffect(currentChapterIndex) {
        if (currentChapterIndex != lastChapterIndex) {
            onLoadChapterContent(currentChapterIndex)
            if (navIntent == ChapterNavIntent.NONE) {
                navIntent = ChapterNavIntent.FIRST
            }
            transitionPolicy.resetCooldown()
            lastChapterIndex = currentChapterIndex
        }
    }

    LaunchedEffect(currentChapterIndex, isMangaMode) {
        if (isMangaMode && mangaNavIntent == ChapterNavIntent.NONE) {
            mangaNavIntent = ChapterNavIntent.FIRST
        }
    }

    LaunchedEffect(scrollState, isInfiniteScrollEnabled, isMangaMode, readingMode, sectionOffsets) {
        snapshotFlow { scrollState.firstVisibleItemIndex to scrollState.isScrollInProgress }
            .distinctUntilChanged()
            .collect { (index, scrolling) ->
                val action = transitionPolicy.evaluate(
                    firstVisibleIndex = index,
                    isScrolling = scrolling,
                    isInfiniteScrollEnabled = isInfiniteScrollEnabled,
                    isMangaMode = isMangaMode,
                    readingMode = readingMode,
                    offsets = sectionOffsets
                ) ?: return@collect
                onInfiniteScrollSwitch(action.direction, action.anchorParagraphIndex)
            }
    }

    // 上报垂直滚动进度
    LaunchedEffect(scrollState, readingMode, isMangaMode, isInfiniteScrollEnabled, sectionOffsets) {
        snapshotFlow { scrollState.firstVisibleItemIndex }
            .distinctUntilChanged()
            .collect { index ->
                if (readingMode != ReadingMode.Vertical || isMangaMode) return@collect
                if (!isInfiniteScrollEnabled) {
                    onScrollUpdate((index - 1).coerceAtLeast(0))
                    return@collect
                }
                if (index in (sectionOffsets.currentStart + 1) until sectionOffsets.currentEndExclusive) {
                    onScrollUpdate((index - sectionOffsets.currentStart - 1).coerceAtLeast(0))
                }
            }
    }

    // 处理挂起的滚动 (垂直模式)
    LaunchedEffect(pendingScrollIndex, isMangaMode, readingMode, isInfiniteScrollEnabled, sectionOffsets) {
        if (readingMode == ReadingMode.Vertical && !isMangaMode && pendingScrollIndex != null) {
            val target = if (isInfiniteScrollEnabled) {
                sectionOffsets.currentStart + 1 + pendingScrollIndex
            } else {
                pendingScrollIndex + 1
            }
            scrollState.scrollToItem(target.coerceAtLeast(0))
            onScrollConsumed()
        }
    }

    LaunchedEffect(isMangaMode, mangaNavIntent, currentParagraphs) {
        if (!isMangaMode) return@LaunchedEffect
        when (mangaNavIntent) {
            ChapterNavIntent.FIRST -> {
                mangaPendingScrollIndex = 0
                mangaNavIntent = ChapterNavIntent.NONE
            }
            ChapterNavIntent.LAST -> {
                mangaPendingScrollIndex = (currentParagraphs.size - 1).coerceAtLeast(0)
                mangaNavIntent = ChapterNavIntent.NONE
            }
            else -> Unit
        }
    }

    LaunchedEffect(mangaPendingScrollIndex) {
        if (mangaPendingScrollIndex != null) {
            kotlinx.coroutines.delay(16)
            mangaPendingScrollIndex = null
        }
    }

    DisposableEffect(Unit) { onDispose { latestOnExit() } }
    
    Box(
        modifier = modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)
    ) {
        if (isMangaMode) {
            MangaNativeReader(
                paragraphs = currentParagraphs,
                serverUrl = serverEndpoint,
                chapterUrl = currentChapterUrl,
                forceProxy = forceMangaProxy,
                pendingScrollIndex = mangaPendingScrollIndex,
                onToggleControls = { showControls = !showControls },
                onScroll = { onScrollUpdate(it) },
                onEdgeHint = { hint -> mangaEdgeHint = hint },
                onEdgeSwitch = { direction ->
                    if (direction < 0 && currentChapterIndex > 0) {
                        mangaNavIntent = ChapterNavIntent.LAST
                        onChapterClick(currentChapterIndex - 1)
                    } else if (direction > 0 && currentChapterIndex < chapters.size - 1) {
                        mangaNavIntent = ChapterNavIntent.FIRST
                        onChapterClick(currentChapterIndex + 1)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        } else if (readingMode == ReadingMode.Vertical) {
            LazyColumn(
                state = scrollState,
                modifier = Modifier.fillMaxSize().clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) { showControls = !showControls },
                contentPadding = contentPadding
            ) {
                if (currentParagraphs.isEmpty()) {
                    item {
                        Column(modifier = Modifier.fillMaxWidth().padding(vertical = AppDimens.PaddingLarge), horizontalAlignment = Alignment.CenterHorizontally) {
                            if (isContentLoading) CircularProgressIndicator()
                            Text(text = if (isContentLoading) "正在加载..." else "暂无内容", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.customColors.textSecondary)
                        }
                    }
                } else {
                    itemsIndexed(items = listItems, key = { _, item ->
                        when (item) {
                            is ReadingListItem.ChapterTitle -> "title_${item.chapterIndex}"
                            is ReadingListItem.ParagraphItem -> "p_${item.chapterIndex}_${item.paragraphIndex}"
                        }
                    }) { _, item ->
                        when (item) {
                            is ReadingListItem.ChapterTitle -> {
                                Text(
                                    text = item.title,
                                    style = if (item.isCurrent) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.titleMedium,
                                    color = if (item.isCurrent) MaterialTheme.colorScheme.onSurface else MaterialTheme.customColors.textSecondary,
                                    modifier = Modifier.padding(bottom = AppDimens.PaddingLarge)
                                )
                            }
                            is ReadingListItem.ParagraphItem -> {
                                val chapterUrlForItem = chapters.getOrNull(item.chapterIndex)?.url
                                ParagraphItem(
                                    text = item.text,
                                    isPlaying = item.isCurrent && isPlaying && item.paragraphIndex == currentPlayingParagraph,
                                    isPreloaded = item.isCurrent && preloadedParagraphs.contains(item.paragraphIndex),
                                    fontSize = readingFontSize,
                                    chapterUrl = chapterUrlForItem,
                                    serverUrl = serverEndpoint,
                                    forceProxy = forceMangaProxy,
                                    modifier = Modifier.fillMaxWidth().padding(bottom = AppDimens.PaddingMedium)
                                )
                            }
                        }
                    }
                }
            }
        } else {
            // Horizontal Pager 模式
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val style = MaterialTheme.typography.bodyLarge.copy(fontSize = readingFontSize.sp, lineHeight = (readingFontSize * 1.8f).sp)
                val chapterTitle = chapters.getOrNull(currentChapterIndex)?.title.orEmpty()
                val headerText = if (chapterTitle.isNotBlank()) chapterTitle + "\n\n" else ""
                val headerFontSize = (readingFontSize + 6f).sp
                val lineHeightPx = with(LocalDensity.current) { (readingFontSize * 1.8f).sp.toPx() }
                val density = LocalDensity.current
                val availableConstraints = remember(constraints, contentPadding, density) { adjustedConstraints(constraints, contentPadding, density) }
                val paginatedPages = rememberPaginatedText(currentParagraphs, style, availableConstraints, lineHeightPx, headerText, headerFontSize)
                
                key(currentChapterIndex) { // 强行重置 Pager 状态
                    val pagerState = rememberPagerState(initialPage = 0, pageCount = { paginatedPages.pages.size.coerceAtLeast(1) })
                    
                    LaunchedEffect(paginatedPages, isPlaying, currentPlayingParagraph, pendingScrollIndex, navIntent) {
                        if (paginatedPages.pages.isEmpty()) return@LaunchedEffect
                        if (isPlaying && currentPlayingParagraph >= 0) {
                            val target = paginatedPages.pages.indexOfFirst { it.startParagraphIndex >= currentPlayingParagraph }.coerceAtLeast(0)
                            pagerState.scrollToPage(target)
                            navIntent = ChapterNavIntent.NONE
                        } else if (pendingScrollIndex != null) {
                            val target = paginatedPages.pages.indexOfFirst { it.startParagraphIndex >= pendingScrollIndex }.coerceAtLeast(0)
                            pagerState.scrollToPage(target)
                            onScrollConsumed()
                            navIntent = ChapterNavIntent.NONE
                        } else if (navIntent == ChapterNavIntent.LAST) {
                            pagerState.scrollToPage(paginatedPages.lastIndex)
                            navIntent = ChapterNavIntent.NONE
                        } else if (navIntent == ChapterNavIntent.FIRST) {
                            pagerState.scrollToPage(0)
                            navIntent = ChapterNavIntent.NONE
                        }
                    }

                    val viewConfiguration = LocalViewConfiguration.current
                    HorizontalPager(
                        state = pagerState,
                        userScrollEnabled = !(isPlaying && lockPageOnTTS),
                        modifier = Modifier.fillMaxSize().pointerInput(showControls, paginatedPages, isPlaying, lockPageOnTTS, viewConfiguration) {
                            detectTapGesturesWithoutConsuming(viewConfiguration) { offset, size ->
                                if (isPlaying && lockPageOnTTS) {
                                    if (offset.x in (size.width / 3f)..(size.width * 2f / 3f)) showControls = !showControls
                                    return@detectTapGesturesWithoutConsuming
                                }
                                handleHorizontalTap(offset, size, showControls, pagerState, paginatedPages.pages, 
                                    onPreviousChapter = { navIntent = ChapterNavIntent.LAST; onChapterClick(currentChapterIndex - 1) }, 
                                    onNextChapter = { navIntent = ChapterNavIntent.FIRST; onChapterClick(currentChapterIndex + 1) }, 
                                    coroutineScope, onToggleControls = { showControls = it })
                            }
                        }
                    ) { page ->
                        val pi = paginatedPages.getOrNull(page)
                        val text = pi?.let { 
                            remember(it, isPlaying, currentPlayingParagraph, paginatedPages.fullText) { // 修正：增加 isPlaying 依赖
                                val base = paginatedPages.fullText.subSequence(it.start.coerceAtLeast(0), it.end.coerceAtMost(paginatedPages.fullText.text.length))
                                if (isPlaying && currentPlayingParagraph == it.startParagraphIndex) { // 修正：必须处于播放状态才高亮
                                    AnnotatedString.Builder(base).apply { addStyle(SpanStyle(background = Color.Blue.copy(alpha = 0.15f)), 0, base.length) }.toAnnotatedString()
                                } else base
                            }
                        } ?: AnnotatedString("")
                        Box(modifier = Modifier.fillMaxSize().padding(contentPadding)) { 
                            SelectionContainer { Text(text = text, style = style, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.fillMaxSize()) } 
                        }
                    }
                    LaunchedEffect(pagerState.currentPage) { paginatedPages.getOrNull(pagerState.currentPage)?.let { onScrollUpdate(it.startParagraphIndex) } }
                }
            }
        }
        
        AnimatedVisibility(visible = showControls, enter = fadeIn() + slideInVertically(), exit = fadeOut() + slideOutVertically(), modifier = Modifier.align(Alignment.TopCenter)) {
            TopControlBar(book.title, currentChapterIndex.let { if (it < chapters.size) chapters[it].title else "" }, onNavigateBack, onHeaderClick)
        }
        
        AnimatedVisibility(visible = showControls, enter = fadeIn() + slideInVertically(initialOffsetY = { it }), exit = fadeOut() + slideOutVertically(targetOffsetY = { it }), modifier = Modifier.align(Alignment.BottomCenter)) {
            BottomControlBar(
                isPlaying,
                isMangaMode,
                isForceLandscape = isForceLandscape,
                onToggleRotation = { isForceLandscape = !isForceLandscape },
                onPrev = { if (currentChapterIndex > 0) { navIntent = ChapterNavIntent.LAST; onChapterClick(currentChapterIndex - 1) } },
                onNext = { if (currentChapterIndex < chapters.size - 1) { navIntent = ChapterNavIntent.FIRST; onChapterClick(currentChapterIndex + 1) } },
                onList = { showChapterList = true },
                onPlay = onPlayPauseClick,
                onStop = onStopListening,
                onPrevP = onPreviousParagraph,
                onNextP = onNextParagraph,
                onFont = { showFontDialog = true },
                canPrev = currentChapterIndex > 0,
                canNext = currentChapterIndex < chapters.size - 1,
                showTts = showTtsControls && !isMangaMode
            )
        }

        mangaEdgeHint?.let { hint ->
            EdgeSwitchHint(
                text = hint.text,
                isTop = hint.isTop,
                modifier = Modifier.align(if (hint.isTop) Alignment.TopCenter else Alignment.BottomCenter)
            )
        }

        if (showChapterList) ChapterListDialog(chapters, currentChapterIndex, preloadedChapters, book.bookUrl ?: "", onChapter = { onChapterClick(it); showChapterList = false }, onDismiss = { showChapterList = false })
        if (showFontDialog) FontSizeDialog(readingFontSize, onReadingFontSizeChange, readingHorizontalPadding, onReadingHorizontalPaddingChange, lockPageOnTTS, onLockPageOnTTSChange, pageTurningMode, onPageTurningModeChange, darkModeConfig, onDarkModeChange, forceMangaProxy, onForceMangaProxyChange, readingMode, onReadingModeChange, isInfiniteScrollEnabled, onInfiniteScrollEnabledChange, isMangaMode, onDismiss = { showFontDialog = false })
    }
}

private fun parseDisplayParagraphs(content: String): List<String> {
    if (content.isBlank()) return emptyList()
    return content.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
}

@Composable
private fun rememberPaginatedText(paragraphs: List<String>, style: TextStyle, constraints: Constraints, lineHeightPx: Float, headerText: String, headerFontSize: TextUnit): PaginationResult {
    val textMeasurer = rememberTextMeasurer()
    return remember(paragraphs, style, constraints, lineHeightPx, headerText, headerFontSize) {
        if (paragraphs.isEmpty() || constraints.maxWidth == 0 || constraints.maxHeight == 0) return@remember PaginationResult(emptyList(), AnnotatedString(""))
        val paragraphStartIndices = paragraphStartIndices(paragraphs, headerText.length)
        val fullText = fullContent(paragraphs, headerText, headerFontSize)
        val layout = textMeasurer.measure(fullText, style, constraints = Constraints(maxWidth = constraints.maxWidth))
        if (layout.lineCount == 0) return@remember PaginationResult(emptyList(), fullText)
        val pages = mutableListOf<PaginatedPage>()
        var startLine = 0
        while (startLine < layout.lineCount) {
            val pageTop = layout.getLineTop(startLine)
            var endLine = startLine
            while (endLine + 1 < layout.lineCount && layout.getLineBottom(endLine + 1) - pageTop <= constraints.maxHeight.toFloat()) endLine++
            val startParagraphIndex = paragraphIndexForOffset(normalizePageOffset(fullText.text, (layout.getLineStart(startLine) - headerText.length).coerceAtLeast(0), headerText.length), paragraphStartIndices)
            pages.add(PaginatedPage(layout.getLineStart(startLine), layout.getLineEnd(endLine, true), startParagraphIndex))
            startLine = endLine + 1
        }
        PaginationResult(pages, fullText)
    }
}

private data class PaginatedPage(val start: Int, val end: Int, val startParagraphIndex: Int)
private data class PaginationResult(val pages: List<PaginatedPage>, val fullText: AnnotatedString) {
    val indices: IntRange get() = pages.indices
    val lastIndex: Int get() = pages.size - 1
    fun isEmpty(): Boolean = pages.isEmpty()
    fun getOrNull(index: Int): PaginatedPage? = pages.getOrNull(index)
}

private fun fullContent(paragraphs: List<String>, headerText: String, headerFontSize: TextUnit): AnnotatedString {
    val body = paragraphs.joinToString(separator = "\n\n") { it.trim() }
    return AnnotatedString.Builder().apply { if (headerText.isNotBlank()) { pushStyle(SpanStyle(fontSize = headerFontSize, fontWeight = FontWeight.Bold)); append(headerText); pop() }; append(body) }.toAnnotatedString()
}

private fun paragraphStartIndices(paragraphs: List<String>, prefixLength: Int): List<Int> {
    val starts = mutableListOf<Int>()
    var current = prefixLength
    paragraphs.forEachIndexed { i, p -> starts.add(current); current += p.trim().length + if (i < paragraphs.size - 1) 2 else 0 }
    return starts
}

private fun paragraphIndexForOffset(offset: Int, starts: List<Int>): Int = starts.indexOfLast { it <= offset }.coerceAtLeast(0)

private fun normalizePageOffset(fullText: String, bodyOffset: Int, headerLength: Int): Int {
    if (bodyOffset <= 0) return 0
    var absolute = (bodyOffset + headerLength).coerceIn(0, fullText.length)
    while (absolute < fullText.length && (fullText[absolute] == '\n' || fullText[absolute] == '\r')) absolute++
    return (absolute - headerLength).coerceAtLeast(0)
}

private fun adjustedConstraints(constraints: Constraints, padding: PaddingValues, density: Density): Constraints {
    val h = with(density) { (padding.calculateLeftPadding(LayoutDirection.Ltr) + padding.calculateRightPadding(LayoutDirection.Ltr)).toPx() }
    val v = with(density) { (padding.calculateTopPadding() + padding.calculateBottomPadding()).toPx() }
    return Constraints(maxWidth = (constraints.maxWidth - h).toInt().coerceAtLeast(0), maxHeight = (constraints.maxHeight - v).toInt().coerceAtLeast(0))
}

@OptIn(ExperimentalFoundationApi::class)
private suspend fun PointerInputScope.detectTapGesturesWithoutConsuming(vc: androidx.compose.ui.platform.ViewConfiguration, onTap: (Offset, IntSize) -> Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(false)
        var isTap = true
        var tapPos = down.position
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            if ((change.position - down.position).getDistance() > vc.touchSlop) isTap = false
            if (change.changedToUp()) { tapPos = change.position; break }
        }
        if (isTap) onTap(tapPos, size)
    }
}

@OptIn(ExperimentalFoundationApi::class)
private fun handleHorizontalTap(offset: Offset, size: IntSize, show: Boolean, state: androidx.compose.foundation.pager.PagerState, pages: List<PaginatedPage>, onPreviousChapter: () -> Unit, onNextChapter: () -> Unit, scope: kotlinx.coroutines.CoroutineScope, onToggleControls: (Boolean) -> Unit) {
    if (show) { onToggleControls(false); return }
    val width = size.width.toFloat()
    when {
        offset.x < width / 3f -> scope.launch { if (state.currentPage > 0) state.animateScrollToPage(state.currentPage - 1) else onPreviousChapter() }
        offset.x < width * 2f / 3f -> onToggleControls(true)
        else -> scope.launch { if (state.currentPage < pages.size - 1) state.animateScrollToPage(state.currentPage + 1) else onNextChapter() }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderOptionsDialog(fontSize: Float, onFontSize: (Float) -> Unit, hPadding: Float, onHPadding: (Float) -> Unit, lockTTS: Boolean, onLockTTS: (Boolean) -> Unit, turnMode: com.readapp.data.PageTurningMode, onTurnMode: (com.readapp.data.PageTurningMode) -> Unit, darkConfig: DarkModeConfig, onDark: (DarkModeConfig) -> Unit, forceProxy: Boolean, onForceProxy: (Boolean) -> Unit, mode: ReadingMode, onMode: (ReadingMode) -> Unit, infiniteScrollEnabled: Boolean, onInfiniteScrollEnabledChange: (Boolean) -> Unit, isManga: Boolean, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text("阅读选项") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (!isManga) {
                Column { Text("阅读模式", style = MaterialTheme.typography.labelMedium); Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { ReadingMode.values().forEach { m -> FilterChip(selected = mode == m, onClick = { onMode(m) }, label = { Text(if (m == ReadingMode.Vertical) "上下滚动" else "左右翻页") }, modifier = Modifier.weight(1f)) } } }
                Divider()
            }
            Column { Text("夜间模式", style = MaterialTheme.typography.labelMedium); Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { DarkModeConfig.values().forEach { c -> FilterChip(selected = darkConfig == c, onClick = { onDark(c) }, label = { Text(when(c){ DarkModeConfig.ON->"开启"; DarkModeConfig.OFF->"关闭"; DarkModeConfig.AUTO->"系统"}) }, modifier = Modifier.weight(1f)) } } }
            if (isManga) Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clickable { onForceProxy(!forceProxy) }) { Column(modifier = Modifier.weight(1f)) { Text("强制服务器代理", style = MaterialTheme.typography.bodyLarge); Text("如果漫画加载失败请开启", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline) }; Switch(checked = forceProxy, onCheckedChange = onForceProxy) }
            if (!isManga) {
                Divider()
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clickable { onInfiniteScrollEnabledChange(!infiniteScrollEnabled) }) {
                    Checkbox(checked = infiniteScrollEnabled, onCheckedChange = onInfiniteScrollEnabledChange)
                    Column(modifier = Modifier.padding(start = 8.dp)) {
                        Text("启用无限滚动", style = MaterialTheme.typography.bodyMedium)
                        Text("滚动过边界自动切换章节", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                    }
                }
                Column { Text("字体大小: ${fontSize.toInt()}sp", style = MaterialTheme.typography.labelMedium); Slider(value = fontSize, onValueChange = onFontSize, valueRange = 12f..30f) }
                Column { Text("页面边距: ${hPadding.toInt()}dp", style = MaterialTheme.typography.labelMedium); Slider(value = hPadding, onValueChange = onHPadding, valueRange = 0f..50f) }
                Divider()
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clickable { onLockTTS(!lockTTS) }) { Checkbox(checked = lockTTS, onCheckedChange = onLockTTS); Text("播放时锁定翻页", modifier = Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("完成") } })
}

@Composable
private fun FontSizeDialog(fontSize: Float, onFontSize: (Float) -> Unit, hPadding: Float, onHPadding: (Float) -> Unit, lockTTS: Boolean, onLockTTS: (Boolean) -> Unit, turnMode: com.readapp.data.PageTurningMode, onTurnMode: (com.readapp.data.PageTurningMode) -> Unit, darkConfig: DarkModeConfig, onDark: (DarkModeConfig) -> Unit, forceProxy: Boolean, onForceProxy: (Boolean) -> Unit, mode: ReadingMode, onMode: (ReadingMode) -> Unit, infiniteScrollEnabled: Boolean, onInfiniteScrollEnabledChange: (Boolean) -> Unit, isManga: Boolean, onDismiss: () -> Unit) {
    ReaderOptionsDialog(fontSize, onFontSize, hPadding, onHPadding, lockTTS, onLockTTS, turnMode, onTurnMode, darkConfig, onDark, forceProxy, onForceProxy, mode, onMode, infiniteScrollEnabled, onInfiniteScrollEnabledChange, isManga, onDismiss)
}

@Composable
private fun ControlButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit, enabled: Boolean = true) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) { IconButton(onClick = onClick, enabled = enabled) { Icon(icon, null, tint = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline.copy(alpha = 0.3f), modifier = Modifier.size(24.dp)) }; Text(label, style = MaterialTheme.typography.labelSmall, color = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.outline.copy(alpha = 0.3f)) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChapterListDialog(chapters: List<Chapter>, current: Int, preloaded: Set<Int>, url: String, onChapter: (Int) -> Unit, onDismiss: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val localCache = remember { LocalCacheManager(context) }
    var groupIdx by remember(chapters.size) { mutableStateOf(current / 50) }
    val groupCount = (chapters.size + 49) / 50
    AlertDialog(onDismissRequest = onDismiss, title = { Text("章节列表 (${chapters.size})", style = MaterialTheme.typography.titleLarge) }, text = {
        Column {
            if (groupCount > 1) { androidx.compose.foundation.lazy.LazyRow(modifier = Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { items(groupCount) { i -> val s = i * 50 + 1; val e = minOf((i + 1) * 50, chapters.size); FilterChip(selected = groupIdx == i, onClick = { groupIdx = i }, label = { Text("$s-$e") }) } } }
            LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f, false)) {
                val start = groupIdx * 50; val end = minOf((groupIdx + 1) * 50, chapters.size)
                itemsIndexed(chapters.subList(start, end)) { relIdx, chapter ->
                    val index = start + relIdx; val isCurrent = index == current
                    Surface(onClick = { onChapter(index) }, color = if (isCurrent) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f) else if (preloaded.contains(index)) MaterialTheme.customColors.success.copy(alpha = 0.1f) else MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) {
                        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp, horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) { Text(chapter.title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, color = if (isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface); if (isCurrent) Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.primary) { Text("当前", modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp), style = MaterialTheme.typography.labelSmall, color = Color.White) } } 
                    }
                    if (index < chapters.size - 1) Divider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                }
            }
        }
    }, confirmButton = {}, dismissButton = { TextButton(onClick = onDismiss) { Text("关闭") } }, shape = RoundedCornerShape(AppDimens.CornerRadiusLarge))
}
