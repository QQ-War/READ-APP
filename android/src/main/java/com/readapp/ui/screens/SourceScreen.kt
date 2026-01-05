@file:OptIn(ExperimentalMaterialApi::class, ExperimentalMaterial3Api::class)

package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.TextButton
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
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
    
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    val keyboardController = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current

    val pullRefreshState = rememberPullRefreshState(
        refreshing = isLoading,
        onRefresh = { sourceViewModel.fetchSources() }
    )

    var showImportUrlDialog by remember { mutableStateOf(false) }
    var importUrl by remember { mutableStateOf("") }

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: android.net.Uri? ->
        uri?.let {
            scope.launch {
                val content = context.contentResolver.openInputStream(it)?.bufferedReader()?.use { it.readText() }
                if (!content.isNullOrBlank()) {
                    sourceViewModel.saveSource(content)
                    sourceViewModel.fetchSources()
                }
            }
        }
    }

    Scaffold(
        topBar = {
            Surface(
                tonalElevation = 3.dp,
                shadowElevation = 3.dp
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = searchText,
                        onValueChange = { sourceViewModel.onSearchTextChanged(it) },
                        placeholder = { Text("搜索书源...") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        leadingIcon = { Icon(Icons.Default.Search, null) },
                        shape = RoundedCornerShape(12.dp)
                    )
                    
                    if (searchText.isNotEmpty()) {
                        TextButton(
                            onClick = {
                                sourceViewModel.onSearchTextChanged("")
                                focusManager.clearFocus()
                                keyboardController?.hide()
                            },
                            modifier = Modifier.padding(start = 8.dp)
                        ) {
                            Text("取消")
                        }
                    }
                }
            }
        },
        floatingActionButton = {
            var showMenu by remember { mutableStateOf(false) }
            Column(horizontalAlignment = Alignment.End) {
                if (showMenu) {
                    FloatingActionButton(
                        onClick = { filePickerLauncher.launch("*/*"); showMenu = false },
                        modifier = Modifier.padding(bottom = 8.dp),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer
                    ) { Icon(Icons.Default.Folder, "本地导入") }
                    FloatingActionButton(
                        onClick = { showImportUrlDialog = true; showMenu = false },
                        modifier = Modifier.padding(bottom = 8.dp),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer
                    ) { Icon(Icons.Default.Link, "网络导入") }
                }
                FloatingActionButton(onClick = { if (showMenu) onNavigateToEdit(null) else showMenu = true }) {
                    Icon(if (showMenu) Icons.Default.Edit else Icons.Default.Add, contentDescription = "新建书源")
                }
            }
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .pullRefresh(pullRefreshState)
        ) {
            val expandedIds = remember { mutableStateMapOf<String, Boolean>() }
            val exploreKinds = remember { mutableStateMapOf<String, List<com.readapp.data.model.BookSource.ExploreKind>>() }
            val loadingExplores = remember { mutableStateMapOf<String, Boolean>() }
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
                onSourceClick = { onNavigateToEdit(it.bookSourceUrl) },
                onToggleSource = { sourceViewModel.toggleSource(it) },
                onDeleteSource = { sourceViewModel.deleteSource(it) },
                onSearchClick = { onNavigateToSearch(it) }
            )

            PullRefreshIndicator(
                refreshing = isLoading,
                state = pullRefreshState,
                modifier = Modifier.align(Alignment.TopCenter)
            )

            if (showImportUrlDialog) {
                AlertDialog(
                    onDismissRequest = { showImportUrlDialog = false },
                    title = { Text("网络导入") },
                    text = {
                        OutlinedTextField(
                            value = importUrl,
                            onValueChange = { importUrl = it },
                            label = { Text("输入书源 URL") },
                            modifier = Modifier.fillMaxWidth()
                        )
                    },
                    confirmButton = {
                        Button(onClick = {
                            scope.launch {
                                val content = fetchUrlContent(importUrl)
                                if (content != null) {
                                    sourceViewModel.saveSource(content)
                                    sourceViewModel.fetchSources()
                                }
                                showImportUrlDialog = false
                                importUrl = ""
                            }
                        }) { Text("导入") }
                    },
                    dismissButton = { TextButton(onClick = { showImportUrlDialog = false }) { Text("取消") } }
                )
            }
        }
    }
}

