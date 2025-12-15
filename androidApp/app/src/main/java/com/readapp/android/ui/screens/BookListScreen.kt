package com.readapp.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.readapp.android.model.Book

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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(text = "书架", style = MaterialTheme.typography.titleLarge)

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = onRefresh, enabled = !isLoading) { Text("刷新书架") }
            Button(onClick = onClearCaches, enabled = !isLoading) { Text("清理缓存") }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            Text(text = "最近阅读排序")
            Switch(checked = sortRecent.value, onCheckedChange = { checked ->
                sortRecent.value = checked
                onSortByRecentChange(checked)
            })
            Text(text = if (ascending.value) "正序" else "倒序")
            Switch(checked = ascending.value, onCheckedChange = { checked ->
                ascending.value = checked
                onSortAscendingChange(checked)
            })
        }

        OutlinedTextField(
            value = query.value,
            onValueChange = {
                query.value = it
                onSearchChange(it)
            },
            label = { Text("搜索书名或作者") },
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = server.value,
            onValueChange = { server.value = it },
            label = { Text("服务器地址") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = publicServer.value,
            onValueChange = { publicServer.value = it },
            label = { Text("公网备用地址（可选）") },
            modifier = Modifier.fillMaxWidth()
        )
        Button(
            onClick = { onServerSave(server.value, publicServer.value.takeIf { it.isNotBlank() }) },
            enabled = !isLoading
        ) { Text("保存服务器设置") }

        Divider()

        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(books, key = { it.id }) { book ->
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(text = book.name ?: "未命名", style = MaterialTheme.typography.titleMedium)
                    Text(text = book.author ?: "")
                    Text(text = "当前章节：${book.durChapterTitle ?: "未知"}")
                    Text(text = "最新章节：${book.latestChapterTitle ?: "未知"}")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onBookClick(book) }) { Text("阅读") }
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
                Divider()
            }
        }
    }
}
