package com.readapp.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import com.readapp.data.manga.MangaImageNormalizer

@Composable
fun RemoteCoverImage(
    url: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop
) {
    val normalized = remember(url) {
        url?.takeIf { it.isNotBlank() }?.let { MangaImageNormalizer.normalizeCoverUrl(it) }
    }
    AsyncImage(
        model = normalized ?: url.orEmpty(),
        contentDescription = contentDescription,
        modifier = modifier,
        contentScale = contentScale
    )
}
