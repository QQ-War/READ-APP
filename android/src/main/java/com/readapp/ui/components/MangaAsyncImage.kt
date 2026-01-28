package com.readapp.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil.compose.AsyncImage
import com.readapp.data.manga.MangaImageRequestFactory

@Composable
fun MangaAsyncImage(
    rawUrl: String,
    serverUrl: String,
    chapterUrl: String?,
    forceProxy: Boolean,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.FillWidth,
    accessToken: String? = null
) {
    val context = LocalContext.current
    var useProxy by remember(rawUrl, forceProxy) { mutableStateOf(forceProxy) }
    val request = remember(rawUrl, serverUrl, chapterUrl, useProxy, accessToken) {
        MangaImageRequestFactory.build(
            rawUrl = rawUrl,
            serverUrl = serverUrl,
            chapterUrl = chapterUrl,
            forceProxy = useProxy,
            accessToken = accessToken
        )
    }
    if (request == null) return
    val imageRequest = remember(request) {
        MangaImageRequestFactory.buildImageRequest(context, request)
    }
    AsyncImage(
        model = imageRequest,
        contentDescription = null,
        modifier = modifier,
        contentScale = contentScale,
        onError = {
            if (!useProxy) {
                useProxy = true
            }
        }
    )
}
