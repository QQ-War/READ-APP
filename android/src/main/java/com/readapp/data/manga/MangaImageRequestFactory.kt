package com.readapp.data.manga

import android.content.Context
import android.net.Uri
import coil.request.ImageRequest
import com.readapp.data.ApiBackend
import com.readapp.data.detectApiBackend
import com.readapp.data.normalizeApiBaseUrl
import com.readapp.data.stripApiBasePath

data class MangaImageRequest(
    val resolvedUrl: String,
    val requestUrl: String,
    val headers: Map<String, String>
)

object MangaImageRequestFactory {
    private const val defaultUserAgent =
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36"

    fun build(
        rawUrl: String,
        serverUrl: String,
        chapterUrl: String?,
        forceProxy: Boolean,
        accessToken: String? = null
    ): MangaImageRequest? {
        if (rawUrl.isBlank()) return null
        val base = stripApiBasePath(serverUrl)
        val resolved = MangaImageNormalizer.resolveUrl(rawUrl, base)
        val profile = MangaAntiScrapingService.resolveProfile(resolved, chapterUrl)
        val referer = MangaAntiScrapingService.resolveReferer(profile, chapterUrl, resolved)
        val requestUrl = if (forceProxy) {
            buildProxyUrl(resolved, serverUrl, accessToken) ?: resolved
        } else {
            resolved
        }
        val headers = buildHeaders(profile, referer)
        return MangaImageRequest(resolved, requestUrl, headers)
    }

    fun buildImageRequest(context: Context, request: MangaImageRequest): ImageRequest {
        return ImageRequest.Builder(context)
            .data(request.requestUrl)
            .apply {
                request.headers.forEach { (key, value) ->
                    addHeader(key, value)
                }
            }
            .build()
    }

    fun buildProxyUrl(url: String, serverUrl: String, accessToken: String? = null): String? {
        val backend = detectApiBackend(serverUrl)
        if (backend != ApiBackend.Read) {
            return null
        }
        val base = stripApiBasePath(normalizeApiBaseUrl(serverUrl, backend))
        return Uri.parse(base).buildUpon()
            .path("api/5/proxypng")
            .appendQueryParameter("url", url)
            .appendQueryParameter("accessToken", accessToken.orEmpty())
            .build()
            .toString()
    }

    private fun buildHeaders(
        profile: MangaAntiScrapingProfile?,
        referer: String?
    ): Map<String, String> {
        val headers = LinkedHashMap<String, String>()
        if (!referer.isNullOrBlank()) {
            headers["Referer"] = referer
        }
        headers["User-Agent"] = profile?.userAgent ?: defaultUserAgent
        profile?.extraHeaders?.forEach { (key, value) ->
            headers[key] = value
        }
        return headers
    }
}
