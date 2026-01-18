package com.readapp.data

import androidx.compose.ui.graphics.Color

enum class ReaderTheme(val displayName: String, val background: Color, val text: Color) {
    System("系统默认", Color.Unspecified, Color.Unspecified),
    Paper("牛皮纸", Color(0xFFF2E8D5), Color(0xFF2E2E33)),
    EyeCare("护眼绿", Color(0xFFE1F0E1), Color(0xFF2C2C30)),
    Dim("深色微调", Color(0xFF1F2023), Color(0xFFE6E6E8))
}
