package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.readapp.Screen
import com.readapp.data.model.Book
import com.readapp.viewmodel.SourceViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SourceExploreScreen(
    sourceUrl: String,
    sourceName: String,
    ruleFindUrl: String,
    categoryName: String,
    onNavigateToDetail: () -> Unit,
    onNavigateBack: () -> Unit,
    sourceViewModel: SourceViewModel = viewModel(factory = SourceViewModel.Factory),
    bookViewModel: com.readapp.viewmodel.BookViewModel = viewModel(factory = com.readapp.viewmodel.BookViewModel.Factory)
) {
    val exploreKey = remember(sourceUrl, ruleFindUrl) { "$sourceUrl|$ruleFindUrl" }
    val exploreState by sourceViewModel.getExploreState(exploreKey).collectAsState()

    LaunchedEffect(exploreKey) {
        sourceViewModel.loadExploreIfNeeded(exploreKey, sourceUrl, ruleFindUrl)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { 
                    Column {
                        Text(categoryName, style = MaterialTheme.typography.titleMedium)
                        Text(sourceName, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            if (exploreState.isLoading && exploreState.books.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    itemsIndexed(exploreState.books) { index, book ->
                        BookSearchResultRow(
                            book = book.copy(sourceDisplayName = sourceName),
                            onAdd = { sourceViewModel.saveBookToBookshelf(book) },
                            modifier = Modifier.clickable {
                                bookViewModel.selectBook(book)
                                onNavigateToDetail()
                            }
                        )
                        Divider(modifier = Modifier.padding(horizontal = 16.dp))
                        
                        // Load more
                        if (index == exploreState.books.lastIndex && exploreState.canLoadMore && !exploreState.isLoading) {
                            LaunchedEffect(exploreKey) {
                                sourceViewModel.loadMoreExplore(exploreKey, sourceUrl, ruleFindUrl)
                            }
                        }
                    }
                    
                    if (exploreState.isLoading && exploreState.books.isNotEmpty()) {
                        item {
                            Box(modifier = Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(modifier = Modifier.size(24.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}
