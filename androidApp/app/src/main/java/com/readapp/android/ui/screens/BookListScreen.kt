package com.readapp.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ClearAll
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.Divider
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
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
    val publicServer = remember { mutableStateOf(publicServerUrl) }
    val sortRecent = remember { mutableStateOf(sortByRecent) }
    val ascending = remember { mutableStateOf(sortAscending) }
    val query = remember { mutableStateOf(searchQuery) }
    val showSettings = rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(serverUrl, publicServerUrl) {
        server.value = serverUrl
        publicServer.value = publicServerUrl
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
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Column {
                        Text(text = "书架", style = MaterialTheme.typography.titleLarge)
                        Text(text = "快速浏览，轻触即可阅读", style = MaterialTheme.typography.labelMedium)
                    }
                },
                actions = {
                    IconButton(onClick = onRefresh, enabled = !isLoading) {
                        Icon(Icons.Outlined.Refresh, contentDescription = "刷新书架")
                    }
                    IconButton(onClick = { showSettings.value = !showSettings.value }) {
                        Icon(Icons.Outlined.Settings, contentDescription = "服务器设置")
                    }
                }
            )
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
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
                        label = { Text("搜索书名或作者") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = sortRecent.value,
                            onClick = {
                                sortRecent.value = !sortRecent.value
                                onSortByRecentChange(sortRecent.value)
                            },
                            label = { Text("按最近阅读") }
                        )
                        FilterChip(
                            selected = ascending.value,
                            onClick = {
                                ascending.value = !ascending.value
                                onSortAscendingChange(ascending.value)
                            },
                            label = { Text(if (ascending.value) "正序" else "倒序") }
                        )
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilledTonalButton(onClick = onRefresh, enabled = !isLoading) {
                            Icon(Icons.Outlined.Refresh, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("刷新书架")
                        }
                        FilledTonalButton(onClick = onClearCaches, enabled = !isLoading) {
                            Icon(Icons.Outlined.ClearAll, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("清理缓存")
                        }
                    }
                }
            }

            if (showSettings.value) {
                item {
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Text(text = "服务器设置", style = MaterialTheme.typography.titleMedium)
                            OutlinedTextField(
                                value = server.value,
                                onValueChange = { server.value = it },
                                label = { Text("服务器地址") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                            OutlinedTextField(
                                value = publicServer.value,
                                onValueChange = { publicServer.value = it },
                                label = { Text("公网备用地址（可选）") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                FilledTonalButton(
                                    onClick = { onServerSave(server.value, publicServer.value.takeIf { it.isNotBlank() }) },
                                    enabled = !isLoading
                                ) {
                                    Text("保存服务器")
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
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = book.name ?: "未命名",
                            style = MaterialTheme.typography.titleMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(text = book.author ?: "", style = MaterialTheme.typography.bodyMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AssistChip(onClick = {}, label = { Text("当前：${book.durChapterTitle ?: "未知"}") })
                            AssistChip(onClick = {}, label = { Text("最新：${book.latestChapterTitle ?: "未知"}") })
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            FilledTonalButton(onClick = { onBookClick(book) }) { Text("继续阅读") }
                        }
                    }
                }
            }

            item { Spacer(modifier = Modifier.height(8.dp)) }
        }
    }
}
