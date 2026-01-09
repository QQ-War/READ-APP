package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.readapp.ui.theme.AppDimens
import com.readapp.viewmodel.BookViewModel
import com.readapp.viewmodel.RssViewModel

@Composable
fun RssSourcesScreen(
    bookViewModel: BookViewModel,
    onNavigateBack: () -> Unit
) {
    val viewModel: RssViewModel = viewModel(
        factory = RssViewModel.Factory(
            repository = bookViewModel.repository,
            preferences = bookViewModel.preferences
        )
    )
    val sources by viewModel.rssSources.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val canEdit by viewModel.canEdit.collectAsState()
    val pending by viewModel.pendingToggles.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                },
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.RssFeed,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.size(8.dp))
                        Text("订阅源")
                    }
                },
                actions = {
                    IconButton(onClick = viewModel::refreshSources) {
                        Icon(Icons.Default.Refresh, contentDescription = "刷新")
                    }
                }
            )
        }
    ) { paddingValues ->
        if (isLoading && sources.isEmpty()) {
            Box(
                modifier = Modifier
                    .padding(paddingValues)
                    .fillMaxWidth()
                    .padding(AppDimens.PaddingLarge),
                contentAlignment = Alignment.Center
            ) {
                Text("加载订阅源中...", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .padding(paddingValues)
                .padding(horizontal = AppDimens.PaddingLarge, vertical = AppDimens.PaddingMedium),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (errorMessage != null) {
                item {
                    Text(
                        text = errorMessage ?: "",
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            item {
                Text(
                    text = if (canEdit) "启用/禁用订阅源会立即同步服务端" else "当前账号只读，无法修改订阅状态",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (sources.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = AppDimens.PaddingLarge),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("暂无可用的订阅源")
                    }
                }
            } else {
                items(sources, key = { it.sourceUrl }) { source ->
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        tonalElevation = 1.dp,
                        shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                        color = MaterialTheme.colorScheme.surfaceVariant
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = source.sourceName ?: source.sourceUrl,
                                    style = MaterialTheme.typography.bodyLarge
                                )
                                source.sourceGroup?.takeIf { it.isNotBlank() }?.let { group ->
                                    Text(
                                        text = group.split(",").firstOrNull() ?: group,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                                source.variableComment?.takeIf { it.isNotBlank() }?.let { comment ->
                                    Text(
                                        text = comment,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                            Switch(
                                checked = source.enabled,
                                onCheckedChange = {
                                    if (canEdit && !pending.contains(source.sourceUrl)) {
                                        viewModel.toggleSource(source.sourceUrl, it)
                                    }
                                },
                                enabled = canEdit && !pending.contains(source.sourceUrl)
                            )
                        }
                    }
                }
            }
            if (isLoading && sources.isNotEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = AppDimens.PaddingLarge),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("同步订阅源中...", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
