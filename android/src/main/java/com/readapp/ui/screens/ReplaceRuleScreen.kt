package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
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
    var editingRule by remember { mutableStateOf<ReplaceRule?>(null) } // null means add new rule

    LaunchedEffect(Unit) {
        bookViewModel.loadReplaceRules()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("净化规则管理") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        editingRule = null // For adding a new rule
                        showEditDialog = true
                    }) {
                        Icon(Icons.Default.Add, contentDescription = "添加规则")
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

@Composable
fun ReplaceRuleItem(
    rule: ReplaceRule,
    onEdit: (ReplaceRule) -> Unit,
    onToggleEnabled: (Boolean) -> Unit,
    onDelete: (ReplaceRule) -> Unit
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
                .clickable { onEdit(rule) }
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
                    onCheckedChange = onToggleEnabled,
                    modifier = Modifier.size(24.dp) // Adjust size if needed
                )
            }
            Text("模式: ${rule.pattern}", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
            Text("替换: ${rule.replacement}", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
            Text("顺序: ${rule.order}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.customColors.textSecondary)
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = { onDelete(rule) }) {
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
    var pattern by remember(rule) { mutableStateOf(rule?.pattern ?: "") }
    var replacement by remember(rule) { mutableStateOf(rule?.replacement ?: "") }
    var order by remember(rule) { mutableStateOf(rule?.order ?: 0) }
    var isEnabled by remember(rule) { mutableStateOf(rule?.isEnabled ?: true) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (rule == null) "??????" else "??????") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingSmall)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("规则名称") },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = pattern,
                    onValueChange = { pattern = it },
                    label = { Text("匹配内容 (正则表达式)") },
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace)
                )
                OutlinedTextField(
                    value = replacement,
                    onValueChange = { replacement = it },
                    label = { Text("替换为") },
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace)
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("执行顺序: $order")
                    Slider(
                        value = order.toFloat(),
                        onValueChange = { order = it.toInt() },
                        valueRange = 0f..100f, // 假定一个合理的顺序范围
                        steps = 99,
                        modifier = Modifier.weight(1f)
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("启用")
                    Switch(checked = isEnabled, onCheckedChange = { isEnabled = it })
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val newRule = ReplaceRule(
                        id = rule?.id ?: 0, // Preserve ID for updates, 0 for new
                        pattern = pattern,
                        replacement = replacement,
                        scope = rule?.scope ?: "global", // Default or preserve scope
                        name = name,
                        order = order,
                        isEnabled = isEnabled
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
