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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.ExpandLess
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
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.google.gson.Gson
import com.readapp.data.model.Book
import com.readapp.data.model.BookSource
import com.readapp.viewmodel.SourceViewModel
import kotlinx.coroutines.launch

@Composable
fun SourceListScreen(
    onNavigateToEdit: (String?) -> Unit = {},
    onNavigateToSearch: (BookSource) -> Unit = {},
    onNavigateToExplore: (String, String, String, String) -> Unit = { _, _, _, _ -> },
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
                label = { Text("搜索/过滤书源...") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
            )

            val expandedIds = remember { mutableStateMapOf<String, Boolean>() }
            val exploreKinds = remember { mutableStateMapOf<String, List<com.readapp.data.model.BookSource.ExploreKind>>() }
            val loadingExplores = remember { mutableStateMapOf<String, Boolean>() }
            val scope = rememberCoroutineScope()
            val gson = remember { Gson() }

            val filteredSources = if (searchText.isEmpty()) {
                sources
            } else {
                sources.filter { 
                    it.bookSourceName.contains(searchText, ignoreCase = true) ||
                    it.bookSourceUrl.contains(searchText, ignoreCase = true) ||
                    (it.bookSourceGroup?.contains(searchText, ignoreCase = true) ?: false)
                }
            }

            SourceListViewContent(
                sources = filteredSources,
                isLoading = isLoading,
                errorMessage = errorMessage,
                expandedIds = expandedIds,
                exploreKinds = exploreKinds,
                loadingExplores = loadingExplores,
                onToggleExpand = { source ->
                    val current = expandedIds[source.bookSourceUrl] ?: false
                    expandedIds[source.bookSourceUrl] = !current
                    if (!current && exploreKinds[source.bookSourceUrl] == null) {
                        scope.launch {
                            loadingExplores[source.bookSourceUrl] = true
                            val foundJson = sourceViewModel.fetchExploreKinds(source.bookSourceUrl)
                            if (foundJson != null) {
                                try {
                                    val kinds = gson.fromJson(foundJson, Array<com.readapp.data.model.BookSource.ExploreKind>::class.java).toList()
                                    exploreKinds[source.bookSourceUrl] = kinds
                                } catch (e: Exception) {}
                            }
                            loadingExplores[source.bookSourceUrl] = false
                        }
                    }
                },
                onExploreClick = { source, kind ->
                    onNavigateToExplore(source.bookSourceUrl, source.bookSourceName, kind.url, kind.title)
                },
                onNavigateToEdit = onNavigateToEdit,
                onNavigateToSearch = onNavigateToSearch,
                onToggle = { sourceViewModel.toggleSource(it) },
                onDelete = { sourceViewModel.deleteSource(it) },
                onRefresh = { sourceViewModel.fetchSources() }
            )
        }
    }
}

@Composable
fun SourceListViewContent(
    sources: List<BookSource>,
    isLoading: Boolean,
    errorMessage: String?,
    expandedIds: Map<String, Boolean>,
    exploreKinds: Map<String, List<BookSource.ExploreKind>>,
    loadingExplores: Map<String, Boolean>,
    onToggleExpand: (BookSource) -> Unit,
    onExploreClick: (BookSource, BookSource.ExploreKind) -> Unit,
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
                        isExpanded = expandedIds[source.bookSourceUrl] ?: false,
                        exploreKinds = exploreKinds[source.bookSourceUrl],
                        isExploreLoading = loadingExplores[source.bookSourceUrl] ?: false,
                        onToggleExpand = { onToggleExpand(source) },
                        onExploreClick = { kind -> onExploreClick(source, kind) },
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
fun BookSourceItem(
    source: BookSource,
    isExpanded: Boolean,
    exploreKinds: List<BookSource.ExploreKind>?,
    isExploreLoading: Boolean,
    onToggleExpand: () -> Unit,
    onExploreClick: (BookSource.ExploreKind) -> Unit,
    onToggle: () -> Unit,
    onDelete: () -> Unit,
    onClick: () -> Unit,
    onSearchClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (source.enabled) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column {
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
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Switch(
                            checked = source.enabled,
                            onCheckedChange = { onToggle() },
                            modifier = Modifier.scale(0.8f)
                        )
                        IconButton(onClick = onToggleExpand) {
                            Icon(if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null)
                        }
                    }
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

            if (isExpanded) {
                if (isExploreLoading) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth().height(2.dp))
                }
                
                if (exploreKinds != null) {
                    LazyRow(
                        modifier = Modifier.padding(bottom = 12.dp),
                        contentPadding = PaddingValues(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(exploreKinds) { kind ->
                            SuggestionChip(
                                onClick = { onExploreClick(kind) },
                                label = { Text(kind.title) }
                            )
                        }
                    }
                } else if (!isExploreLoading) {
                    Text(
                        "该书源暂无发现配置", 
                        style = MaterialTheme.typography.labelSmall, 
                        color = Color.Gray,
                        modifier = Modifier.padding(start = 16.dp, bottom = 12.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun BookSearchResultRow(
    book: Book, 
    onAdd: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
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
                placeholder = painterResource(id = android.R.drawable.ic_menu_report_image), // Fallback image
                error = painterResource(id = android.R.drawable.ic_menu_report_image), // Fallback image
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
