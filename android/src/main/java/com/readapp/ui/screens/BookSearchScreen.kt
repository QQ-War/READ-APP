package com.readapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.readapp.data.model.Book
import com.readapp.viewmodel.BookSearchUiState
import com.readapp.viewmodel.BookSearchViewModel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull

import androidx.compose.material.icons.filled.Clear
import androidx.compose.ui.platform.LocalFocusManager
import com.readapp.Screen
import com.readapp.data.model.BookSource
import com.readapp.viewmodel.BookViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookSearchScreen(
    viewModel: BookSearchViewModel,
    mainNavController: NavController,
    onBack: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val searchText by viewModel.searchText.collectAsState()
    val listState = rememberLazyListState()
    val latestUiState by rememberUpdatedState(uiState)
    val focusManager = LocalFocusManager.current
    val bookViewModel: BookViewModel = viewModel(factory = BookViewModel.Factory)

    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index }
            .filterNotNull()
            .distinctUntilChanged()
            .collect { lastVisibleIndex ->
                val state = latestUiState
                if (state is BookSearchUiState.Success &&
                    lastVisibleIndex >= state.books.lastIndex &&
                    viewModel.canLoadMoreState &&
                    !viewModel.isLoading
                ) {
                    viewModel.performSearch(isNewSearch = false)
                }
            }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = "搜索: ${viewModel.bookSource.bookSourceName}") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            Surface(tonalElevation = 2.dp, shadowElevation = 2.dp) {
                OutlinedTextField(
                    value = searchText,
                    onValueChange = {
                        viewModel.onSearchTextChanged(it)
                        viewModel.performSearch()
                    },
                    label = { Text("搜索书籍...") },
                    singleLine = true,
                    trailingIcon = {
                        if (searchText.isNotEmpty()) {
                            IconButton(onClick = { 
                                viewModel.onSearchTextChanged("")
                                focusManager.clearFocus()
                            }) {
                                Icon(Icons.Default.Clear, "清除")
                            }
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    shape = RoundedCornerShape(12.dp)
                )
            }

            when (val state = uiState) {
                is BookSearchUiState.Loading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                is BookSearchUiState.Error -> {
                    Text(text = state.message, modifier = Modifier.padding(8.dp))
                }
                is BookSearchUiState.Success -> {
                    LazyColumn(state = listState) {
                        items(state.books) { book ->
                            BookSearchItem(book = book, onClick = {
                                bookViewModel.selectBook(book)
                                mainNavController.navigate(Screen.BookDetail.route)
                            })
                        }
                        if (viewModel.isLoading) {
                            item {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    horizontalArrangement = Arrangement.Center
                                ) {
                                    CircularProgressIndicator()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun BookSearchItem(book: Book, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp)
            .clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier.padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AsyncImage(
                model = book.coverUrl,
                contentDescription = book.name,
                placeholder = painterResource(id = android.R.drawable.ic_menu_report_image),
                error = painterResource(id = android.R.drawable.ic_menu_report_image),
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(60.dp, 80.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(text = book.name ?: "未知书名", style = MaterialTheme.typography.titleMedium)
                Text(text = book.author ?: "未知作者", style = MaterialTheme.typography.bodySmall)
                Text(text = book.intro ?: "", style = MaterialTheme.typography.bodySmall, maxLines = 2)
            }
        }
    }
}
