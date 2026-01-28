package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.readapp.ui.components.RemoteCoverImage
import com.readapp.ui.theme.AppDimens
import com.readapp.viewmodel.BookViewModel
import com.readapp.viewmodel.RssViewModel
import com.readapp.data.model.RssSourceItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RssSourcesScreen(
    bookViewModel: BookViewModel,
    onNavigateBack: () -> Unit
) {
    val viewModel: RssViewModel = viewModel(
        factory = RssViewModel.Factory(
            remoteDataSourceFactory = bookViewModel.remoteDataSourceFactory,
            preferences = bookViewModel.preferences
        )
    )
    val sources by viewModel.rssSources.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val canEdit by viewModel.canEdit.collectAsState()
    val pending by viewModel.pendingToggles.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val remoteBusy by viewModel.remoteOperationInProgress.collectAsState()
    var selectedRemoteSource by remember { mutableStateOf<RssSourceItem?>(null) }
    var editingRemoteSource by remember { mutableStateOf<RssSourceItem?>(null) }
    var showingRemoteEditor by remember { mutableStateOf(false) }

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
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { selectedRemoteSource = source },
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
                            if (!source.sourceIcon.isNullOrBlank()) {
                                RemoteCoverImage(
                                    url = source.sourceIcon,
                                    contentDescription = null,
                                    modifier = Modifier
                                        .size(40.dp)
                                        .clip(RoundedCornerShape(AppDimens.CornerRadiusMedium)),
                                    contentScale = ContentScale.Crop
                                )
                                Spacer(modifier = Modifier.size(12.dp))
                            } else {
                                Icon(
                                    imageVector = Icons.Default.RssFeed,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(36.dp)
                                )
                                Spacer(modifier = Modifier.size(12.dp))
                            }
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

    if (showingRemoteEditor) {
        RemoteRssEditorDialog(
            initialSource = null,
            isBusy = remoteBusy,
            onDismiss = { showingRemoteEditor = false },
            onSave = { newSource ->
                viewModel.saveRemoteSource(newSource)
                showingRemoteEditor = false
            }
        )
    }

    editingRemoteSource?.let { source ->
        RemoteRssEditorDialog(
            initialSource = source,
            isBusy = remoteBusy,
            onDismiss = { editingRemoteSource = null },
            onSave = { updated ->
                viewModel.saveRemoteSource(updated, remoteId = source.sourceUrl)
                editingRemoteSource = null
            }
        )
    }

    selectedRemoteSource?.let { source ->
        RemoteRssDetailDialog(
            source = source,
            canEdit = canEdit,
            isBusy = remoteBusy,
            onDismiss = { selectedRemoteSource = null },
            onEdit = {
                editingRemoteSource = source
                selectedRemoteSource = null
            },
            onDelete = {
                viewModel.deleteRemoteSource(source)
                selectedRemoteSource = null
            }
        )
    }
}

@Composable
private fun RemoteRssEditorDialog(
    initialSource: RssSourceItem?,
    isBusy: Boolean,
    onDismiss: () -> Unit,
    onSave: (RssSourceItem) -> Unit
) {
    val scrollState = rememberScrollState()
    var name by remember { mutableStateOf(initialSource?.sourceName ?: "") }
    var url by remember { mutableStateOf(initialSource?.sourceUrl ?: "") }
    var group by remember { mutableStateOf(initialSource?.sourceGroup ?: "") }
    var icon by remember { mutableStateOf(initialSource?.sourceIcon ?: "") }
    var comment by remember { mutableStateOf(initialSource?.variableComment ?: "") }
    var loginUrl by remember { mutableStateOf(initialSource?.loginUrl ?: "") }
    var loginUi by remember { mutableStateOf(initialSource?.loginUi ?: "") }
    var enabled by remember { mutableStateOf(initialSource?.enabled ?: true) }

    AlertDialog(
        onDismissRequest = { if (!isBusy) onDismiss() },
        title = {
            Text(if (initialSource == null) "新建官方订阅源" else "编辑官方订阅源")
        },
        text = {
            Column(
                modifier = Modifier
                    .verticalScroll(scrollState)
                    .padding(vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("订阅名称") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isBusy
                )
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    label = { Text("订阅链接") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isBusy
                )
                OutlinedTextField(
                    value = group,
                    onValueChange = { group = it },
                    label = { Text("分组标签") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isBusy
                )
                OutlinedTextField(
                    value = icon,
                    onValueChange = { icon = it },
                    label = { Text("图标地址") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isBusy
                )
                OutlinedTextField(
                    value = comment,
                    onValueChange = { comment = it },
                    label = { Text("备注") },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isBusy
                )
                OutlinedTextField(
                    value = loginUrl,
                    onValueChange = { loginUrl = it },
                    label = { Text("登录地址") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isBusy
                )
                OutlinedTextField(
                    value = loginUi,
                    onValueChange = { loginUi = it },
                    label = { Text("登录界面") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isBusy
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("启用订阅源")
                    Spacer(modifier = Modifier.weight(1f))
                    Switch(
                        checked = enabled,
                        onCheckedChange = { enabled = it },
                        enabled = !isBusy
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val trimmedUrl = url.trim()
                    if (trimmedUrl.isNotBlank()) {
                        onSave(
                            RssSourceItem(
                                sourceUrl = trimmedUrl,
                                sourceName = name.ifBlank { null },
                                sourceGroup = group.ifBlank { null },
                                sourceIcon = icon.ifBlank { null },
                                variableComment = comment.ifBlank { null },
                                loginUrl = loginUrl.ifBlank { null },
                                loginUi = loginUi.ifBlank { null },
                                enabled = enabled
                            )
                        )
                    }
                },
                enabled = url.isNotBlank() && !isBusy
            ) {
                Text("保存")
            }
        },
        dismissButton = {
            TextButton(onClick = { if (!isBusy) onDismiss() }) {
                Text("取消")
            }
        }
    )
}

@Composable
private fun RemoteRssDetailDialog(
    source: RssSourceItem,
    canEdit: Boolean,
    isBusy: Boolean,
    onDismiss: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(source.sourceName ?: "订阅详情")
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("链接: ${source.sourceUrl}", style = MaterialTheme.typography.bodySmall)
                Text("状态: ${if (source.enabled) "已启用" else "已禁用"}", style = MaterialTheme.typography.bodySmall)
                source.sourceGroup?.takeIf { it.isNotBlank() }?.let { Text("分组: $it", style = MaterialTheme.typography.bodySmall) }
                source.variableComment?.takeIf { it.isNotBlank() }?.let { Text("备注: $it", style = MaterialTheme.typography.bodySmall) }
                source.loginUrl?.takeIf { it.isNotBlank() }?.let { Text("登录地址: $it", style = MaterialTheme.typography.bodySmall) }
                source.loginUi?.takeIf { it.isNotBlank() }?.let { Text("登录界面: $it", style = MaterialTheme.typography.bodySmall) }
            }
        },
        confirmButton = {
            if (canEdit) {
                Button(onClick = onEdit, enabled = !isBusy) {
                    Text("编辑")
                }
            }
        },
        dismissButton = {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TextButton(onClick = onDismiss) {
                    Text("关闭")
                }
                if (canEdit) {
                    TextButton(
                        onClick = onDelete,
                        enabled = !isBusy
                    ) {
                        Text("删除", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    )
}
