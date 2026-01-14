// BookshelfScreen.kt - 书架页面（带右上角设置按钮与下拉刷新）
@file:OptIn(ExperimentalMaterialApi::class, ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)

package com.readapp.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import coil.compose.AsyncImage
import com.readapp.Screen
import com.readapp.data.model.Book
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors
import com.readapp.viewmodel.BookViewModel

@Composable
fun BookshelfScreen(
    mainNavController: NavController,
    bookViewModel: BookViewModel
) {
    val books by bookViewModel.books.collectAsState()
    val isLoading by bookViewModel.isLoading.collectAsState()
    val onlineResults by bookViewModel.onlineSearchResults.collectAsState()
    val isOnlineSearching by bookViewModel.isOnlineSearching.collectAsState()
    val searchOnlineEnabled by bookViewModel.searchSourcesFromBookshelf.collectAsState()
    val preferredSources by bookViewModel.preferredSearchSourceUrls.collectAsState()
    val availableSources by bookViewModel.availableBookSources.collectAsState()
    
    var searchQuery by remember { mutableStateOf("") }
    var showSearchConfig by remember { mutableStateOf(false) }
    
    val context = LocalContext.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    LaunchedEffect(Unit) {
        bookViewModel.refreshBooks()
    }

    val refreshState = rememberPullRefreshState(
        refreshing = isLoading,
        onRefresh = { bookViewModel.refreshBooks() }
    )

    val importBookLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let {
            bookViewModel.importBook(it)
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.VolumeUp,
                            contentDescription = null,
                            tint = MaterialTheme.customColors.gradientStart,
                            modifier = Modifier.size(28.dp)
                        )
                        Text(
                            text = "ReadApp",
                            style = MaterialTheme.typography.headlineSmall,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { showSearchConfig = true }) {
                        Icon(
                            imageVector = Icons.Default.Tune,
                            contentDescription = "搜索设置"
                        )
                    }
                    IconButton(onClick = { importBookLauncher.launch("*/*") }) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = "导入书籍"
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .pullRefresh(refreshState)
        ) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = AppDimens.PaddingMedium),
                verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium),
                contentPadding = PaddingValues(bottom = AppDimens.PaddingLarge)
            ) {
                item {
                    Spacer(modifier = Modifier.height(AppDimens.PaddingMedium))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SearchBar(
                            query = searchQuery,
                            onQueryChange = {
                                searchQuery = it
                                bookViewModel.searchBooks(it)
                            },
                            onConfigClick = { showSearchConfig = true },
                            modifier = Modifier.weight(1f)
                        )
                        if (searchQuery.isNotEmpty()) {
                            TextButton(onClick = {
                                searchQuery = ""
                                bookViewModel.searchBooks("")
                                focusManager.clearFocus()
                                keyboardController?.hide()
                            }) {
                                Text("取消")
                            }
                        }
                    }
                }

                if (searchQuery.isEmpty()) {
                    if (books.isEmpty()) {
                        item { EmptyBookshelf() }
                    } else {
                        items(books) { book ->
                            BookRow(
                                book = book,
                                onCoverClick = {
                                    bookViewModel.selectBook(book)
                                    mainNavController.navigate(Screen.BookDetail.route)
                                },
                                onInfoClick = { 
                                    bookViewModel.selectBook(book)
                                    mainNavController.navigate(Screen.Reading.route)
                                }
                            )
                        }
                    }
                } else {
                    // 搜索结果
                    if (books.isNotEmpty()) {
                        item { SectionHeader("书架内匹配") }
                        items(books) { book ->
                            BookRow(
                                book = book,
                                onCoverClick = {
                                    bookViewModel.selectBook(book)
                                    mainNavController.navigate(Screen.BookDetail.route)
                                },
                                onInfoClick = { 
                                    bookViewModel.selectBook(book)
                                    mainNavController.navigate(Screen.Reading.route)
                                }
                            )
                        }
                    }
                    
                    if (searchOnlineEnabled) {
                        item { SectionHeader("全网搜索结果") }
                        if (isOnlineSearching) {
                            item { Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp)) } }
                        } else if (onlineResults.isEmpty()) {
                            item { Text("未找到相关书籍", style = MaterialTheme.typography.bodySmall, color = Color.Gray, modifier = Modifier.padding(16.dp)) }
                        } else {
                            items(onlineResults) { book ->
                                BookSearchResultRow(
                                    book = book,
                                    onAdd = { bookViewModel.saveBookToBookshelf(book) },
                                    modifier = Modifier.clickable {
                                        bookViewModel.selectBook(book)
                                        mainNavController.navigate(Screen.BookDetail.route)
                                    }
                                )
                            }
                        }
                    }
                }
            }

            PullRefreshIndicator(
                refreshing = isLoading,
                state = refreshState,
                modifier = Modifier.align(Alignment.TopCenter)
            )
        }
    }

    if (showSearchConfig) {
        SearchConfigDialog(
            enabled = searchOnlineEnabled,
            onEnabledChange = { bookViewModel.updateSearchSourcesFromBookshelf(it) },
            availableSources = availableSources.filter { it.enabled },
            preferredUrls = preferredSources,
            onToggleSource = { bookViewModel.togglePreferredSearchSource(it) },
            onClearAll = { bookViewModel.clearPreferredSearchSources() },
            onDismiss = { showSearchConfig = false }
        )
    }
}

