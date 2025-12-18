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
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    serverAddress: String,
    selectedTtsEngine: String,
    speechSpeed: Int,
    preloadCount: Int,
    onServerAddressChange: (String) -> Unit,
    onTtsEngineClick: () -> Unit,
    onSpeechSpeedChange: (Int) -> Unit,
    onPreloadCountChange: (Int) -> Unit,
    onClearCache: () -> Unit,
    onLogout: () -> Unit,
    onNavigateBack: () -> Unit,
    modifier: Modifier = Modifier
) {
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
                    onClick = { /* 打开服务器地址编辑对话框 */ }
                )
            }
            
            // TTS 设置
            SettingsSection(title = "听书设置") {
                SettingsItem(
                    icon = Icons.Default.VolumeUp,
                    title = "TTS引擎",
                    subtitle = selectedTtsEngine,
                    onClick = onTtsEngineClick
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
