package com.readapp.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

@Composable
fun LoginScreen(
    isLoading: Boolean,
    serverUrl: String,
    publicServerUrl: String,
    onLogin: (String, String) -> Unit,
    onServerSave: (String, String?) -> Unit
) {
    val username = remember { mutableStateOf("") }
    val password = remember { mutableStateOf("") }
    val server = remember { mutableStateOf(serverUrl) }
    val publicServer = remember { mutableStateOf(publicServerUrl) }

    LaunchedEffect(serverUrl, publicServerUrl) {
        server.value = serverUrl
        publicServer.value = publicServerUrl
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(text = "登录轻阅读")

        OutlinedTextField(
            value = server.value,
            onValueChange = { server.value = it },
            label = { Text("服务器地址，例如 http://192.168.1.10:8080/api/5") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = publicServer.value,
            onValueChange = { publicServer.value = it },
            label = { Text("公网备用地址（可选）") },
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = username.value,
            onValueChange = { username.value = it },
            label = { Text("用户名") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = password.value,
            onValueChange = { password.value = it },
            label = { Text("密码") },
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth()
        )

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = {
                    onServerSave(server.value, publicServer.value.takeIf { it.isNotBlank() })
                },
                enabled = !isLoading
            ) {
                Text("保存服务器")
            }
            Button(
                onClick = {
                    onServerSave(server.value, publicServer.value.takeIf { it.isNotBlank() })
                    onLogin(username.value, password.value)
                },
                enabled = !isLoading
            ) {
                Text("登录")
            }
        }
    }
}
