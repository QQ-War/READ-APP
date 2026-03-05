// SettingsScreen.kt - 设置页面（带返回按钮）
package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.readapp.Screen
import com.readapp.data.AppInstallLaunchResult
import com.readapp.data.AppUpdateInfo
import com.readapp.data.AppUpdateManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    username: String,
    onNavigateToSubSetting: (String) -> Unit,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val updateManager = remember { AppUpdateManager(context.applicationContext) }
    var isCheckingUpdate by remember { mutableStateOf(false) }
    var isDownloadingUpdate by remember { mutableStateOf(false) }
    var updateStatus by remember { mutableStateOf("当前版本：${updateManager.currentVersionText()}") }
    var pendingUpdate by remember { mutableStateOf<AppUpdateInfo?>(null) }

    Scaffold(
        topBar = {
            LargeTopAppBar(
                title = { Text("设置") }
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(bottom = 32.dp)
        ) {
            item {
                AccountHeader(username) {
                    onNavigateToSubSetting(Screen.SettingsAccount.route)
                }
            }

            item {
                SettingsCategory("通用设置")
            }

            item {
                MenuNavigationItem(
                    title = "阅读设置",
                    icon = Icons.Default.MenuBook,
                    onClick = { onNavigateToSubSetting(Screen.SettingsReading.route) }
                )
            }

            item {
                MenuNavigationItem(
                    title = "听书设置",
                    icon = Icons.Default.VolumeUp,
                    onClick = { onNavigateToSubSetting(Screen.SettingsTts.route) }
                )
            }

            item {
                MenuNavigationItem(
                    title = "内容与净化",
                    icon = Icons.Default.CleaningServices,
                    onClick = { onNavigateToSubSetting(Screen.SettingsContent.route) }
                )
            }

            item {
                MenuNavigationItem(
                    title = "订阅源管理",
                    icon = Icons.Default.RssFeed,
                    onClick = { onNavigateToSubSetting(Screen.RssSources.route) }
                )
            }

            item {
                SettingsCategory("系统")
            }

            item {
                MenuNavigationItem(
                    title = "调试与日志",
                    icon = Icons.Default.BugReport,
                    onClick = { onNavigateToSubSetting(Screen.SettingsDebug.route) }
                )
            }

            item {
                val title = when {
                    isDownloadingUpdate -> "下载更新中..."
                    isCheckingUpdate -> "检查更新中..."
                    else -> "检查应用更新"
                }
                MenuNavigationItem(
                    title = title,
                    subtitle = updateStatus,
                    icon = Icons.Default.Download,
                    onClick = {
                        if (isCheckingUpdate || isDownloadingUpdate) return@MenuNavigationItem
                        scope.launch {
                            isCheckingUpdate = true
                            updateStatus = "正在检查 CI-MAIN 更新..."
                            val result = updateManager.checkCiMainUpdate()
                            result.onSuccess { info ->
                                if (info.hasUpdate) {
                                    updateStatus = "发现新版本：${info.remoteUpdatedAt}"
                                    pendingUpdate = info
                                } else {
                                    updateStatus = "已是最新版本（CI-MAIN）"
                                }
                            }.onFailure {
                                updateStatus = "检查失败：${it.message ?: "未知错误"}"
                            }
                            isCheckingUpdate = false
                        }
                    }
                )
            }

            item {
                Box(modifier = Modifier.fillMaxWidth().padding(top = 24.dp), contentAlignment = Alignment.Center) {
                    Text(
                        updateManager.currentVersionText(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline
                    )
                }
            }
        }
    }

    pendingUpdate?.let { info ->
        AlertDialog(
            onDismissRequest = { pendingUpdate = null },
            title = { Text("发现新版本") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("当前版本：${info.localVersionName}")
                    Text("当前构建：${info.localBuildTimeUtc}")
                    Text("远端构建：${info.remoteUpdatedAt}")
                }
            },
            confirmButton = {
                Button(
                    enabled = !isDownloadingUpdate,
                    onClick = {
                        scope.launch {
                            isDownloadingUpdate = true
                            updateStatus = "正在下载更新包..."
                            val downloadResult = updateManager.downloadApk(info.downloadUrl, info.assetName)
                            downloadResult.onSuccess { apkFile ->
                                when (val installResult = updateManager.launchInstall(apkFile)) {
                                    AppInstallLaunchResult.Started -> {
                                        updateStatus = "已拉起安装器，请完成安装"
                                    }
                                    AppInstallLaunchResult.NeedUnknownSourcesPermission -> {
                                        updateStatus = "请允许“安装未知应用”权限后重试安装"
                                    }
                                    is AppInstallLaunchResult.Failed -> {
                                        updateStatus = "安装失败：${installResult.message}"
                                    }
                                }
                            }.onFailure {
                                updateStatus = "下载失败：${it.message ?: "未知错误"}"
                            }
                            isDownloadingUpdate = false
                            pendingUpdate = null
                        }
                    }
                ) {
                    Text("下载并安装")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingUpdate = null }) {
                    Text("取消")
                }
            }
        )
    }
}

@Composable
private fun AccountHeader(username: String, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Person, null, tint = MaterialTheme.colorScheme.onPrimary)
            }
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(username.ifBlank { "未登录" }, style = MaterialTheme.typography.titleMedium)
                Text("账号与服务器配置", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SettingsCategory(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 12.dp, bottom = 4.dp, start = 4.dp)
    )
}

@Composable
private fun MenuNavigationItem(
    title: String,
    subtitle: String? = null,
    icon: ImageVector,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(icon, null, modifier = Modifier.size(24.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Icon(Icons.Default.ChevronRight, null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.outline)
        }
    }
}
