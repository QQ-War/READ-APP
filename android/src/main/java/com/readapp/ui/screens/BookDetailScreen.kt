package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.readapp.ui.components.RemoteCoverImage
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.theme.AppDimens

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookDetailScreen(
    book: Book,
    chapters: List<Chapter>,
    isChaptersLoading: Boolean,
    isInBookshelf: Boolean,
    manualMangaUrls: Set<String>,
    onToggleManualManga: (String) -> Unit,
    onAddToBookshelf: () -> Unit,
    onRemoveFromBookshelf: () -> Unit,
    onSourceSwitch: (Book) -> Unit,
    onNavigateBack: () -> Unit,
    onStartReading: () -> Unit,
    onChapterClick: (Int) -> Unit,
    onDownloadChapters: (Int, Int) -> Unit,
    onRefresh: () -> Unit
) {
    var showDownloadDialog by remember { mutableStateOf(false) }
    var showCustomRangeDialog by remember { mutableStateOf(false) }
    var showSourceSwitchDialog by remember { mutableStateOf(false) }
    
    val isManuallyMarkedAsManga = remember(manualMangaUrls, book.bookUrl) {
        manualMangaUrls.contains(book.bookUrl)
    }
    val isAudioBook = book.type == 1
    val pullRefreshState = rememberPullRefreshState(
        refreshing = isChaptersLoading,
        onRefresh = onRefresh
    )

    Scaffold(
        // ... topBar ...
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .pullRefresh(pullRefreshState)
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize()
            ) {
                // Book Header Info
                item {
                    BookHeaderSection(
                        book = book,
                        isInBookshelf = isInBookshelf,
                        onAddToBookshelf = onAddToBookshelf,
                        onRemoveFromBookshelf = onRemoveFromBookshelf,
                        onShowSourceSwitch = { showSourceSwitchDialog = true }
                    )
                }

            if (!isAudioBook) {
                // Manga Mode Toggle
                item {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                            .clickable { book.bookUrl?.let { onToggleManualManga(it) } },
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Book, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.width(16.dp))
                            Text(
                                "强制漫画模式",
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyLarge
                            )
                            Switch(
                                checked = isManuallyMarkedAsManga,
                                onCheckedChange = { book.bookUrl?.let { onToggleManualManga(it) } }
                            )
                        }
                    }
                }
            }

            item {
                Button(
                    onClick = onStartReading,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                ) {
                    Icon(
                        imageVector = Icons.Default.PlayArrow,
                        contentDescription = null
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(if (isAudioBook) "开始播放" else "开始阅读")
                }
            }

            // Introduction
            item {
                // ... intro ...
            }
            // ... rest of screen ...

            // Chapter List Header
            item {
                var currentGroupIndex by remember(chapters.size) {
                    val initialIndex = book.durChapterIndex ?: 0
                    mutableStateOf(initialIndex / 50)
                }
                val groupCount = (chapters.size + 49) / 50
                
                Column {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "目录 (${chapters.size}章)",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold
                        )
                        if (isChaptersLoading) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        }
                    }
                    
                    if (groupCount > 1) {
                        androidx.compose.foundation.lazy.LazyRow(
                            contentPadding = PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.padding(bottom = 8.dp)
                        ) {
                            items(groupCount) { index ->
                                val start = index * 50 + 1
                                val end = minOf((index + 1) * 50, chapters.size)
                                FilterChip(
                                    selected = currentGroupIndex == index,
                                    onClick = { currentGroupIndex = index },
                                    label = { Text("$start-$end") }
                                )
                            }
                        }
                    }
                    
                    val start = currentGroupIndex * 50
                    val end = minOf((currentGroupIndex + 1) * 50, chapters.size)
                    val visibleChapters = chapters.subList(start, end)
                    
                    visibleChapters.forEachIndexed { relativeIndex, chapter ->
                        val index = start + relativeIndex
                        ListItem(
                            headlineContent = { 
                                Text(
                                    chapter.title,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    color = if (index == (book.durChapterIndex ?: 0)) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                                )
                            },
                            supportingContent = { Text("第 ${index + 1} 章") },
                            modifier = Modifier.clickable { onChapterClick(index) }
                        )
                        Divider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
            
                item {
                    Spacer(Modifier.height(80.dp))
                }
            }
            PullRefreshIndicator(
                refreshing = isChaptersLoading,
                state = pullRefreshState,
                modifier = Modifier.align(Alignment.TopCenter)
            )
        }

        if (showDownloadDialog) {
            AlertDialog(
                onDismissRequest = { showDownloadDialog = false },
                title = { Text("选择缓存范围") },
                text = {
                    Column {
                        ListItem(
                            headlineContent = { Text("缓存全文") },
                            modifier = Modifier.clickable {
                                onDownloadChapters(0, chapters.lastIndex)
                                showDownloadDialog = false
                            }
                        )
                        ListItem(
                            headlineContent = { Text("缓存后续 50 章") },
                            modifier = Modifier.clickable {
                                val current = book.durChapterIndex ?: 0
                                onDownloadChapters(current, (current + 50).coerceAtMost(chapters.lastIndex))
                                showDownloadDialog = false
                            }
                        )
                        ListItem(
                            headlineContent = { Text("自定义范围") },
                            modifier = Modifier.clickable {
                                showDownloadDialog = false
                                showCustomRangeDialog = true
                            }
                        )
                    }
                },
                confirmButton = {
                    TextButton(onClick = { showDownloadDialog = false }) { Text("取消") }
                }
            )
        }

        if (showCustomRangeDialog) {
            var startText by remember { mutableStateOf("1") }
            var endText by remember { mutableStateOf(chapters.size.toString()) }
            
            AlertDialog(
                onDismissRequest = { showCustomRangeDialog = false },
                title = { Text("自定义缓存范围") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = startText,
                            onValueChange = { startText = it },
                            label = { Text("起始章节") }
                        )
                        OutlinedTextField(
                            value = endText,
                            onValueChange = { endText = it },
                            label = { Text("结束章节") }
                        )
                    }
                },
                confirmButton = {
                    Button(onClick = {
                        val s = startText.toIntOrNull()?.minus(1) ?: 0
                        val e = endText.toIntOrNull()?.minus(1) ?: chapters.lastIndex
                        onDownloadChapters(s, e)
                        showCustomRangeDialog = false
                    }) {
                        Text("开始下载")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showCustomRangeDialog = false }) { Text("取消") }
                }
            )
        }

        if (showSourceSwitchDialog) {
            SourceSwitchDialog(
                bookName = book.name ?: "",
                author = book.author ?: "",
                currentSource = book.origin ?: "",
                onSelect = { 
                    onSourceSwitch(it)
                    showSourceSwitchDialog = false 
                },
                onDismiss = { showSourceSwitchDialog = false }
            )
        }
    }
}

