// LoginScreen.kt - 登录页面
package com.readapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@Composable
fun LoginScreen(
    viewModel: com.readapp.viewmodel.BookViewModel,
    onLoginSuccess: () -> Unit,
    modifier: Modifier = Modifier
) {
    val serverAddressState by viewModel.serverAddress.collectAsState()
    val usernameState by viewModel.username.collectAsState()
    var serverAddress by rememberSaveable(serverAddressState) { mutableStateOf(serverAddressState) }
    var username by rememberSaveable(usernameState) { mutableStateOf(usernameState) }
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        MaterialTheme.customColors.gradientStart.copy(alpha = 0.1f),
                        MaterialTheme.colorScheme.background
                    )
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(AppDimens.PaddingLarge),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // Logo 和标题
            LoginHeader()
            
            Spacer(modifier = Modifier.height(48.dp))
            
            // 登录表单
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppDimens.CornerRadiusLarge),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.customColors.cardBackground
                ),
                elevation = CardDefaults.cardElevation(
                    defaultElevation = AppDimens.ElevationMedium
                )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(AppDimens.PaddingLarge),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "欢迎回来",
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    
                    Text(
                        text = "登录以继续使用 ReadApp",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.customColors.textSecondary
                    )
                    
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    // 服务器地址输入
                    OutlinedTextField(
                        value = serverAddress,
                        onValueChange = { serverAddress = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("服务器地址") },
                        placeholder = { Text("http://192.168.1.100:8080") },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Cloud,
                                contentDescription = null
                            )
                        },
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Uri,
                            imeAction = ImeAction.Next
                        ),
                        singleLine = true,
                        shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.customColors.gradientStart,
                            focusedLabelColor = MaterialTheme.customColors.gradientStart
                        )
                    )
                    
                    // 用户名输入
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("用户名") },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Person,
                                contentDescription = null
                            )
                        },
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Text,
                            imeAction = ImeAction.Next
                        ),
                        singleLine = true,
                        shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.customColors.gradientStart,
                            focusedLabelColor = MaterialTheme.customColors.gradientStart
                        )
                    )
                    
                    // 密码输入
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("密码") },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Lock,
                                contentDescription = null
                            )
                        },
                        trailingIcon = {
                            IconButton(
                                onClick = { passwordVisible = !passwordVisible }
                            ) {
                                Icon(
                                    imageVector = if (passwordVisible) {
                                        Icons.Default.Visibility
                                    } else {
                                        Icons.Default.VisibilityOff
                                    },
                                    contentDescription = if (passwordVisible) {
                                        "隐藏密码"
                                    } else {
                                        "显示密码"
                                    }
                                )
                            }
                        },
                        visualTransformation = if (passwordVisible) {
                            VisualTransformation.None
                        } else {
                            PasswordVisualTransformation()
                        },
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Password,
                            imeAction = ImeAction.Done
                        ),
                        keyboardActions = KeyboardActions(
                            onDone = {
                                // 执行登录
                                viewModel.login(serverAddress, username, password, onLoginSuccess)
                            }
                        ),
                        singleLine = true,
                        shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.customColors.gradientStart,
                            focusedLabelColor = MaterialTheme.customColors.gradientStart
                        )
                    )
                    
                    // 错误消息
                    if (errorMessage != null) {
                        Text(
                            text = errorMessage!!,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    // 登录按钮
                    Button(
                        onClick = {
                            viewModel.login(serverAddress, username, password, onLoginSuccess)
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp),
                        enabled = !isLoading && 
                                serverAddress.isNotBlank() && 
                                username.isNotBlank() && 
                                password.isNotBlank(),
                        shape = RoundedCornerShape(AppDimens.CornerRadiusMedium),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.customColors.gradientStart,
                            disabledContainerColor = MaterialTheme.customColors.border
                        )
                    ) {
                        if (isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                color = MaterialTheme.colorScheme.onPrimary,
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text(
                                text = "登录",
                                style = MaterialTheme.typography.titleMedium
                            )
                        }
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(24.dp))
            
            // 提示信息
            Text(
                text = "首次使用？请确保已部署轻阅读后端服务",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.customColors.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = AppDimens.PaddingLarge)
            )
        }
    }
}

@Composable
private fun LoginHeader() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Logo 图标
        Surface(
            modifier = Modifier.size(100.dp),
            shape = RoundedCornerShape(24.dp),
            color = MaterialTheme.customColors.gradientStart.copy(alpha = 0.2f)
        ) {
            Box(
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.VolumeUp,
                    contentDescription = "ReadApp Logo",
                    tint = MaterialTheme.customColors.gradientStart,
                    modifier = Modifier.size(56.dp)
                )
            }
        }
        
        // 应用标题
        Text(
            text = "ReadApp",
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.onSurface
        )
        
        Text(
            text = "轻阅读第三方听书客户端",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.customColors.textSecondary
        )
    }
}