@Composable
private fun EmptyBookshelf() {
    Box(
        modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Book,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.customColors.textSecondary
            )
            Text(
                text = "暂无书籍",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.customColors.textSecondary
            )
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(vertical = 8.dp)
    )
}

@Composable
private fun SearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    onConfigClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = modifier,
        placeholder = {
            Text(
                text = "搜索书籍或作者...",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.customColors.textSecondary
            )
        },
        leadingIcon = {
            Icon(
                imageVector = Icons.Default.Search,
                contentDescription = "搜索",
                tint = MaterialTheme.customColors.textSecondary
            )
        },
        colors = OutlinedTextFieldDefaults.colors(
            unfocusedBorderColor = MaterialTheme.customColors.border,
            focusedBorderColor = MaterialTheme.colorScheme.primary
        ),
        shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
        singleLine = true
    )
}

@Composable
private fun SearchConfigDialog(
    enabled: Boolean,
    onEnabledChange: (Boolean) -> Unit,
    availableSources: List<com.readapp.data.model.BookSource>,
    preferredUrls: Set<String>,
    onToggleSource: (String) -> Unit,
    onClearAll: () -> Unit,
    onDismiss: () -> Unit
) {
    var filterQuery by remember { mutableStateOf("") }
    val filteredSources = remember(filterQuery, availableSources) {
        if (filterQuery.isBlank()) availableSources
        else availableSources.filter { it.bookSourceName.contains(filterQuery, ignoreCase = true) }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("搜索设置") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = enabled, onCheckedChange = onEnabledChange)
                    Text("搜索时包含全网书源")
                }
                if (enabled) {
                    Divider()
                    OutlinedTextField(
                        value = filterQuery,
                        onValueChange = { filterQuery = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("搜索书源名称...") },
                        leadingIcon = { Icon(Icons.Default.Search, null) },
                        singleLine = true
                    )
                    Text("选择优先搜索源", style = MaterialTheme.typography.labelMedium)
                    LazyColumn(Modifier.heightIn(max = 300.dp)) {
                        if (filterQuery.isBlank()) {
                            item {
                                ListItem(
                                    headlineContent = { Text(if (preferredUrls.isEmpty()) "✓ 全部启用源" else "使用全部启用源") },
                                    modifier = Modifier.clickable { onClearAll() }
                                )
                            }
                        }
                        items(filteredSources) { source ->
                            ListItem(
                                headlineContent = { Text(source.bookSourceName) },
                                trailingContent = {
                                    if (preferredUrls.contains(source.bookSourceUrl)) {
                                        Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                                    }
                                },
                                modifier = Modifier.clickable { onToggleSource(source.bookSourceUrl) }
                            )
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("完成") } }
    )
}

@Composable
private fun BookRow(
    book: Book,
    onCoverClick: () -> Unit,
    onInfoClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth().height(120.dp),
        shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.customColors.cardBackground),
        elevation = CardDefaults.cardElevation(defaultElevation = AppDimens.ElevationSmall)
    ) {
        Row(
            modifier = Modifier.fillMaxSize().padding(AppDimens.PaddingMedium),
            horizontalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium)
        ) {
            BookCover(
                coverUrl = book.coverUrl,
                modifier = Modifier.fillMaxHeight().aspectRatio(3f / 4f).clickable(onClick = onCoverClick)
            )

            Column(
                modifier = Modifier.fillMaxHeight().weight(1f).clickable(onClick = onInfoClick),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(text = book.name ?: "未知书名", style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(text = book.author ?: "未知作者", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.customColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }

                ReadingProgress(
                    progress = (book.durChapterIndex?.toFloat() ?: 0f) / (book.totalChapters?.toFloat()?.coerceAtLeast(1f) ?: 1f),
                    currentChapter = (book.durChapterIndex ?: 0) + 1,
                    totalChapters = book.totalChapters ?: 0
                )
            }
        }
    }
}

@Composable
private fun BookCover(
    coverUrl: String?,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(AppDimens.CornerRadiusMedium))
            .background(brush = Brush.linearGradient(colors = listOf(MaterialTheme.customColors.gradientStart, MaterialTheme.customColors.gradientEnd))),
        contentAlignment = Alignment.Center
    ) {
        if (!coverUrl.isNullOrBlank()) {
            AsyncImage(model = coverUrl, contentDescription = "书籍封面", contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Icon(Icons.Default.Book, null, modifier = Modifier.size(48.dp), tint = Color.White.copy(alpha = 0.5f))
        }
    }
}

@Composable
private fun ReadingProgress(
    progress: Float,
    currentChapter: Int,
    totalChapters: Int
) {
    Column {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(text = "进度 ${(progress * 100).toInt()}%", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.customColors.textSecondary)
            Text(text = "$currentChapter/$totalChapters", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.customColors.textSecondary)
        }
        Spacer(modifier = Modifier.height(4.dp))
        LinearProgressIndicator(
            progress = progress.coerceIn(0f, 1f),
            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
            color = MaterialTheme.customColors.gradientStart,
            trackColor = MaterialTheme.customColors.border
        )
    }
}
