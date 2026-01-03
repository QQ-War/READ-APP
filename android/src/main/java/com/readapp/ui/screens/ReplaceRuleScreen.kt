package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.readapp.data.model.ReplaceRule
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors
import com.readapp.viewmodel.BookViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReplaceRuleScreen(
    bookViewModel: BookViewModel = viewModel(),
    onNavigateBack: () -> Unit
) {
    val replaceRules by bookViewModel.replaceRules.collectAsState()
    val isLoading by bookViewModel.isLoading.collectAsState()
    val errorMessage by bookViewModel.errorMessage.collectAsState()

    var showEditDialog by remember { mutableStateOf(false) }
    var showImportUrlDialog by remember { mutableStateOf(false) }
    var importUrl by remember { mutableStateOf("") }
    var editingRule by remember { mutableStateOf<ReplaceRule?>(null) } // null means add new rule
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = androidx.activity.result.contract.ActivityResultContracts.GetContent()
    ) { uri: android.net.Uri? ->
        uri?.let {
            scope.launch {
                val content = context.contentResolver.openInputStream(it)?.bufferedReader()?.use { it.readText() }
                if (!content.isNullOrBlank()) {
                    bookViewModel.saveReplaceRules(content)
                    bookViewModel.loadReplaceRules()
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        bookViewModel.loadReplaceRules()
    }

    Scaffold(
        topBar = {
            var showMenu by remember { mutableStateOf(false) }
            TopAppBar(
                title = { Text("净化规则管理") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "更多")
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = { Text("新建规则") },
                                onClick = {
                                    showMenu = false
                                    editingRule = null
                                    showEditDialog = true
                                },
                                leadingIcon = { Icon(Icons.Default.Add, null) }
                            )
                            DropdownMenuItem(
                                text = { Text("本地导入") },
                                onClick = {
                                    showMenu = false
                                    filePickerLauncher.launch("*/*")
                                },
                                leadingIcon = { Icon(Icons.Default.Folder, null) }
                            )
                            DropdownMenuItem(
                                text = { Text("网络导入") },
                                onClick = {
                                    showMenu = false
                                    showImportUrlDialog = true
                                },
                                leadingIcon = { Icon(Icons.Default.Link, null) }
                            )
                        }
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(AppDimens.PaddingMedium)
        ) {
            if (showImportUrlDialog) {
                AlertDialog(
                    onDismissRequest = { showImportUrlDialog = false },
                    title = { Text("网络导入") },
                    text = {
                        OutlinedTextField(
                            value = importUrl,
                            onValueChange = { importUrl = it },
                            label = { Text("输入规则 URL") },
                            modifier = Modifier.fillMaxWidth()
                        )
                    },
                    confirmButton = {
                        Button(onClick = {
                            scope.launch {
                                val content = fetchUrlContent(importUrl)
                                if (content != null) {
                                    bookViewModel.saveReplaceRules(content)
                                    bookViewModel.loadReplaceRules()
                                }
                                showImportUrlDialog = false
                                importUrl = ""
                            }
                        }) { Text("导入") }
                    },
                    dismissButton = { TextButton(onClick = { showImportUrlDialog = false }) { Text("取消") } }
                )
            }
            if (isLoading && replaceRules.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            } else if (errorMessage != null) {
                Text(errorMessage ?: "未知错误", color = MaterialTheme.colorScheme.error)
                Spacer(Modifier.height(AppDimens.PaddingMedium))
                Button(onClick = { bookViewModel.loadReplaceRules() }) {
                    Text("重试")
                }
            } else if (replaceRules.isEmpty()) {
                Text("暂无净化规则。点击右上角 + 添加新规则。", color = MaterialTheme.customColors.textSecondary)
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingSmall)) {
                    items(replaceRules, key = { it.id }) { rule ->
                        ReplaceRuleItem(
                            rule = rule,
                            onEdit = {
                                editingRule = rule
                                showEditDialog = true
                            },
                            onToggleEnabled = { isEnabled ->
                                bookViewModel.toggleReplaceRule(rule.id, isEnabled)
                            },
                            onDelete = {
                                bookViewModel.deleteReplaceRule(rule.id)
                            }
                        )
                    }
                }
            }
        }
    }

    if (showEditDialog) {
        ReplaceRuleEditDialog(
            rule = editingRule,
            onDismiss = { showEditDialog = false },
            onSave = { newRule ->
                bookViewModel.addReplaceRule(newRule) // Use addReplaceRule for both add/edit
                showEditDialog = false
            }
        )
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

@Composable
fun ReplaceRuleItem(
    rule: ReplaceRule,
    onEdit: () -> Unit,
    onToggleEnabled: (Boolean) -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.customColors.cardBackground
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = AppDimens.ElevationSmall)
    ) {
        Column(
            modifier = Modifier
                .clickable(onClick = onEdit)
                .padding(AppDimens.PaddingMedium)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(rule.name, style = MaterialTheme.typography.titleMedium)
                Switch(
                    checked = rule.isEnabled,
                    onCheckedChange = onToggleEnabled
                )
            }
            rule.groupname?.let {
                if(it.isNotBlank()) {
                    Text("分组: $it", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.customColors.textSecondary)
                }
            }
            Text("模式: ${rule.pattern}", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 2)
            Text("替换: ${rule.replacement}", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 2)
            Text("顺序: ${rule.ruleOrder}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.customColors.textSecondary)

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDelete) {
                    Text("删除", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReplaceRuleEditDialog(
    rule: ReplaceRule?, // null for add, non-null for edit
    onDismiss: () -> Unit,
    onSave: (ReplaceRule) -> Unit
) {
    var name by remember(rule) { mutableStateOf(rule?.name ?: "") }
    var groupname by remember(rule) { mutableStateOf(rule?.groupname ?: "") }
    var pattern by remember(rule) { mutableStateOf(rule?.pattern ?: "") }
    var replacement by remember(rule) { mutableStateOf(rule?.replacement ?: "") }
    var scope by remember(rule) { mutableStateOf(rule?.scope ?: "") }
    var excludeScope by remember(rule) { mutableStateOf(rule?.excludeScope ?: "") }
    var ruleOrder by remember(rule) { mutableStateOf(rule?.ruleOrder ?: 0) }
    var isEnabled by remember(rule) { mutableStateOf(rule?.isEnabled ?: true) }
    var isRegex by remember(rule) { mutableStateOf(rule?.isRegex ?: true) }
    var scopeTitle by remember(rule) { mutableStateOf(rule?.scopeTitle ?: false) }
    var scopeContent by remember(rule) { mutableStateOf(rule?.scopeContent ?: true) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (rule == null) "添加净化规则" else "编辑净化规则") },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("规则名称*") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = pattern, onValueChange = { pattern = it }, label = { Text("匹配内容* (正则)") }, modifier = Modifier.fillMaxWidth(), textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace))
                OutlinedTextField(value = replacement, onValueChange = { replacement = it }, label = { Text("替换为") }, modifier = Modifier.fillMaxWidth(), textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace))
                OutlinedTextField(value = groupname, onValueChange = { groupname = it }, label = { Text("分组") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = scope, onValueChange = { scope = it }, label = { Text("作用范围 (书名,逗号隔开)") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = excludeScope, onValueChange = { excludeScope = it }, label = { Text("排除范围 (书名,逗号隔开)") }, modifier = Modifier.fillMaxWidth())

                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("执行顺序: $ruleOrder")
                    Slider(value = ruleOrder.toFloat(), onValueChange = { ruleOrder = it.toInt() }, valueRange = 0f..100f, steps = 99, modifier = Modifier.weight(1f))
                }

                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("启用规则")
                    Switch(checked = isEnabled, onCheckedChange = { isEnabled = it })
                }
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("使用正则")
                    Switch(checked = isRegex, onCheckedChange = { isRegex = it })
                }
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("作用于标题")
                    Switch(checked = scopeTitle, onCheckedChange = { scopeTitle = it })
                }
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("作用于正文")
                    Switch(checked = scopeContent, onCheckedChange = { scopeContent = it })
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val newRule = ReplaceRule(
                        id = rule?.id ?: "", // Preserve ID for updates
                        name = name,
                        groupname = groupname,
                        pattern = pattern,
                        replacement = replacement,
                        scope = scope,
                        scopeTitle = scopeTitle,
                        scopeContent = scopeContent,
                        excludeScope = excludeScope,
                        isEnabled = isEnabled,
                        isRegex = isRegex,
                        timeoutMillisecond = rule?.timeoutMillisecond ?: 3000L,
                        ruleOrder = ruleOrder
                    )
                    onSave(newRule)
                },
                enabled = name.isNotBlank() && pattern.isNotBlank()
            ) {
                Text("保存")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}