@Composable
fun SourceSwitchDialog(
    bookName: String,
    author: String,
    currentSource: String,
    onSelect: (Book) -> Unit,
    onDismiss: () -> Unit
) {
    val bookViewModel: com.readapp.viewmodel.BookViewModel = androidx.lifecycle.viewmodel.compose.viewModel(factory = com.readapp.viewmodel.BookViewModel.Factory)
    val results by bookViewModel.searchNewSource(bookName, author).collectAsState(initial = emptyList())
    
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("更换来源 (书名完全一致)") },
        text = {
            if (results.isEmpty()) {
                Box(Modifier.fillMaxWidth().height(100.dp), Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(Modifier.size(24.dp))
                        Spacer(Modifier.height(8.dp))
                        Text("正在搜索书名一致的源...", style = MaterialTheme.typography.labelSmall)
                    }
                }
            } else {
                LazyColumn(Modifier.heightIn(max = 400.dp)) {
                    items(results) { resBook ->
                        val isAuthorMatch = resBook.author == author
                        ListItem(
                            headlineContent = { 
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(resBook.sourceDisplayName ?: "未知源")
                                    if (isAuthorMatch) {
                                        Spacer(Modifier.width(8.dp))
                                        Surface(color = Color(0xFFE8F5E9), shape = RoundedCornerShape(4.dp)) {
                                            Text("推荐", color = Color(0xFF2E7D32), style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(horizontal = 4.dp))
                                        }
                                    }
                                }
                            },
                            supportingContent = { Text("${resBook.name} • ${resBook.author}") },
                            trailingContent = {
                                if (resBook.origin == currentSource) {
                                    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(4.dp)) {
                                        Text("当前", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(horizontal = 4.dp))
                                    }
                                }
                            },
                            modifier = Modifier.clickable { onSelect(resBook) }
                        )
                        Divider()
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("关闭") }
        }
    )
}

@Composable
private fun BookHeaderSection(
    book: Book,
    isInBookshelf: Boolean,
    onAddToBookshelf: () -> Unit,
    onRemoveFromBookshelf: () -> Unit,
    onShowSourceSwitch: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        RemoteCoverImage(
            url = book.coverUrl,
            contentDescription = null,
            modifier = Modifier
                .width(100.dp)
                .height(140.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentScale = ContentScale.Crop
        )

        Column(modifier = Modifier.weight(1f)) {
            Text(
                book.name ?: "未知书名",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                book.author ?: "未知作者",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.secondary
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = onShowSourceSwitch,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary)
                ) {
                    Text("换源")
                }
                
                if (isInBookshelf) {
                    IconButton(onClick = onRemoveFromBookshelf) {
                        Icon(Icons.Default.RemoveCircleOutline, null, tint = MaterialTheme.colorScheme.error)
                    }
                } else {
                    IconButton(onClick = onAddToBookshelf) {
                        Icon(Icons.Default.AddCircleOutline, null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SuggestionChip(
                    onClick = { },
                    label = { Text(book.originName ?: "未知来源") }
                )
                if (book.type == 1) {
                    SuggestionChip(
                        onClick = { },
                        label = { Text("音频书") }
                    )
                }
            }
            if (book.durChapterTitle != null) {
                Text(
                    "读至: ${book.durChapterTitle}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
