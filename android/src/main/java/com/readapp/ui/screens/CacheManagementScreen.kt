package com.readapp.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.readapp.data.LocalCacheManager
import com.readapp.data.model.Book
import com.readapp.viewmodel.BookViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CacheManagementScreen(
    bookViewModel: BookViewModel,
    onNavigateBack: () -> Unit
) {
    val books by bookViewModel.books.collectAsState()
    val localCache = remember { LocalCacheManager(bookViewModel.getApplication()) }
    var totalCacheSize by remember { mutableStateOf(0L) }
    
    LaunchedEffect(Unit) {
        totalCacheSize = 0L // Recalculate if needed or provide a method in LocalCacheManager
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("离线缓存管理") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                },
                actions = {
                    TextButton(onClick = { 
                        localCache.clearAllCache()
                        // Force recompose or refresh
                    }) {
                        Text("清空全部", color = MaterialTheme.colorScheme.error)
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            items(books) { book ->
                val cachedCount = localCache.getCachedChapterCount(book.bookUrl ?: "", book.totalChapterNum ?: 0)
                if (cachedCount > 0) {
                    val size = localCache.getCacheSize(book.bookUrl ?: "")
                    ListItem(
                        headlineContent = { Text(book.name ?: "未知书名") },
                        supportingContent = { Text("已缓存 $cachedCount 章 (${formatFileSize(size)})") },
                        trailingContent = {
                            IconButton(onClick = { localCache.clearCache(book.bookUrl ?: "") }) {
                                Icon(Icons.Default.Delete, "清除", tint = MaterialTheme.colorScheme.error)
                            }
                        }
                    )
                    Divider()
                }
            }
        }
    }
}

private fun formatFileSize(size: Long): String {
    if (size <= 0) return "0 B"
    val units = listOf("B", "KB", "MB", "GB", "TB")
    var s = size.toDouble()
    var unitIndex = 0
    while (s >= 1024 && unitIndex < units.size - 1) {
        s /= 1024
        unitIndex++
    }
    return "%.2f %s".format(s, units[unitIndex])
}
