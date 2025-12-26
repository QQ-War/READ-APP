// SettingsScreen.kt - 设置页面（带返回按钮）
package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import com.readapp.data.model.HttpTTS
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    serverAddress: String,
    username: String,
    selectedTtsEngine: String,
    narrationTtsEngine: String,
    dialogueTtsEngine: String,
    speakerTtsMapping: Map<String, String>,
    availableTtsEngines: List<HttpTTS>,
    speechSpeed: Int,
    preloadCount: Int,
    loggingEnabled: Boolean,
    bookshelfSortByRecent: Boolean,
    onServerAddressChange: (String) -> Unit,
    onSelectTtsEngine: (String) -> Unit,
    onSelectNarrationTtsEngine: (String) -> Unit,
    onSelectDialogueTtsEngine: (String) -> Unit,
    onAddSpeakerMapping: (String, String) -> Unit,
    onRemoveSpeakerMapping: (String) -> Unit,
    onReloadTtsEngines: () -> Unit,
    onSpeechSpeedChange: (Int) -> Unit,
    onPreloadCountChange: (Int) -> Unit,
    onClearCache: () -> Unit,
    onExportLogs: () -> Unit,
    onClearLogs: () -> Unit,
    onLoggingEnabledChange: (Boolean) -> Unit,
    onBookshelfSortByRecentChange: (Boolean) -> Unit,
    onNavigateToReplaceRules: () -> Unit,
    onLogout: () -> Unit,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showTtsDialog by remember { mutableStateOf(false) }
    var showNarrationDialog by remember { mutableStateOf(false) }
    var showDialogueDialog by remember { mutableStateOf(false) }
    var showSpeakerDialog by remember { mutableStateOf(false) }
    var showAccountDialog by remember { mutableStateOf(false) }
    var newSpeakerName by remember { mutableStateOf("") }
    var selectedSpeakerEngine by remember { mutableStateOf("") }
    val selectedTtsName = remember(selectedTtsEngine, availableTtsEngines) {
        availableTtsEngines.firstOrNull { it.id == selectedTtsEngine }?.name
            ?: selectedTtsEngine.ifBlank { "未选择" }
    }
    val narrationTtsName = remember(narrationTtsEngine, availableTtsEngines) {
        availableTtsEngines.firstOrNull { it.id == narrationTtsEngine }?.name
            ?: narrationTtsEngine.ifBlank { "未选择" }
    }
    val dialogueTtsName = remember(dialogueTtsEngine, availableTtsEngines) {
        availableTtsEngines.firstOrNull { it.id == dialogueTtsEngine }?.name
            ?: dialogueTtsEngine.ifBlank { "未选择" }
    }

    LaunchedEffect(Unit) {
        onReloadTtsEngines()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "设置",
                        style = MaterialTheme.typography.headlineSmall
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            imageVector = Icons.Default.ArrowBack,
                            contentDescription = "返回"
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        }
    ) { paddingValues ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState())
                .padding(AppDimens.PaddingMedium),
            verticalArrangement = Arrangement.spacedBy(AppDimens.PaddingMedium)
        ) {
            // 服务器设置
            SettingsSection(title = "服务器配置") {
                SettingsItem(
                    icon = Icons.Default.Cloud,
                    title = "服务器地址",
                    subtitle = serverAddress,
                    onClick = { showAccountDialog = true }
                )
            }

            SettingsSection(title = "书架设置") {
                SettingsToggleItem(
                    icon = Icons.Default.Schedule,
                    title = "最近阅读排序",
                    subtitle = if (bookshelfSortByRecent) "按最近阅读时间" else "按加入书架顺序",
                    checked = bookshelfSortByRecent,
                    onCheckedChange = onBookshelfSortByRecentChange
                )
            }
            
            // TTS 设置
            SettingsSection(title = "听书设置") {
                SettingsItem(
                    icon = Icons.Default.VolumeUp,
                    title = "默认 TTS 引擎",
                    subtitle = selectedTtsName,
                    onClick = {
                        showTtsDialog = true
                    }
                )

                Divider(color = MaterialTheme.customColors.border)

                SettingsItem(
                    icon = Icons.Default.RecordVoiceOver,
                    title = "旁白 TTS",
                    subtitle = narrationTtsName,
                    onClick = {
                        showNarrationDialog = true
                    }
                )

                Divider(color = MaterialTheme.customColors.border)

                SettingsItem(
                    icon = Icons.Default.Chat,
                    title = "对话 TTS",
                    subtitle = dialogueTtsName,
                    onClick = {
                        showDialogueDialog = true
                    }
                )
                
                Divider(color = MaterialTheme.customColors.border)
                
                SliderSettingItem(
                    icon = Icons.Default.Speed,
                    title = "语速",
                    value = speechSpeed,
                    valueRange = 5f..50f,
                    onValueChange = { onSpeechSpeedChange(it.toInt()) },
                    valueLabel = speechSpeed.toString()
                )
                
                Divider(color = MaterialTheme.customColors.border)
                
                SliderSettingItem(
                    icon = Icons.Default.CloudQueue,
                    title = "预加载数量",
                    value = preloadCount,
                    valueRange = 1f..10f,
                    onValueChange = { onPreloadCountChange(it.toInt()) },
                    valueLabel = preloadCount.toString()
                )

                Divider(color = MaterialTheme.customColors.border)

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(AppDimens.PaddingMedium),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "发言人 TTS 映射",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.customColors.textSecondary
                    )

                    if (speakerTtsMapping.isEmpty()) {
                        Text(
                            text = "暂无发言人绑定",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.customColors.textSecondary
                        )
                    } else {
                        speakerTtsMapping.toList().sortedBy { it.first }.forEach { (speaker, ttsId) ->
                            val ttsName = availableTtsEngines.firstOrNull { it.id == ttsId }?.name ?: ttsId
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(text = speaker, style = MaterialTheme.typography.bodyMedium)
                                    Text(
                                        text = "朗读: $ttsName",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.customColors.textSecondary
                                    )
                                }
                                TextButton(onClick = { onRemoveSpeakerMapping(speaker) }) {
                                    Text("移除")
                                }
                            }
                        }
                    }

                    OutlinedTextField(
                        value = newSpeakerName,
                        onValueChange = { newSpeakerName = it },
                        label = { Text("新增发言人") },
                        modifier = Modifier.fillMaxWidth()
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = availableTtsEngines.firstOrNull { it.id == selectedSpeakerEngine }?.name
                                ?: "请选择 TTS 引擎",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        TextButton(onClick = { showSpeakerDialog = true }) {
                            Text("选择引擎")
                        }
                    }

                    Button(
                        onClick = {
                            if (newSpeakerName.isNotBlank() && selectedSpeakerEngine.isNotBlank()) {
                                onAddSpeakerMapping(newSpeakerName, selectedSpeakerEngine)
                                newSpeakerName = ""
                                selectedSpeakerEngine = ""
                            }
                        },
                        enabled = newSpeakerName.isNotBlank() && selectedSpeakerEngine.isNotBlank(),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("添加映射")
                    }
                }
            }

            SettingsSection(title = "内容净化") {
                SettingsItem(
                    icon = Icons.Default.CleaningServices,
                    title = "净化规则管理",
                    subtitle = "自定义规则清理书籍内容",
                    onClick = onNavigateToReplaceRules
                )
            }

            // 数据管理
            SettingsSection(title = "数据管理") {
                SettingsItem(
                    icon = Icons.Default.Delete,
                    title = "清除本地缓存",
                    subtitle = "清除已缓存的书籍内容",
                    onClick = onClearCache,
                    tint = MaterialTheme.colorScheme.onSurface
                )

                Divider(color = MaterialTheme.customColors.border)

                SettingsItem(
                    icon = Icons.Default.Description,
                    title = "导出日志",
                    subtitle = "保存并导出日志用于排查问题",
                    onClick = onExportLogs,
                    tint = MaterialTheme.colorScheme.onSurface
                )

                Divider(color = MaterialTheme.customColors.border)

                SettingsItem(
                    icon = Icons.Default.DeleteSweep,
                    title = "清除历史日志",
                    subtitle = "清空已记录的日志内容",
                    onClick = onClearLogs,
                    tint = MaterialTheme.colorScheme.onSurface
                )

                Divider(color = MaterialTheme.customColors.border)

                SettingsToggleItem(
                    icon = Icons.Default.BugReport,
                    title = "记录日志",
                    subtitle = if (loggingEnabled) "已开启" else "已关闭",
                    checked = loggingEnabled,
                    onCheckedChange = onLoggingEnabledChange
                )
            }
            
            // 关于
            SettingsSection(title = "关于") {
                SettingsItem(
                    icon = Icons.Default.Info,
                    title = "应用版本",
                    subtitle = "v1.0.0",
                    onClick = { }
                )
                
                Divider(color = MaterialTheme.customColors.border)
                
                SettingsItem(
                    icon = Icons.Default.Description,
                    title = "开源协议",
                    subtitle = "MIT License",
                    onClick = { }
                )
            }
            
            // 退出登录
            Card(
                modifier = Modifier.fillMaxWidth(),
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
                        .fillMaxWidth()
                        .clickable(onClick = onLogout)
                        .padding(AppDimens.PaddingMedium),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Logout,
                        contentDescription = "退出登录",
                        tint = MaterialTheme.colorScheme.error
                    )
                    
                    Spacer(modifier = Modifier.width(8.dp))
                    
                    Text(
                        text = "退出登录",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(32.dp))
        }

        if (showTtsDialog) {
            TtsEngineDialog(
                availableTtsEngines = availableTtsEngines,
                selectedTtsEngine = selectedTtsEngine,
                title = "选择默认 TTS 引擎",
                onSelect = {
                    onSelectTtsEngine(it)
                    showTtsDialog = false
                },
                onReload = onReloadTtsEngines,
                onDismiss = { showTtsDialog = false }
            )
        }

        if (showAccountDialog) {
            AccountDetailDialog(
                serverAddress = serverAddress,
                username = username,
                onLogout = {
                    showAccountDialog = false
                    onLogout()
                },
                onDismiss = { showAccountDialog = false }
            )
        }

        if (showNarrationDialog) {
            TtsEngineDialog(
                availableTtsEngines = availableTtsEngines,
                selectedTtsEngine = narrationTtsEngine,
                title = "选择旁白 TTS 引擎",
                onSelect = {
                    onSelectNarrationTtsEngine(it)
                    showNarrationDialog = false
                },
                onReload = onReloadTtsEngines,
                onDismiss = { showNarrationDialog = false }
            )
        }

        if (showDialogueDialog) {
            TtsEngineDialog(
                availableTtsEngines = availableTtsEngines,
                selectedTtsEngine = dialogueTtsEngine,
                title = "选择对话 TTS 引擎",
                onSelect = {
                    onSelectDialogueTtsEngine(it)
                    showDialogueDialog = false
                },
                onReload = onReloadTtsEngines,
                onDismiss = { showDialogueDialog = false }
            )
        }

        if (showSpeakerDialog) {
            TtsEngineDialog(
                availableTtsEngines = availableTtsEngines,
                selectedTtsEngine = selectedSpeakerEngine,
                title = "选择发言人 TTS 引擎",
                onSelect = {
                    selectedSpeakerEngine = it
                    showSpeakerDialog = false
                },
                onReload = onReloadTtsEngines,
                onDismiss = { showSpeakerDialog = false }
            )
        }
    }
}

