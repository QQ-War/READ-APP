package com.readapp.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.readapp.data.model.*
import com.readapp.viewmodel.SourceViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SourceEditScreen(
    sourceId: String? = null,
    onNavigateBack: () -> Unit,
    sourceViewModel: SourceViewModel = viewModel(factory = SourceViewModel.Factory)
) {
    var jsonContent by remember { mutableStateOf("") }
    var structuredSource by remember { mutableStateOf(FullBookSource()) }
    var editMode by remember { mutableStateOf(0) } // 0: Structured, 1: Raw JSON
    var isLoading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val gson = remember { GsonBuilder().setPrettyPrinting().create() }

    LaunchedEffect(sourceId) {
        if (sourceId != null) {
            isLoading = true
            val content = sourceViewModel.getSourceDetail(sourceId)
            if (content != null) {
                jsonContent = content
                try {
                    structuredSource = gson.fromJson(content, FullBookSource::class.java)
                } catch (e: Exception) {
                    errorMessage = "解析书源失败，请使用源码模式查看"
                }
            } else {
                snackbarHostState.showSnackbar("加载书源失败")
            }
            isLoading = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (sourceId == null) "新建书源" else "编辑书源") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    if (sourceId != null) {
                        IconButton(onClick = { showDeleteConfirm = true }) {
                            Icon(Icons.Default.Delete, contentDescription = "删除", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                    IconButton(
                        onClick = {
                            scope.launch {
                                isLoading = true
                                val finalJson = if (editMode == 0) gson.toJson(structuredSource) else jsonContent
                                val result = sourceViewModel.saveSource(finalJson)
                                isLoading = false
                                if (result.isSuccess) {
                                    sourceViewModel.fetchSources()
                                    onNavigateBack()
                                } else {
                                    errorMessage = result.exceptionOrNull()?.message ?: "保存失败"
                                    snackbarHostState.showSnackbar(errorMessage ?: "保存失败")
                                }
                            }
                        },
                        enabled = !isLoading
                    ) {
                        Icon(Icons.Default.Check, contentDescription = "保存")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        Column(modifier = Modifier.padding(paddingValues).fillMaxSize()) {
            TabRow(selectedTabIndex = editMode) {
                Tab(selected = editMode == 0, onClick = { 
                    if (editMode == 1) {
                        try {
                            structuredSource = gson.fromJson(jsonContent, FullBookSource::class.java)
                            editMode = 0
                        } catch (e: Exception) {
                            scope.launch { snackbarHostState.showSnackbar("JSON格式错误，无法切换") }
                        }
                    } else {
                        editMode = 0 
                    }
                }) {
                    Text("结构化", modifier = Modifier.padding(12.dp))
                }
                Tab(selected = editMode == 1, onClick = { 
                    if (editMode == 0) {
                        jsonContent = gson.toJson(structuredSource)
                    }
                    editMode = 1 
                }) {
                    Text("源码 (JSON)", modifier = Modifier.padding(12.dp))
                }
            }

            if (isLoading) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else {
                if (editMode == 0) {
                    StructuredSourceForm(structuredSource)
                } else {
                    TextField(
                        value = jsonContent,
                        onValueChange = { jsonContent = it },
                        modifier = Modifier.fillMaxSize().padding(8.dp),
                        placeholder = { Text("在此输入书源JSON...") }
                    )
                }
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("确认删除") },
            text = { Text("确定要删除此书源吗？此操作不可恢复。") },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        sourceId?.let { sourceViewModel.deleteSourceById(it) }
                        showDeleteConfirm = false
                        onNavigateBack()
                    }
                }) {
                    Text("删除", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("取消") }
            }
        )
    }
}

@Composable
fun StructuredSourceForm(source: FullBookSource) {
    Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        OutlinedTextField(value = source.bookSourceName, onValueChange = { source.bookSourceName = it }, label = { Text("书源名称") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = source.bookSourceGroup ?: "", onValueChange = { source.bookSourceGroup = it }, label = { Text("书源分组") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = source.bookSourceUrl, onValueChange = { source.bookSourceUrl = it }, label = { Text("书源地址") }, modifier = Modifier.fillMaxWidth())
        
        Text("基础规则", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
        OutlinedTextField(value = source.searchUrl ?: "", onValueChange = { source.searchUrl = it }, label = { Text("搜索地址") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = source.exploreUrl ?: "", onValueChange = { source.exploreUrl = it }, label = { Text("发现地址") }, modifier = Modifier.fillMaxWidth())
        
        RuleSection("搜索规则", source.ruleSearch ?: SearchRule()) { source.ruleSearch = it }
        RuleSection("详情页规则", source.ruleBookInfo ?: BookInfoRule()) { source.ruleBookInfo = it }
        RuleSection("目录规则", source.ruleToc ?: TocRule()) { source.ruleToc = it }
        RuleSection("正文规则", source.ruleContent ?: ContentRule()) { source.ruleContent = it }
    }
}

@Composable
fun RuleSection(title: String, rule: Any, onUpdate: (Any) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(8.dp)) {
                Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null)
            }
            if (expanded) {
                // Simplified editor for rules
                Text("请在源码模式下编辑详细规则", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary, modifier = Modifier.padding(8.dp))
            }
        }
    }
}