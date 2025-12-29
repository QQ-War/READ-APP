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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookSearchScreen(
    viewModel: BookSearchViewModel,
    onBack: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val searchText by viewModel.searchText.collectAsState()
    val listState = rememberLazyListState()
    val latestUiState by rememberUpdatedState(uiState)

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
                title = { Text(text = "Search in ${viewModel.bookSource.bookSourceName}") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            OutlinedTextField(
                value = searchText,
                onValueChange = {
                    viewModel.onSearchTextChanged(it)
                    viewModel.performSearch()
                },
                label = { Text("Search Books") },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp)
            )

            when (val state = uiState) {
                is BookSearchUiState.Loading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                }
                is BookSearchUiState.Error -> {
                    Text(text = state.message, modifier = Modifier.padding(8.dp))
                }
                is BookSearchUiState.Success -> {
                    LazyColumn(state = listState) {
                        items(state.books) { book ->
                            BookSearchItem(book = book, onAdd = {
                                viewModel.addBookToBookshelf(book)
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
fun BookSearchItem(book: Book, onAdd: () -> Unit) {
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
                placeholder = painterResource(id = android.R.drawable.ic_menu_report_image),
                error = painterResource(id = android.R.drawable.ic_menu_report_image),
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(60.dp, 80.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(text = book.name ?: "Unknown Title", style = MaterialTheme.typography.titleMedium)
                Text(text = book.author ?: "Unknown Author", style = MaterialTheme.typography.bodySmall)
                Text(text = book.intro ?: "", style = MaterialTheme.typography.bodySmall, maxLines = 2)
            }
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = "Add to Bookshelf")
            }
        }
    }
}