@Composable
private fun SettingsSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.customColors.textSecondary,
            modifier = Modifier.padding(
                start = AppDimens.PaddingSmall,
                bottom = 4.dp
            )
        )
        
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.customColors.cardBackground
            ),
            elevation = CardDefaults.cardElevation(
                defaultElevation = AppDimens.ElevationSmall
            )
        ) {
            Column(content = content)
        }
    }
}

@Composable
private fun SettingsItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
    tint: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(AppDimens.PaddingMedium),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.weight(1f)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = tint,
                modifier = Modifier.size(24.dp)
            )
            
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = tint
                )
                
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.customColors.textSecondary
                    )
                }
            }
        }
        
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = "进入",
            tint = MaterialTheme.customColors.textSecondary,
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
private fun SettingsToggleItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    tint: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(AppDimens.PaddingMedium),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.weight(1f)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = tint,
                modifier = Modifier.size(24.dp)
            )

            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = tint
                )

                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.customColors.textSecondary
                    )
                }
            }
        }

        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun TtsEngineDialog(
    availableTtsEngines: List<HttpTTS>,
    selectedTtsEngine: String,
    title: String,
    onSelect: (String) -> Unit,
    onReload: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = title) },
        text = {
            if (availableTtsEngines.isEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "暂无可用的 TTS 引擎，请先在后端配置。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.customColors.textSecondary
                    )
                    TextButton(onClick = onReload) {
                        Text("刷新列表")
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 360.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    items(availableTtsEngines) { tts ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    onSelect(tts.id)
                                }
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = tts.id == selectedTtsEngine,
                                onClick = { onSelect(tts.id) }
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = tts.name,
                                    style = MaterialTheme.typography.bodyLarge
                                )
                                if (tts.contentType != null) {
                                    Text(
                                        text = tts.contentType,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.customColors.textSecondary
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("关闭")
            }
        }
    )
}

