package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.readapp.data.model.Book
import com.readapp.data.model.Chapter
import com.readapp.ui.theme.AppDimens

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookDetailScreen(
    book: Book,
    chapters: List<Chapter>,
    isChaptersLoading: Boolean,
    onNavigateBack: () -> Unit,
    onStartReading: () -> Unit,
    onChapterClick: (Int) -> Unit,
    onDownloadChapters: (Int, Int) -> Unit
) {
    var showDownloadDialog by remember { mutableStateOf(false) }
    var showCustomRangeDialog by remember { mutableStateOf(false) }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("书籍详情") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                },
                actions = {
                    IconButton(onClick = { showDownloadDialog = true }) {
                        Icon(Icons.Default.Download, "下载")
                    }
                }
            )
        },
        bottomBar = {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                tonalElevation = 8.dp,
                shadowElevation = 8.dp
            ) {
                Button(
                    onClick = onStartReading,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                        .height(56.dp),
                    shape = RoundedCornerShape(28.dp)
                ) {
                    Icon(Icons.Default.PlayArrow, null)
                    Spacer(Modifier.width(8.dp))
                    Text("开始阅读", style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // Book Header Info
            item {
                BookHeaderSection(book)
            }

            // Introduction
            item {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "简介",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        book.intro ?: "暂无简介",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Chapter List Header
            item {
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
            }

            // Chapters
            itemsIndexed(chapters) { index, chapter ->
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
                if (index < chapters.size - 1) {
                    Divider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            
            item {
                Spacer(Modifier.height(80.dp))
            }
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
    }
}

@Composable
private fun BookHeaderSection(book: Book) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        AsyncImage(
            model = book.coverUrl,
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
            Spacer(Modifier.height(4.dp))
            Text(
                book.author ?: "未知作者",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.secondary
            )
            Spacer(Modifier.height(8.dp))
            SuggestionChip(
                onClick = { },
                label = { Text(book.originName ?: "未知来源") }
            )
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
