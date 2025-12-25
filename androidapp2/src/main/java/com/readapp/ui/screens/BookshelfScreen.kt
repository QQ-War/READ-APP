// BookshelfScreen.kt - 书架页面（带右上角设置按钮）
package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book as BookIcon
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.readapp.data.model.Book
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookshelfScreen(
    books: List<Book>,
    onBookClick: (Book) -> Unit,
    onSearchQueryChange: (String) -> Unit,
    onSettingsClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    var searchQuery by remember { mutableStateOf("") }
    
    Scaffold(
        topBar = {
            // 顶部栏：标题和设置按钮
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
                    // 设置按钮
                    IconButton(onClick = onSettingsClick) {
                        Icon(
                            imageVector = Icons.Default.Settings,
                            contentDescription = "设置",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = AppDimens.PaddingMedium),
            verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium),
            contentPadding = PaddingValues(bottom = AppDimens.PaddingLarge)
        ) {
            item {
                Spacer(modifier = Modifier.height(AppDimens.PaddingMedium))
                SearchBar(
                    query = searchQuery,
                    onQueryChange = {
                        searchQuery = it
                        onSearchQueryChange(it)
                    },
                    modifier = Modifier.fillMaxWidth()
                )
            }

            if (books.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 48.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.BookIcon,
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
            } else {
                items(books) { book ->
                    BookRow(
                        book = book,
                        onClick = { onBookClick(book) }
                    )
                }
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
private fun BookRow(
    book: Book,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .height(120.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.customColors.cardBackground
        ),
        elevation = CardDefaults.cardElevation(
            defaultElevation = AppDimens.ElevationSmall
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(AppDimens.PaddingMedium),
            horizontalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium)
        ) {
            BookCover(
                emoji = book.coverEmoji,
                coverUrl = book.coverUrl,
                modifier = Modifier
                    .fillMaxHeight()
                    .aspectRatio(3f / 4f)
            )

            Column(
                modifier = Modifier
                    .fillMaxHeight()
                    .weight(1f),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = book.title,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = book.author,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.customColors.textSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                ReadingProgress(
                    progress = book.progress,
                    currentChapter = book.currentChapter,
                    totalChapters = book.totalChapters
                )
            }
        }
    }
}

@Composable
private fun BookCover(
    emoji: String,
    coverUrl: String?,
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
        if (!coverUrl.isNullOrBlank()) {
            AsyncImage(
                model = coverUrl,
                contentDescription = "书籍封面",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Text(
                text = emoji,
                style = MaterialTheme.typography.displayLarge,
                fontSize = 64.sp
            )
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
                text = "$currentChapter/${totalChapters}章",
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
