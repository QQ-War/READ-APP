package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.readapp.R
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import com.readapp.viewmodel.SourceViewModel

@Composable
fun SourceListScreen(
    onNavigateToEdit: (String?) -> Unit = {},
    onNavigateToSearch: (BookSource) -> Unit = {},
    sourceViewModel: SourceViewModel = viewModel(factory = SourceViewModel.Factory)
) {
    val sources by sourceViewModel.sources.collectAsState()
    val isLoading by sourceViewModel.isLoading.collectAsState()
    val errorMessage by sourceViewModel.errorMessage.collectAsState()
    val searchText by sourceViewModel.searchText.collectAsState()
    val searchResults by sourceViewModel.searchResults.collectAsState()
    val isGlobalSearching by sourceViewModel.isGlobalSearching.collectAsState()

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(onClick = { onNavigateToEdit(null) }) {
                Icon(Icons.Default.Add, contentDescription = "新建书源")
            }
        }
    ) { paddingValues ->
        Column(modifier = Modifier.fillMaxSize().padding(paddingValues)) {
            OutlinedTextField(
                value = searchText,
                onValueChange = { sourceViewModel.onSearchTextChanged(it) },
                label = { Text("全局搜索书籍...") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
            )

            if (searchText.isBlank()) {
                SourceListViewContent(
                    sources = sources,
                    isLoading = isLoading,
                    errorMessage = errorMessage,
                    onNavigateToEdit = onNavigateToEdit,
                    onNavigateToSearch = onNavigateToSearch,
                    onToggle = { sourceViewModel.toggleSource(it) },
                    onDelete = { sourceViewModel.deleteSource(it) },
                    onRefresh = { sourceViewModel.fetchSources() }
                )
            } else {
                GlobalSearchViewContent(
                    searchResults = searchResults,
                    isGlobalSearching = isGlobalSearching,
                    onAddBookToBookshelf = { sourceViewModel.saveBookToBookshelf(it) }
                )
            }
        }
    }
}

@Composable
fun SourceListViewContent(
    sources: List<BookSource>,
    isLoading: Boolean,
    errorMessage: String?,
    onNavigateToEdit: (String?) -> Unit,
    onNavigateToSearch: (BookSource) -> Unit,
    onToggle: (BookSource) -> Unit,
    onDelete: (BookSource) -> Unit,
    onRefresh: () -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        if (isLoading && sources.isEmpty()) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
        } else if (errorMessage != null) {
            Text(
                text = errorMessage,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.align(Alignment.Center)
            )
        } else {
            LazyColumn(modifier = Modifier.padding(8.dp)) {
                items(sources, key = { it.bookSourceUrl }) { source ->
                    BookSourceItem(
                        source = source,
                        onToggle = { onToggle(source) },
                        onDelete = { onDelete(source) },
                        onClick = { onNavigateToEdit(source.bookSourceUrl) },
                        onSearchClick = { onNavigateToSearch(source) }
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                }
            }
        }
    }
}

@Composable
fun GlobalSearchViewContent(
    searchResults: List<Book>,
    isGlobalSearching: Boolean,
    onAddBookToBookshelf: (Book) -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        if (isGlobalSearching && searchResults.isEmpty()) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
        } else if (searchResults.isEmpty()) {
            Text(
                text = "没有找到相关书籍。",
                modifier = Modifier.align(Alignment.Center),
                color = Color.Gray
            )
        } else {
            LazyColumn {
                items(searchResults) { book ->
                    BookSearchResultItem(book = book, onAdd = { onAddBookToBookshelf(book) })
                }
            }
        }
    }
}

@Composable
fun BookSourceItem(
    source: BookSource,
    onToggle: () -> Unit,
    onDelete: () -> Unit,
    onClick: () -> Unit,
    onSearchClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxSize()
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (source.enabled) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = source.bookSourceName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (source.enabled) MaterialTheme.colorScheme.onSurface else Color.Gray
                )
                Spacer(modifier = Modifier.height(4.dp))

                if (!source.bookSourceGroup.isNullOrBlank()) {
                    Text(
                        text = "分组: ${source.bookSourceGroup}",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }

                Text(
                    text = source.bookSourceUrl,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )

                if (!source.bookSourceComment.isNullOrBlank()) {
                    Text(
                        text = source.bookSourceComment,
                        style = MaterialTheme.typography.bodySmall,
                        fontStyle = FontStyle.Italic,
                        color = Color.Gray,
                        maxLines = 2
                    )
                }
            }
            
            Spacer(modifier = Modifier.width(8.dp))
            
            Column(horizontalAlignment = Alignment.End) {
                Switch(
                    checked = source.enabled,
                    onCheckedChange = { onToggle() }
                )
                Row {
                    IconButton(onClick = onSearchClick) {
                        Icon(
                            imageVector = Icons.Default.Search,
                            contentDescription = "搜索",
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                    IconButton(onClick = onDelete) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "删除",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun BookSearchResultItem(book: Book, onAdd: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier.padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AsyncImage(
                model = book.coverUrl,
                contentDescription = book.name,
                placeholder = painterResource(id = R.drawable.ic_launcher_background), // Fallback image
                error = painterResource(id = R.drawable.ic_launcher_background), // Fallback image
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(60.dp, 80.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(text = book.name ?: "未知书名", style = MaterialTheme.typography.titleMedium)
                Text(text = book.author ?: "未知作者", style = MaterialTheme.typography.bodySmall)
                Text(text = book.intro ?: "", style = MaterialTheme.typography.bodySmall, maxLines = 2)
                book.sourceDisplayName?.let {
                    Text(text = "来源: $it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                }
            }
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = "Add to Bookshelf")
            }
        }
    }
}