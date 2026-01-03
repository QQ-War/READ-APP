package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.readapp.data.model.HttpTTS
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountSettingsScreen(
    serverAddress: String,
    username: String,
    onLogout: () -> Unit,
    onNavigateBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("账号管理") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("用户信息", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("用户名")
                        Text(username, color = MaterialTheme.colorScheme.secondary)
                    }
                    Divider(modifier = Modifier.padding(vertical = 8.dp))
                    Text("服务器地址", style = MaterialTheme.typography.labelSmall)
                    Text(serverAddress, style = MaterialTheme.typography.bodySmall)
                }
            }

            Button(
                onClick = onLogout,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
            ) {
                Text("退出登录")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingSettingsScreen(
    readingMode: com.readapp.data.ReadingMode,
    fontSize: Float,
    horizontalPadding: Float,
    onReadingModeChange: (com.readapp.data.ReadingMode) -> Unit,
    onFontSizeChange: (Float) -> Unit,
    onHorizontalPaddingChange: (Float) -> Unit,
    onClearCache: () -> Unit,
    onNavigateToCache: () -> Unit,
    onNavigateBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("阅读设置") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Column {
                Text("字体大小: ${fontSize.toInt()}", style = MaterialTheme.typography.titleSmall)
                Slider(value = fontSize, onValueChange = onFontSizeChange, valueRange = 12f..30f)
            }

            Column {
                Text("页边距: ${horizontalPadding.toInt()}", style = MaterialTheme.typography.titleSmall)
                Slider(value = horizontalPadding, onValueChange = onHorizontalPaddingChange, valueRange = 0f..48f)
            }

            Column {
                Text("翻页模式", style = MaterialTheme.typography.titleSmall)
                Row(modifier = Modifier.fillMaxWidth()) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { onReadingModeChange(com.readapp.data.ReadingMode.Vertical) }.padding(8.dp)) {
                        RadioButton(selected = readingMode == com.readapp.data.ReadingMode.Vertical, onClick = { onReadingModeChange(com.readapp.data.ReadingMode.Vertical) })
                        Text("上下滚动")
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { onReadingModeChange(com.readapp.data.ReadingMode.Horizontal) }.padding(8.dp)) {
                        RadioButton(selected = readingMode == com.readapp.data.ReadingMode.Horizontal, onClick = { onReadingModeChange(com.readapp.data.ReadingMode.Horizontal) })
                        Text("左右翻页")
                    }
                }
            }

            Button(onClick = onNavigateToCache, modifier = Modifier.fillMaxWidth()) {
                Text("离线缓存管理")
            }

            Button(onClick = onClearCache, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer)) {
                Text("强制清除所有缓存")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TtsSettingsScreen(
    selectedTtsEngine: String,
    useSystemTts: Boolean,
    systemVoiceId: String,
    narrationTtsEngine: String,
    dialogueTtsEngine: String,
    speakerTtsMapping: Map<String, String>,
    availableTtsEngines: List<HttpTTS>,
    speechSpeed: Int,
    preloadCount: Int,
    lockPageOnTTS: Boolean,
    onSelectTtsEngine: (String) -> Unit,
    onUseSystemTtsChange: (Boolean) -> Unit,
    onSystemVoiceIdChange: (String) -> Unit,
    onSelectNarrationTtsEngine: (String) -> Unit,
    onSelectDialogueTtsEngine: (String) -> Unit,
    onAddSpeakerMapping: (String, String) -> Unit,
    onRemoveSpeakerMapping: (String) -> Unit,
    onReloadTtsEngines: () -> Unit,
    onSpeechSpeedChange: (Int) -> Unit,
    onPreloadCountChange: (Int) -> Unit,
    onLockPageOnTTSChange: (Boolean) -> Unit,
    onNavigateToManage: () -> Unit,
    onNavigateBack: () -> Unit
) {
    var showTtsDialog by remember { mutableStateOf(false) }
    var showNarrationDialog by remember { mutableStateOf(false) }
    var showDialogueDialog by remember { mutableStateOf(false) }
    
    val selectedTtsName = availableTtsEngines.firstOrNull { it.id == selectedTtsEngine }?.name ?: "未选择"
    val narrationTtsName = availableTtsEngines.firstOrNull { it.id == narrationTtsEngine }?.name ?: "未选择"
    val dialogueTtsName = availableTtsEngines.firstOrNull { it.id == dialogueTtsEngine }?.name ?: "未选择"

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("听书设置") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                },
                actions = {
                    TextButton(onClick = onNavigateToManage) {
                        Text("管理引擎")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            SectionHeader("通用设置")
            SettingsToggleItem(
                icon = Icons.Default.SettingsSystemDaydream,
                title = "使用系统内置 TTS",
                subtitle = "支持离线使用，响应更快",
                checked = useSystemTts,
                onCheckedChange = onUseSystemTtsChange
            )
            
            SettingsToggleItem(
                icon = Icons.Default.Lock,
                title = "播放时锁定翻页",
                subtitle = "防止听书时误触",
                checked = lockPageOnTTS,
                onCheckedChange = onLockPageOnTTSChange
            )

            SectionHeader("引擎设置")
            if (!useSystemTts) {
                SettingsItem(title = "默认 TTS 引擎", subtitle = selectedTtsName, icon = Icons.Default.VolumeUp) { showTtsDialog = true }
                SettingsItem(title = "旁白 TTS", subtitle = narrationTtsName, icon = Icons.Default.RecordVoiceOver) { showNarrationDialog = true }
                SettingsItem(title = "对话 TTS", subtitle = dialogueTtsName, icon = Icons.Default.Chat) { showDialogueDialog = true }
            } else {
                var showVoiceDialog by remember { mutableStateOf(false) }
                SettingsItem(
                    title = "系统语音选择",
                    subtitle = systemVoiceId.ifBlank { "默认" },
                    icon = Icons.Default.RecordVoiceOver,
                    onClick = { showVoiceDialog = true }
                )
                
                if (showVoiceDialog) {
                    val bookViewModel: com.readapp.viewmodel.BookViewModel = androidx.lifecycle.viewmodel.compose.viewModel()
                    val voices by bookViewModel.availableSystemVoices.collectAsState()
                    
                    AlertDialog(
                        onDismissRequest = { showVoiceDialog = false },
                        title = { Text("选择系统语音") },
                        text = {
                            LazyColumn {
                                item {
                                    Row(
                                        modifier = Modifier.fillMaxWidth().clickable { onSystemVoiceIdChange(""); showVoiceDialog = false }.padding(8.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        RadioButton(selected = systemVoiceId.isEmpty(), onClick = { onSystemVoiceIdChange(""); showVoiceDialog = false })
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text("默认")
                                    }
                                }
                                items(voices) { voice ->
                                    Row(
                                        modifier = Modifier.fillMaxWidth().clickable { onSystemVoiceIdChange(voice.name); showVoiceDialog = false }.padding(8.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        RadioButton(selected = systemVoiceId == voice.name, onClick = { onSystemVoiceIdChange(voice.name); showVoiceDialog = false })
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text("${voice.name} (${voice.locale.displayName})")
                                    }
                                }
                            }
                        },
                        confirmButton = { TextButton(onClick = { showVoiceDialog = false }) { Text("关闭") } }
                    )
                }
            }

            SectionHeader("播放参数")
            Column {
                Text("语速: $speechSpeed%", style = MaterialTheme.typography.titleSmall)
                Slider(value = speechSpeed.toFloat(), onValueChange = { onSpeechSpeedChange(it.toInt()) }, valueRange = 50f..300f)
            }

            if (!useSystemTts) {
                Column {
                    Text("预加载段数: $preloadCount", style = MaterialTheme.typography.titleSmall)
                    Slider(value = preloadCount.toFloat(), onValueChange = { onPreloadCountChange(it.toInt()) }, valueRange = 1f..10f)
                }
            }
        }
    }

    if (showTtsDialog) {
        TtsEngineDialog(availableTtsEngines, selectedTtsEngine, "选择默认 TTS", { onSelectTtsEngine(it); showTtsDialog = false }, onReloadTtsEngines, { showTtsDialog = false })
    }
    if (showNarrationDialog) {
        TtsEngineDialog(availableTtsEngines, narrationTtsEngine, "选择旁白 TTS", { onSelectNarrationTtsEngine(it); showNarrationDialog = false }, onReloadTtsEngines, { showNarrationDialog = false })
    }
    if (showDialogueDialog) {
        TtsEngineDialog(availableTtsEngines, dialogueTtsEngine, "选择对话 TTS", { onSelectDialogueTtsEngine(it); showDialogueDialog = false }, onReloadTtsEngines, { showDialogueDialog = false })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContentSettingsScreen(
    bookshelfSortByRecent: Boolean,
    searchOnlineEnabled: Boolean,
    preferredSourcesCount: Int,
    onBookshelfSortByRecentChange: (Boolean) -> Unit,
    onSearchOnlineEnabledChange: (Boolean) -> Unit,
    onNavigateToPreferredSources: () -> Unit,
    onNavigateToReplaceRules: () -> Unit,
    onNavigateBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("内容与搜索设置") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            SectionHeader("搜索设置")
            SettingsToggleItem(
                title = "书架搜索包含书源",
                subtitle = "在搜索书架书籍时同步搜索全网",
                icon = Icons.Default.Search,
                checked = searchOnlineEnabled,
                onCheckedChange = onSearchOnlineEnabledChange
            )
            
            if (searchOnlineEnabled) {
                SettingsItem(
                    title = "指定搜索源",
                    subtitle = if (preferredSourcesCount == 0) "全部启用源" else "已选 $preferredSourcesCount 个",
                    icon = Icons.Default.Tune,
                    onClick = onNavigateToPreferredSources
                )
            }

            SectionHeader("内容设置")
            SettingsItem(title = "净化规则管理", subtitle = "自定义规则清理书籍内容", icon = Icons.Default.CleaningServices, onClick = onNavigateToReplaceRules)
            SettingsToggleItem(title = "最近阅读排序", subtitle = "按最后阅读时间排序", icon = Icons.Default.Sort, checked = bookshelfSortByRecent, onCheckedChange = onBookshelfSortByRecentChange)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DebugSettingsScreen(
    loggingEnabled: Boolean,
    onLoggingEnabledChange: (Boolean) -> Unit,
    onExportLogs: () -> Unit,
    onClearLogs: () -> Unit,
    onClearCache: () -> Unit,
    logCount: Int,
    onNavigateBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("调试与日志") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            SettingsToggleItem(title = "启用日志记录", icon = Icons.Default.BugReport, checked = loggingEnabled, onCheckedChange = onLoggingEnabledChange)
            SettingsItem(title = "导出日志", subtitle = "当前有 $logCount 条日志", icon = Icons.Default.Share, onClick = onExportLogs)
            SettingsItem(title = "清空日志", icon = Icons.Default.Delete, onClick = onClearLogs)
            SettingsItem(title = "清除离线缓存", icon = Icons.Default.LayersClear, onClick = onClearCache)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TtsEngineManageScreen(
    engines: List<HttpTTS>,
    onAddEngine: (HttpTTS) -> Unit,
    onAddEngines: (String) -> Unit,
    onDeleteEngine: (String) -> Unit,
    onNavigateBack: () -> Unit
) {
    var showEditDialog by remember { mutableStateOf(false) }
    var showImportUrlDialog by remember { mutableStateOf(false) }
    var importUrl by remember { mutableStateOf("") }
    var engineToEdit by remember { mutableStateOf<HttpTTS?>(null) }
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = androidx.activity.result.contract.ActivityResultContracts.GetContent()
    ) { uri: android.net.Uri? ->
        uri?.let {
            scope.launch {
                val content = context.contentResolver.openInputStream(it)?.bufferedReader()?.use { it.readText() }
                if (!content.isNullOrBlank()) {
                    onAddEngines(content)
                }
            }
        }
    }

    Scaffold(
        topBar = {
            var showMenu by remember { mutableStateOf(false) }
            TopAppBar(
                title = { Text("TTS 引擎管理") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "更多")
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = { Text("新建引擎") },
                                onClick = {
                                    showMenu = false
                                    engineToEdit = null
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
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            if (showImportUrlDialog) {
                AlertDialog(
                    onDismissRequest = { showImportUrlDialog = false },
                    title = { Text("网络导入") },
                    text = {
                        OutlinedTextField(
                            value = importUrl,
                            onValueChange = { importUrl = it },
                            label = { Text("输入引擎 URL") },
                            modifier = Modifier.fillMaxWidth()
                        )
                    },
                    confirmButton = {
                        Button(onClick = {
                            scope.launch {
                                val content = fetchUrlContent(importUrl)
                                if (content != null) {
                                    onAddEngines(content)
                                }
                                showImportUrlDialog = false
                                importUrl = ""
                            }
                        }) { Text("导入") }
                    },
                    dismissButton = { TextButton(onClick = { showImportUrlDialog = false }) { Text("取消") } }
                )
            }
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(engines) { engine ->
                    ListItem(
                        headlineContent = { Text(engine.name) },
                        supportingContent = { Text(engine.url, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        trailingContent = {
                            Row {
                                IconButton(onClick = {
                                    engineToEdit = engine
                                    showEditDialog = true
                                }) {
                                    Icon(Icons.Default.Edit, "编辑")
                                }
                                IconButton(onClick = { onDeleteEngine(engine.id) }) {
                                    Icon(Icons.Default.Delete, "删除", tint = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    )
                    Divider()
                }
            }
        }
    }

    if (showEditDialog) {
        TtsEngineEditDialog(
            engine = engineToEdit,
            onSave = {
                onAddEngine(it)
                showEditDialog = false
            },
            onDismiss = { showEditDialog = false }
        )
    }
}

@Composable
private fun TtsEngineEditDialog(
    engine: HttpTTS?,
    onSave: (HttpTTS) -> Unit,
    onDismiss: () -> Unit
) {
    var name by remember { mutableStateOf(engine?.name ?: "") }
    var url by remember { mutableStateOf(engine?.url ?: "") }
    var contentType by remember { mutableStateOf(engine?.contentType ?: "audio/mpeg") }
    var concurrentRate by remember { mutableStateOf(engine?.concurrentRate ?: "1") }
    var header by remember { mutableStateOf(engine?.header ?: "") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (engine == null) "添加引擎" else "编辑引擎") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.verticalScroll(rememberScrollState())) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("名称") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = url, onValueChange = { url = it }, label = { Text("接口 URL") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = contentType, onValueChange = { contentType = it }, label = { Text("Content Type") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = concurrentRate, onValueChange = { concurrentRate = it }, label = { Text("并发频率") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = header, onValueChange = { header = it }, label = { Text("自定义 Header (JSON)") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
            }
        },
        confirmButton = {
            Button(onClick = {
                onSave(HttpTTS(
                    id = engine?.id ?: java.util.UUID.randomUUID().toString(),
                    userid = engine?.userid,
                    name = name,
                    url = url,
                    contentType = contentType,
                    concurrentRate = concurrentRate,
                    loginUrl = engine?.loginUrl,
                    loginUi = engine?.loginUi,
                    header = header,
                    enabledCookieJar = engine?.enabledCookieJar,
                    loginCheckJs = engine?.loginCheckJs,
                    lastUpdateTime = System.currentTimeMillis()
                ))
            }, enabled = name.isNotBlank() && url.isNotBlank()) {
                Text("保存")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PreferredSourcesScreen(
    availableSources: List<com.readapp.data.model.BookSource>,
    preferredUrls: Set<String>,
    onToggleSource: (String) -> Unit,
    onClearAll: () -> Unit,
    onNavigateBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("指定搜索源") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, "返回")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding).fillMaxSize()) {
            item {
                Text(
                    "未选择任何书源时，将默认搜索所有已启用的书源。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.padding(16.dp)
                )
            }
            
            item {
                ListItem(
                    headlineContent = { Text(if (preferredUrls.isEmpty()) "✓ 全部启用源" else "使用全部启用源") },
                    modifier = Modifier.clickable { onClearAll() }
                )
                Divider()
            }
            
            items(availableSources.filter { it.enabled }) { source ->
                ListItem(
                    headlineContent = { Text(source.bookSourceName) },
                    trailingContent = {
                        if (preferredUrls.contains(source.bookSourceUrl)) {
                            Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    },
                    modifier = Modifier.clickable { onToggleSource(source.bookSourceUrl) }
                )
                Divider()
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp))
}

@Composable
fun SettingsItem(
    title: String,
    subtitle: String? = null,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, modifier = Modifier.size(24.dp))
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.Default.ChevronRight, null, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
fun SettingsToggleItem(
    title: String,
    subtitle: String? = null,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, modifier = Modifier.size(24.dp))
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Switch(checked = checked, onCheckedChange = onCheckedChange)
        }
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
            LazyColumn {
                items(availableTtsEngines) { tts ->
                    Row(modifier = Modifier.fillMaxWidth().clickable { onSelect(tts.id) }.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = tts.id == selectedTtsEngine, onClick = { onSelect(tts.id) })
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(tts.name)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } }
    )
}
