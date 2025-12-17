// BookshelfScreen.kt - 书架页面
package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.readapp.data.model.Book
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@Composable
fun BookshelfScreen(
    books: List<Book>,
    onBookClick: (Book) -> Unit,
    onSearchQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var searchQuery by remember { mutableStateOf("") }
    
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(AppDimens.PaddingMedium)
    ) {
        // 搜索栏
        SearchBar(
            query = searchQuery,
            onQueryChange = { 
                searchQuery = it
                onSearchQueryChange(it)
            },
            modifier = Modifier.fillMaxWidth()
        )
        
        Spacer(modifier = Modifier.height(AppDimens.PaddingMedium))
        
        // 书籍网格
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium),
            verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium)
        ) {
            items(books) { book ->
                BookCard(
                    book = book,
                    onClick = { onBookClick(book) }
                )
            }
        }
    }
}

@Composable
private fun SearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
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
private fun BookCard(
    book: Book,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.customColors.cardBackground
        ),
        elevation = CardDefaults.cardElevation(
            defaultElevation = AppDimens.ElevationSmall
        )
    ) {
        Column(
            modifier = Modifier.padding(AppDimens.PaddingMedium)
        ) {
            // 书籍封面
            BookCover(
                emoji = book.coverEmoji,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(3f / 4f)
            )
            
            Spacer(modifier = Modifier.height(12.dp))
            
            // 书名
            Text(
                text = book.title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            
            Spacer(modifier = Modifier.height(4.dp))
            
            // 作者
            Text(
                text = book.author,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.customColors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            
            Spacer(modifier = Modifier.height(12.dp))
            
            // 进度信息
            ReadingProgress(
                progress = book.progress,
                currentChapter = book.currentChapter,
                totalChapters = book.totalChapters
            )
        }
    }
}

@Composable
private fun BookCover(
    emoji: String,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(AppDimens.CornerRadiusMedium))
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(
                        MaterialTheme.customColors.gradientStart,
                        MaterialTheme.customColors.gradientEnd
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = emoji,
            style = MaterialTheme.typography.displayLarge,
            fontSize = 64.sp
        )
    }
}

@Composable
private fun ReadingProgress(
    progress: Float,
    currentChapter: Int,
    totalChapters: Int
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "进度 ${(progress * 100).toInt()}%",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.customColors.textSecondary
            )
            Text(
                text = "$currentChapter/$totalChapters章",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.customColors.textSecondary
            )
        }
        
        Spacer(modifier = Modifier.height(4.dp))
        
        // 进度条
        LinearProgressIndicator(
            progress = progress,
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp)),
            color = MaterialTheme.customColors.gradientStart,
            trackColor = MaterialTheme.customColors.border
        )
    }
}