private suspend fun fetchUrlContent(url: String): String? {
    return kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        runCatching {
            val client = okhttp3.OkHttpClient()
            val request = okhttp3.Request.Builder().url(url).build()
            client.newCall(request).execute().use { it.body?.string() }
        }.getOrNull()
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SourceListViewContent(
    sources: List<BookSource>,
    isLoading: Boolean,
    errorMessage: String?,
    expandedIds: SnapshotStateMap<String, Boolean>,
    exploreKinds: SnapshotStateMap<String, List<com.readapp.data.model.BookSource.ExploreKind>>,
    loadingExplores: SnapshotStateMap<String, Boolean>,
    onToggleExpand: (BookSource) -> Unit,
    onExploreClick: (BookSource, com.readapp.data.model.BookSource.ExploreKind) -> Unit,
    onSourceClick: (BookSource) -> Unit,
    onToggleSource: (BookSource) -> Unit,
    onDeleteSource: (BookSource) -> Unit,
    onSearchClick: (BookSource) -> Unit
) {
    val expandedGroups = remember { mutableStateMapOf<String, Boolean>() }
    val groupedSources = remember(sources) {
        sources.groupBy { it.bookSourceGroup?.takeIf { g -> g.isNotBlank() } ?: "未分组" }
            .toSortedMap()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        if (isLoading && sources.isEmpty()) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
        } else if (errorMessage != null && sources.isEmpty()) {
            Text(
                text = errorMessage,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.align(Alignment.Center).padding(16.dp)
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 80.dp)
            ) {
                groupedSources.forEach { (groupName, groupSources) ->
                    val isGroupExpanded = expandedGroups[groupName] ?: false
                    
                    item(key = "group_" + groupName) {
                        Surface(
                            onClick = { expandedGroups[groupName] = !isGroupExpanded },
                            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        text = groupName,
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(
                                        text = "(" + groupSources.size + ")",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.secondary
                                    )
                                }
                                Icon(
                                    imageVector = if (isGroupExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                                    contentDescription = null,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        }
                    }

                    if (isGroupExpanded) {
                        items(groupSources, key = { it.bookSourceUrl }) { source ->
                            SourceItem(
                                source = source,
                                isExpanded = expandedIds[source.bookSourceUrl] ?: false,
                                exploreKinds = exploreKinds[source.bookSourceUrl],
                                isLoadingExplore = loadingExplores[source.bookSourceUrl] ?: false,
                                onToggleExpand = { onToggleExpand(source) },
                                onExploreClick = { kind -> onExploreClick(source, kind) },
                                onClick = { onSourceClick(source) },
                                onToggle = { onToggleSource(source) },
                                onDelete = { onDeleteSource(source) },
                                onSearch = { onSearchClick(source) }
                            )
                            Divider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SourceItem(
    source: BookSource,
    isExpanded: Boolean,
    exploreKinds: List<com.readapp.data.model.BookSource.ExploreKind>?,
    isLoadingExplore: Boolean,
    onToggleExpand: () -> Unit,
    onExploreClick: (com.readapp.data.model.BookSource.ExploreKind) -> Unit,
    onClick: () -> Unit,
    onToggle: () -> Unit,
    onDelete: () -> Unit,
    onSearch: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 左侧：点击展开/收起频道
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable(onClick = onToggleExpand)
            ) {
                Text(
                    text = source.bookSourceName,
                    style = MaterialTheme.typography.titleMedium,
                    color = if (source.enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline
                )
                Text(
                    text = source.bookSourceUrl,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onSearch) {
                    Icon(Icons.Default.Search, contentDescription = "搜索", tint = MaterialTheme.colorScheme.primary)
                }
                
                Switch(
                    checked = source.enabled,
                    onCheckedChange = { onToggle() },
                    modifier = Modifier.scale(0.8f)
                )
                
                // 编辑按钮 (原来中间的箭头改到这里)
                IconButton(onClick = onClick) {
                    Icon(
                        imageVector = Icons.Default.ChevronRight,
                        contentDescription = "编辑",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }
                
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = "删除", tint = MaterialTheme.colorScheme.error)
                }
            }
        }

        if (isExpanded) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, bottom = 12.dp)
            ) {
                if (isLoadingExplore) {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp).align(Alignment.Center))
                } else if (!exploreKinds.isNullOrEmpty()) {
                    androidx.compose.foundation.lazy.LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(exploreKinds) { kind ->
                            SuggestionChip(
                                onClick = { onExploreClick(kind) },
                                label = { Text(kind.title, style = MaterialTheme.typography.labelSmall) }
                            )
                        }
                    }
                } else {
                    Text(
                        text = "该书源暂无发现配置",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline
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
        }
    }
}
