// ReadingScreen.kt - 闃呰椤甸潰闆嗘垚鍚功鍔熻兘锛堟钀介珮浜級
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
    lockPageOnTTS: Boolean = false,
    onLockPageOnTTSChange: (Boolean) -> Unit = {},
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

    // 褰撶珷鑺傜储寮曞彉鍖栨垨绔犺妭鍒楄〃鍔犺浇瀹屾垚鏃讹紝鑷姩鍔犺浇绔犺妭鍐呭骞跺洖鍒伴《閮?
    LaunchedEffect(currentChapterIndex, chapters.size) {
        if (chapters.isNotEmpty() && currentChapterIndex in chapters.indices) {
            onLoadChapterContent(currentChapterIndex)
            scrollState.scrollToItem(0)
        }
    }
    
    // 褰撳墠鎾斁娈佃惤鍙樺寲鏃讹紝鑷姩婊氬姩鍒拌娈佃惤
    LaunchedEffect(currentPlayingParagraph) {
        if (currentPlayingParagraph >= 0 && currentPlayingParagraph < paragraphs.size) {
            coroutineScope.launch {
                // +1 鏄洜涓虹涓€涓?item 鏄珷鑺傛爣棰?
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
        // 涓昏鍐呭鍖哄煙锛氭樉绀虹珷鑺傛鏂?
        Column(
            modifier = Modifier
                .fillMaxSize()
                .clickable(
                    enabled = readingMode == ReadingMode.Vertical,
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) {
                    // 鐐瑰嚮鍒囨崲鎺у埗鏍忔樉绀?闅愯棌
                    showControls = !showControls
                }
        ) {
            // 鍐呭鍖哄煙
            if (readingMode == com.readapp.data.ReadingMode.Vertical) {
                LazyColumn(
                    state = scrollState,
                    modifier = Modifier
                        .fillMaxSize()
                        .weight(1f),
                    contentPadding = contentPadding
                ) {
                    // 绔犺妭鏍囬
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
                        // 绔犺妭鍐呭锛堝垎娈垫樉绀猴紝甯﹂珮浜級
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
                    val pageTextCache = remember { mutableStateMapOf<Int, AnnotatedString>() }
                    val pagerState = rememberPagerState { paginatedPages.pages.size.coerceAtLeast(1) }
                    resolveCurrentPageStart = {
                        paginatedPages.getOrNull(pagerState.currentPage)?.let {
                            it.startParagraphIndex to it.startOffsetInParagraph
                        }
                    }
                    val viewConfiguration = LocalViewConfiguration.current
                    val onPreviousChapterFromPager = {
                        if (currentChapterIndex > 0) {
                            pendingJumpToLastPageTarget = currentChapterIndex - 1
                            onChapterClick(currentChapterIndex - 1)
                        }
                    }
                    val onNextChapterFromPager = {
                        if (currentChapterIndex < chapters.size - 1) {
                            pendingJumpToLastPageTarget = null
                            onChapterClick(currentChapterIndex + 1)
                        }
                    }
                    
                    Box(modifier = Modifier.fillMaxSize()) {
                        HorizontalPager(
                            state = pagerState,
                            userScrollEnabled = !(isPlaying && lockPageOnTTS),
                            modifier = Modifier
                                .fillMaxSize()
                                .pointerInput(
                                    showControls,
                                    paginatedPages,
                                    currentChapterIndex,
                                    viewConfiguration,
                                    isPlaying,
                                    lockPageOnTTS
                                ) {
                                    detectTapGesturesWithoutConsuming(viewConfiguration) { offset, size ->
                                        if (isPlaying && lockPageOnTTS) {
                                            val width = size.width.toFloat()
                                            val isMiddle = offset.x in (width / 3f)..(width * 2f / 3f)
                                            if (isMiddle) {
                                                showControls = !showControls
                                            }
                                            return@detectTapGesturesWithoutConsuming
                                        }
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
                            val pageInfo = paginatedPages.getOrNull(page)
                            val pageText = pageInfo?.let { pi ->
                                remember(pi, currentPlayingParagraph, currentParagraphStartOffset, playbackProgress, paginatedPages.fullText) {
                                    val baseText = paginatedPages.fullText.subSequence(
                                        pi.start.coerceAtLeast(0),
                                        pi.end.coerceAtMost(paginatedPages.fullText.text.length)
                                    )
                                    
                                    if (currentPlayingParagraph == pi.startParagraphIndex) {
                                        val builder = AnnotatedString.Builder(baseText)
                                        // 计算在当前页面内的相对偏移
                                        // 简化版：由于阅读器分页通常以段落为界或包含完整段落，这里对当前段落覆盖到的文字应用高亮
                                        // 如果需要更精准，需要 paragraphStartIndices
                                        builder.addStyle(
                                            style = SpanStyle(background = Color.Blue.copy(alpha = 0.15f)),
                                            start = 0,
                                            end = baseText.length
                                        )
                                        builder.toAnnotatedString()
                                    } else {
                                        baseText
                                    }
                                }
                            } ?: AnnotatedString("")
                            
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
                    
                        LaunchedEffect(pagerState, paginatedPages, isPlaying, lockPageOnTTS) {
                            snapshotFlow { pagerState.currentPage to pagerState.isScrollInProgress }
                                .distinctUntilChanged()
                                .collect { (page, isScrolling) ->
                                    val pageInfo = paginatedPages.getOrNull(page)
                                    if (pageInfo != null) {
                                        currentPageStartIndex = pageInfo.startParagraphIndex
                                        currentPageStartOffset = pageInfo.startOffsetInParagraph

                                        if (isPlaying && !isPaused && !lockPageOnTTS && !isAutoScrolling && isScrolling) {
                                            if (!lockPageOnTTS) {
                                                onStopListening()
                                                onStartListening(pageInfo.startParagraphIndex, pageInfo.startOffsetInParagraph)
                                            }
                                        }
                                        lastAutoScrollTarget = null
                                        isAutoScrolling = false
                                    }
                                }
                        }

                        LaunchedEffect(
                            currentPlayingParagraph,
                            currentParagraphStartOffset,
                            playbackProgress,
                            paginatedPages,
                            readingMode,
                            isPlaying
                        ) {
                            if (readingMode != ReadingMode.Horizontal) return@LaunchedEffect
                            if (!isPlaying) return@LaunchedEffect
                            if (currentPlayingParagraph < 0 || paginatedPages.isEmpty()) return@LaunchedEffect
                            if (pagerState.currentPageOffsetFraction != 0f) return@LaunchedEffect
                            val paragraph = paragraphs.getOrNull(currentPlayingParagraph) ?: return@LaunchedEffect
                            val paragraphLength = paragraph.length
                            if (paragraphLength <= 0) return@LaunchedEffect
                            val startOffset = currentParagraphStartOffset.coerceIn(0, paragraphLength)
                            val playableLength = (paragraphLength - startOffset).coerceAtLeast(1)
                            val offsetInParagraph =
                                startOffset + (playbackProgress.coerceIn(0f, 1f) * playableLength).toInt()
                            val pagesForParagraph = paginatedPages.pages.withIndex()
                                .filter { it.value.startParagraphIndex == currentPlayingParagraph }
                            if (pagesForParagraph.isEmpty()) return@LaunchedEffect
                            var targetPage = pagesForParagraph.first().index
                            for (i in pagesForParagraph.indices) {
                                val entry = pagesForParagraph[i]
                                val start = entry.value.startOffsetInParagraph
                                val nextStart = pagesForParagraph.getOrNull(i + 1)?.value?.startOffsetInParagraph
                                val inThisPage = if (nextStart == null || nextStart <= start) {
                                    offsetInParagraph >= start
                                } else {
                                    offsetInParagraph >= start && offsetInParagraph < nextStart
                                }
                                if (inThisPage) {
                                    targetPage = entry.index
                                    break
                                }
                            }
                            if (targetPage != pagerState.currentPage) {
                                if (pagerState.isScrollInProgress) return@LaunchedEffect
                                if (lastAutoScrollTarget == targetPage) return@LaunchedEffect
                                lastAutoScrollTarget = targetPage
                                isAutoScrolling = true
                                pagerState.scrollToPage(targetPage)
                            }
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
                                    val safeEnd = pageInfo.end.coerceAtMost(paginatedPages.fullText.text.length)
                                    val text = if (safeEnd > safeStart) {
                                        paginatedPages.fullText.subSequence(safeStart, safeEnd)
                                    } else {
                                        AnnotatedString("")
                                    }
                                    pageTextCache[index] = text
                                }
                            }
                            val staleKeys = pageTextCache.keys.filter { it !in indices }
                            for (key in staleKeys) {
                                pageTextCache.remove(key)
                            }
                        }
                    
                        LaunchedEffect(pendingJumpToLastPageTarget, paginatedPages, currentChapterIndex) {
                            if (paginatedPages.isEmpty()) return@LaunchedEffect
                            if (currentChapterIndex == lastHandledChapterIndex) return@LaunchedEffect
                            val target = pendingJumpToLastPageTarget
                            if (target != null && currentChapterIndex == target) {
                                pagerState.scrollToPage(paginatedPages.lastIndex)
                            } else {
                                pagerState.scrollToPage(0)
                            }
                            lastHandledChapterIndex = currentChapterIndex
                            pendingJumpToLastPageTarget = null
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
                        onChapterClick(currentChapterIndex - 1)
                    }
                },
                onNextChapter = {
                    if (currentChapterIndex < chapters.size - 1) {
                        pendingJumpToLastPageTarget = null
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
                onDismiss = { showFontDialog = false }
            )
        }
    }
}

/**
 * 娈佃惤椤圭粍浠?- 甯﹂珮浜晥鏋?
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
        isPlaying -> MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)  // 褰撳墠鎾斁锛氭繁钃濊壊楂樹寒
        isPreloaded -> MaterialTheme.customColors.success.copy(alpha = 0.15f)  // 宸查杞斤細娴呯豢鑹叉爣璁?
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
                            contentDescription = if (isPlaying) "\u6682\u505c" else "\u64ad\u653e",
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
    isDarkMode: Boolean,
    onDarkModeChange: (Boolean) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = "阅读选项") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                // 夜间模式
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().clickable { onDarkModeChange(!isDarkMode) }
                ) {
                    Text("夜间模式", modifier = Modifier.weight(1f))
                    Switch(checked = isDarkMode, onCheckedChange = onDarkModeChange)
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

                // 翻页模式
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("翻页效果", style = MaterialTheme.typography.labelMedium)
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


