// Theme.kt - 主题配置
package com.readapp.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

// 颜色定义
object AppColors {
    // 主色调 - 渐变蓝紫色系
    val Primary = Color(0xFF3B82F6)
    val PrimaryVariant = Color(0xFF9333EA)
    val Secondary = Color(0xFF8B5CF6)
    
    // 深色模式
    val DarkBackground = Color(0xFF111827)
    val DarkSurface = Color(0xFF1F2937)
    val DarkCard = Color(0xFF374151)
    val DarkBorder = Color(0xFF4B5563)
    
    // 浅色模式
    val LightBackground = Color(0xFFF9FAFB)
    val LightSurface = Color(0xFFFFFFFF)
    val LightCard = Color(0xFFFFFFFF)
    val LightBorder = Color(0xFFE5E7EB)
    
    // 功能色
    val Success = Color(0xFF10B981)
    val Warning = Color(0xFFF59E0B)
    val Error = Color(0xFFEF4444)
    val Info = Color(0xFF3B82F6)
    
    // 文本色
    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xFF9CA3AF)
    val TextPrimaryLight = Color(0xFF111827)
    val TextSecondaryLight = Color(0xFF6B7280)
}

// 深色主题
private val DarkColorScheme = darkColorScheme(
    primary = AppColors.Primary,
    secondary = AppColors.Secondary,
    background = AppColors.DarkBackground,
    surface = AppColors.DarkSurface,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onBackground = AppColors.TextPrimary,
    onSurface = AppColors.TextPrimary,
    error = AppColors.Error
)

// 浅色主题
private val LightColorScheme = lightColorScheme(
    primary = AppColors.Primary,
    secondary = AppColors.Secondary,
    background = AppColors.LightBackground,
    surface = AppColors.LightSurface,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onBackground = AppColors.TextPrimaryLight,
    onSurface = AppColors.TextPrimaryLight,
    error = AppColors.Error
)

@Composable
fun ReadAppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    
    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography(),
        shapes = Shapes(),
        content = content
    )
}

// 自定义形状
val Shapes = Shapes(
    small = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
    medium = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
    large = androidx.compose.foundation.shape.RoundedCornerShape(24.dp)
)

// 扩展属性，便于访问自定义颜色
val MaterialTheme.customColors: CustomColors
    @Composable
    get() = if (isSystemInDarkTheme()) {
        CustomColors(
            cardBackground = AppColors.DarkCard,
            border = AppColors.DarkBorder,
            textSecondary = AppColors.TextSecondary,
            success = AppColors.Success,
            gradientStart = AppColors.Primary,
            gradientEnd = AppColors.PrimaryVariant
        )
    } else {
        CustomColors(
            cardBackground = AppColors.LightCard,
            border = AppColors.LightBorder,
            textSecondary = AppColors.TextSecondaryLight,
            success = AppColors.Success,
            gradientStart = AppColors.Primary,
            gradientEnd = AppColors.PrimaryVariant
        )
    }

data class CustomColors(
    val cardBackground: Color,
    val border: Color,
    val textSecondary: Color,
    val success: Color,
    val gradientStart: Color,
    val gradientEnd: Color
)

// 尺寸定义
object AppDimens {
    val PaddingSmall = 8.dp
    val PaddingMedium = 16.dp
    val PaddingLarge = 24.dp
    val PaddingXLarge = 32.dp
    
    val CornerRadiusSmall = 12.dp
    val CornerRadiusMedium = 16.dp
    val CornerRadiusLarge = 24.dp
    
    val IconSizeSmall = 20.dp
    val IconSizeMedium = 24.dp
    val IconSizeLarge = 32.dp
    
    val ElevationSmall = 2.dp
    val ElevationMedium = 4.dp
    val ElevationLarge = 8.dp
}
