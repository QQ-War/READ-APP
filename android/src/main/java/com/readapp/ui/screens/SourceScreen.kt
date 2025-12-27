package com.readapp.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.readapp.data.model.BookSource
import com.readapp.viewmodel.SourceViewModel

@Composable
fun SourceListScreen(
    sourceViewModel: SourceViewModel = viewModel(factory = SourceViewModel.Factory)
) {
    val sources by sourceViewModel.sources.collectAsState()
    val isLoading by sourceViewModel.isLoading.collectAsState()
    val errorMessage by sourceViewModel.errorMessage.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        if (isLoading && sources.isEmpty()) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
        } else if (errorMessage != null) {
            Text(
                text = errorMessage!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.align(Alignment.Center)
            )
        } else {
            LazyColumn(modifier = Modifier.padding(8.dp)) {
                items(sources, key = { it.bookSourceUrl }) { source ->
                    BookSourceItem(source = source)
                    Spacer(modifier = Modifier.height(8.dp))
                }
            }
        }
    }
}

@Composable
fun BookSourceItem(source: BookSource) {
    Card(
        modifier = Modifier.fillMaxSize(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (source.enabled) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
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
    }
}
