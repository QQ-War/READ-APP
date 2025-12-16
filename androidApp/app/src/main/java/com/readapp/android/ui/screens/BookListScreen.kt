package com.readapp.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.readapp.android.model.Book

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookListScreen(
    books: List<Book>,
    searchQuery: String,
    serverUrl: String,
    publicServerUrl: String,
    isLoading: Boolean,
    onRefresh: () -> Unit,
    onServerSave: (String, String?) -> Unit,
    onBookClick: (Book) -> Unit,
    sortByRecent: Boolean,
    sortAscending: Boolean,
    onSortByRecentChange: (Boolean) -> Unit,
    onSortAscendingChange: (Boolean) -> Unit,
    onSearchChange: (String) -> Unit,
    onClearCaches: () -> Unit
) {
    val server = remember { mutableStateOf(serverUrl) }
    val sortRecent = remember { mutableStateOf(sortByRecent) }
    val ascending = remember { mutableStateOf(sortAscending) }
    val query = remember { mutableStateOf(searchQuery) }
    val showSettings = rememberSaveable { mutableStateOf(false) }
    val showActions = remember { mutableStateOf(false) }

    LaunchedEffect(serverUrl) {
        server.value = serverUrl
    }

    LaunchedEffect(sortByRecent) {
        sortRecent.value = sortByRecent
    }

    LaunchedEffect(sortAscending) {
        ascending.value = sortAscending
    }

    LaunchedEffect(searchQuery) {
        query.value = searchQuery
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Surface(tonalElevation = 3.dp, color = MaterialTheme.colorScheme.background) {
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = { showSettings.value = true }) {
                            Icon(imageVector = Icons.Rounded.Settings, contentDescription = "打开设置")
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(text = "书架", style = MaterialTheme.typography.headlineMedium)
                            Text(
                                text = "搜索、刷新或排序",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        }
                        Box {
                            IconButton(onClick = { showActions.value = true }) {
                                Icon(Icons.Outlined.MoreVert, contentDescription = "更多操作")
                            }
                            DropdownMenu(
                                expanded = showActions.value,
                                onDismissRequest = { showActions.value = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text(if (ascending.value) "切换为倒序" else "切换为正序") },
                                    onClick = {
                                        ascending.value = !ascending.value
                                        onSortAscendingChange(ascending.value)
                                        showActions.value = false
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text(if (sortRecent.value) "按最新更新" else "按最近阅读") },
                                    onClick = {
                                        sortRecent.value = !sortRecent.value
                                        onSortByRecentChange(sortRecent.value)
                                        showActions.value = false
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("刷新书架") },
                                    enabled = !isLoading,
                                    onClick = {
                                        onRefresh()
                                        showActions.value = false
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("清理缓存") },
                                    enabled = !isLoading,
                                    onClick = {
                                        onClearCaches()
                                        showActions.value = false
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text(if (showSettings.value) "收起设置" else "服务器设置") },
                                    onClick = {
                                        showSettings.value = !showSettings.value
                                        showActions.value = false
                                    }
                                )
                            }
                        }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                }
            }
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = query.value,
                        onValueChange = {
                            query.value = it
                            onSearchChange(it)
                        },
                        leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                        placeholder = { Text("搜索书名或作者") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp)),
                        singleLine = true
                    )
                }
            }

            if (showSettings.value) {
                item {
                    ElevatedCard(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column {
                                    Text(text = "服务器设置", style = MaterialTheme.typography.titleMedium)
                                    Text(text = "登录与书架使用的统一地址", style = MaterialTheme.typography.bodySmall)
                                }
                                Icon(Icons.Outlined.MoreVert, contentDescription = null)
                            }
                            OutlinedTextField(
                                value = server.value,
                                onValueChange = { server.value = it },
                                label = { Text("服务器地址") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                FilledTonalButton(
                                    onClick = {
                                        onServerSave(server.value, null)
                                        showSettings.value = false
                                    },
                                    enabled = !isLoading
                                ) {
                                    Text("保存并关闭")
                                }
                                TextButton(onClick = { showSettings.value = false }) {
                                    Text("收起")
                                }
                            }
                        }
                    }
                }
            }

            item {
                Text(text = "我的书籍", style = MaterialTheme.typography.titleMedium)
            }

            items(books, key = { it.id }) { book ->
                BookListItem(book = book, onBookClick = { onBookClick(book) })
            }

            item { Spacer(modifier = Modifier.height(8.dp)) }
        }
    }
}

@Composable
private fun BookListItem(
    book: Book,
    onBookClick: () -> Unit
) {
    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .clickable { onBookClick() },
        shape = RoundedCornerShape(18.dp),
        colors = androidx.compose.material3.CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f)
        )
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val coverInitial = book.name?.firstOrNull()?.toString() ?: "书"
            Box(
                modifier = Modifier
                    .size(58.dp, 76.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center
            ) {
                Text(text = coverInitial, style = MaterialTheme.typography.titleLarge)
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = book.name ?: "未命名",
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = book.durChapterTitle?.let { "${it} ..." } ?: "快速开始阅读",
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    AssistChip(onClick = {}, label = { Text(book.author.orEmpty().ifBlank { "未知作者" }) })
                    AssistChip(onClick = {}, label = { Text(book.originName ?: book.origin ?: "自定义来源") })
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "最新 ${book.latestChapterTitle ?: "-"}",
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Icon(imageVector = Icons.Outlined.BookmarkBorder, contentDescription = null)
                }
            }
        }
    }
}
