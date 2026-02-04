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
        val token = accessToken?.takeIf { it.isNotBlank() }
        val assetUrl = buildAssetUrlIfNeeded(resolved, serverUrl, accessToken)
        val profile = MangaAntiScrapingService.resolveProfile(resolved, chapterUrl)
        val referer = MangaAntiScrapingService.resolveReferer(profile, chapterUrl, resolved)
        val requestUrl = when {
            assetUrl != null -> assetUrl
            forceProxy -> buildProxyUrl(resolved, serverUrl, accessToken)
            else -> resolved
        }
        if (requestUrl.isNullOrBlank()) {
            return null
        }
        if (token == null && isAssetPath(resolved)) {
            return null
        }
        val headers = buildHeaders(profile, referer, token)
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
        val token = accessToken?.takeIf { it.isNotBlank() } ?: return null
        val backend = detectApiBackend(serverUrl)
        if (backend != ApiBackend.Read) {
            return null
        }
        val base = stripApiBasePath(normalizeApiBaseUrl(serverUrl, backend))
        return Uri.parse(base).buildUpon()
            .path("api/5/proxypng")
            .appendQueryParameter("url", url)
            .build()
            .toString()
    }

    fun buildAssetUrlIfNeeded(url: String, serverUrl: String, accessToken: String? = null): String? {
        val token = accessToken?.takeIf { it.isNotBlank() } ?: return null
        val backend = detectApiBackend(serverUrl)
        if (backend != ApiBackend.Read) return null
        val normalized = normalizeAssetPath(url) ?: return null
        val base = stripApiBasePath(normalizeApiBaseUrl(serverUrl, backend))
        return Uri.parse(base).buildUpon()
            .path("api/5/assets")
            .appendQueryParameter("path", normalized)
            .build()
            .toString()
    }

    private fun isAssetPath(url: String): Boolean {
        val lower = url.lowercase()
        return lower.startsWith("/assets/") ||
            lower.startsWith("assets/") ||
            lower.startsWith("../assets/") ||
            lower.startsWith("/book-assets/") ||
            lower.startsWith("book-assets/") ||
            lower.startsWith("../book-assets/") ||
            lower.startsWith("http://assets/") ||
            lower.startsWith("https://assets/") ||
            lower.startsWith("http//assets/") ||
            lower.startsWith("https//assets/") ||
            lower.contains("/assets/") ||
            lower.contains("/book-assets/")
    }

    private fun normalizeAssetPath(url: String): String? {
        val lower = url.lowercase()
        var path: String? = null
        when {
            lower.startsWith("http://assets/") || lower.startsWith("https://assets/") || lower.startsWith("http//assets/") || lower.startsWith("https//assets/") -> {
                val parts = url.split("/").filter { it.isNotEmpty() }
                if (parts.size >= 2) {
                    // drop scheme or malformed scheme token, keep assets/...
                    path = "/" + parts.drop(1).joinToString("/")
                }
            }
            lower.startsWith("../assets/") -> path = "/assets/" + url.removePrefix("../assets/")
            lower.startsWith("../book-assets/") -> path = "/book-assets/" + url.removePrefix("../book-assets/")
            lower.startsWith("assets/") -> path = "/assets/" + url.removePrefix("assets/")
            lower.startsWith("book-assets/") -> path = "/book-assets/" + url.removePrefix("book-assets/")
            lower.startsWith("/assets/") || lower.startsWith("/book-assets/") -> path = url
            else -> {
                val parsed = Uri.parse(url)
                val rawPath = parsed.path
                if (rawPath != null && (rawPath.contains("/assets/") || rawPath.contains("/book-assets/"))) {
                    var normalized = rawPath.replace("/../", "/")
                    if (!normalized.startsWith("/")) {
                        normalized = "/$normalized"
                    }
                    path = if (normalized.contains("/assets/")) {
                        normalized.substring(normalized.indexOf("/assets/"))
                    } else if (normalized.contains("/book-assets/")) {
                        normalized.substring(normalized.indexOf("/book-assets/"))
                    } else null
                } else if (url.contains("/assets/") || url.contains("/book-assets/")) {
                    val normalized = url.replace("/../", "/")
                    path = if (normalized.contains("/assets/")) {
                        normalized.substring(normalized.indexOf("/assets/"))
                    } else if (normalized.contains("/book-assets/")) {
                        normalized.substring(normalized.indexOf("/book-assets/"))
                    } else null
                }
            }
        }

        if (path == null) return null
        if (path.startsWith("/assets/assets/")) {
            path = path.removePrefix("/assets")
        }
        return path
    }

    private fun buildHeaders(
        profile: MangaAntiScrapingProfile?,
        referer: String?,
        accessToken: String?
    ): Map<String, String> {
        val headers = LinkedHashMap<String, String>()
        if (!referer.isNullOrBlank()) {
            headers["Referer"] = referer
        }
        headers["User-Agent"] = profile?.userAgent ?: defaultUserAgent
        if (!accessToken.isNullOrBlank()) {
            headers["Authorization"] = "Bearer $accessToken"
        }
        profile?.extraHeaders?.forEach { (key, value) ->
            headers[key] = value
        }
        return headers
    }
}
