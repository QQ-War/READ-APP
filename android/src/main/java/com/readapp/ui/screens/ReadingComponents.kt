package com.readapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.Divider
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.readapp.ui.theme.AppDimens
import com.readapp.ui.theme.customColors

@Composable
internal fun ParagraphItem(
    text: String,
    isPlaying: Boolean,
    isPreloaded: Boolean,
    fontSize: Float,
    chapterUrl: String?,
    serverUrl: String,
    forceProxy: Boolean,
    modifier: Modifier = Modifier
) {
    val backgroundColor = when {
        isPlaying -> MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
        isPreloaded -> MaterialTheme.customColors.success.copy(alpha = 0.15f)
        else -> Color.Transparent
    }
    Surface(modifier = modifier, color = backgroundColor, shape = RoundedCornerShape(8.dp)) {
        val imgUrl = androidx.compose.runtime.remember(text) {
            """(?:__IMG__|<img[^>]+(?:src|data-src)=["']?)([^"'>\s\n]+)["']?""".toRegex()
                .find(text)
                ?.groupValues
                ?.get(1)
        }
        if (imgUrl != null) {
            AsyncImage(
                model = imgUrl,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                contentScale = ContentScale.FillWidth
            )
        } else {
            Text(
                text,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = fontSize.sp),
                color = MaterialTheme.colorScheme.onSurface,
                lineHeight = (fontSize * 1.8f).sp,
                modifier = Modifier.padding(
                    horizontal = if (isPlaying || isPreloaded) 12.dp else 0.dp,
                    vertical = if (isPlaying || isPreloaded) 8.dp else 0.dp
                )
            )
        }
    }
}

@Composable
internal fun TopControlBar(title: String, chapter: String, onBack: () -> Unit, onHeader: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
        shadowElevation = 4.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppDimens.PaddingMedium, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "返回") }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp)
                    .clickable(onClick = onHeader)
            ) {
                Text(text = title, style = MaterialTheme.typography.titleMedium, maxLines = 1)
                Text(
                    text = chapter,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.customColors.textSecondary,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
internal fun EdgeSwitchHint(text: String, isTop: Boolean, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.padding(top = if (isTop) 8.dp else 0.dp, bottom = if (isTop) 0.dp else 12.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f),
        shape = RoundedCornerShape(12.dp),
        shadowElevation = 4.dp
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
        )
    }
}

@Composable
internal fun BottomControlBar(
    isPlaying: Boolean,
    isManga: Boolean,
    isForceLandscape: Boolean,
    onToggleRotation: () -> Unit,
    onPrev: () -> Unit,
    onNext: () -> Unit,
    onList: () -> Unit,
    onPlay: () -> Unit,
    onStop: () -> Unit,
    onPrevP: () -> Unit,
    onNextP: () -> Unit,
    onFont: () -> Unit,
    canPrev: Boolean,
    canNext: Boolean,
    showTts: Boolean
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
        shadowElevation = 8.dp,
        shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppDimens.PaddingMedium, vertical = 12.dp)
                .navigationBarsPadding()
        ) {
            if (showTts) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 12.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = onPrevP) { Icon(Icons.Default.KeyboardArrowUp, null) }
                    FloatingActionButton(
                        onClick = onPlay,
                        containerColor = MaterialTheme.customColors.gradientStart,
                        modifier = Modifier.size(48.dp)
                    ) {
                        Icon(
                            if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            null,
                            tint = Color.White
                        )
                    }
                    IconButton(onClick = onNextP) { Icon(Icons.Default.KeyboardArrowDown, null) }
                    IconButton(onClick = onStop) { Icon(Icons.Default.Stop, null, tint = MaterialTheme.colorScheme.error) }
                }
                Divider(modifier = Modifier.padding(bottom = 12.dp), color = MaterialTheme.customColors.border.copy(alpha = 0.5f))
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Button(
                    onClick = onPrev,
                    modifier = Modifier.weight(1f),
                    enabled = canPrev,
                    shape = RoundedCornerShape(12.dp)
                ) { Text("上一章", textAlign = TextAlign.Center) }
                Button(
                    onClick = onNext,
                    modifier = Modifier.weight(1f),
                    enabled = canNext,
                    shape = RoundedCornerShape(12.dp)
                ) { Text("下一章", textAlign = TextAlign.Center) }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("列表", modifier = Modifier.clickable(onClick = onList), style = MaterialTheme.typography.labelLarge)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("排版", modifier = Modifier.clickable(onClick = onFont), style = MaterialTheme.typography.labelLarge)
                }
                if (!isManga) {
                    Text(
                        if (isForceLandscape) "竖屏" else "横屏",
                        modifier = Modifier.clickable(onClick = onToggleRotation),
                        style = MaterialTheme.typography.labelLarge
                    )
                }
            }
        }
    }
}
