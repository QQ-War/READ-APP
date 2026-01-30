package com.readapp.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
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
    var failed by remember(rawUrl, forceProxy) { mutableStateOf(false) }
    var retryToken by remember(rawUrl, forceProxy) { mutableStateOf(0) }
    val request = remember(rawUrl, serverUrl, chapterUrl, useProxy, accessToken, retryToken) {
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
    Box(modifier = modifier) {
        AsyncImage(
            model = imageRequest,
            contentDescription = null,
            modifier = Modifier.matchParentSize(),
            contentScale = contentScale,
            onSuccess = { failed = false },
            onError = {
                failed = true
                if (!useProxy) {
                    useProxy = true
                }
            }
        )
        if (failed) {
            Button(
                onClick = {
                    failed = false
                    retryToken += 1
                },
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(8.dp)
            ) {
                Text("重试")
            }
        }
    }
}