@Composable
private fun AccountDetailDialog(
    serverAddress: String,
    username: String,
    onLogout: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = "帐号详情") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(text = "账号：${username.ifBlank { "未登录" }}")
                Text(text = "服务器：$serverAddress")
            }
        },
        confirmButton = {
            TextButton(onClick = onLogout) {
                Text("退出登录")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("关闭")
            }
        }
    )
}

@Composable
private fun SliderSettingItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    value: Int,
    valueRange: ClosedFloatingPointRange<Float>,
    onValueChange: (Float) -> Unit,
    valueLabel: String
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(AppDimens.PaddingMedium)
    ) {
        Row(
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = title,
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(24.dp)
                )
                
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
            
            Surface(
                shape = RoundedCornerShape(8.dp),
                color = MaterialTheme.customColors.gradientStart.copy(alpha = 0.2f)
            ) {
                Text(
                    text = valueLabel,
                    modifier = Modifier.padding(
                        horizontal = 12.dp,
                        vertical = 4.dp
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.customColors.gradientStart
                )
            }
        }
        
        Spacer(modifier = Modifier.height(8.dp))
        
        Slider(
            value = value.toFloat(),
            onValueChange = onValueChange,
            valueRange = valueRange,
            modifier = Modifier.fillMaxWidth(),
            colors = SliderDefaults.colors(
                thumbColor = MaterialTheme.customColors.gradientStart,
                activeTrackColor = MaterialTheme.customColors.gradientStart,
                inactiveTrackColor = MaterialTheme.customColors.border
            )
        )
    }
}