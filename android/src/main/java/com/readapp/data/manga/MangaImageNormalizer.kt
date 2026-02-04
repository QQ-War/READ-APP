package com.readapp.data.manga

import android.net.Uri

object MangaImageNormalizer {
    fun sanitizeUrlString(raw: String): String {
        var trimmed = raw.trim()
        val lower = trimmed.lowercase()
        if (lower.startsWith("http//")) {
            trimmed = "http://" + trimmed.removePrefix("http//")
        } else if (lower.startsWith("https//")) {
            trimmed = "https://" + trimmed.removePrefix("https//")
        } else if (lower.startsWith("http:/") && !lower.startsWith("http://")) {
            trimmed = "http://" + trimmed.removePrefix("http:/")
        } else if (lower.startsWith("https:/") && !lower.startsWith("https://")) {
            trimmed = "https://" + trimmed.removePrefix("https:/")
        }
        val patterns = listOf(".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp")
        val lower = trimmed.lowercase()
        for (pattern in patterns) {
            val idx = lower.indexOf(pattern)
            if (idx >= 0) {
                val end = idx + pattern.length
                if (end < trimmed.length && trimmed[end] == ',') {
                    return trimmed.substring(0, end)
                }
                return trimmed
            }
        }
        val idx1 = trimmed.indexOf(",%7B")
        if (idx1 >= 0) return trimmed.substring(0, idx1)
        val idx2 = trimmed.indexOf(",{")
        if (idx2 >= 0) return trimmed.substring(0, idx2)
        return trimmed
    }

    fun resolveUrl(raw: String, baseUrl: String): String {
        val cleaned = sanitizeUrlString(raw)
        val resolved = if (cleaned.startsWith("http")) {
            cleaned
        } else {
            if (cleaned.startsWith("/")) "$baseUrl$cleaned" else "$baseUrl/$cleaned"
        }
        return normalizeHost(resolved)
    }

    fun normalizeHost(url: String): String {
        val uri = Uri.parse(url)
        val host = uri.host?.lowercase() ?: return url
        for (rule in MangaImageNormalizationRules.hostRewrites) {
            val from = rule.fromSuffix.lowercase()
            if (host == from) {
                return uri.buildUpon().encodedAuthority(rule.toSuffix).build().toString()
            }
            if (host.endsWith(".$from")) {
                val prefix = host.substring(0, host.length - from.length - 1)
                val newHost = "$prefix.${rule.toSuffix}"
                return uri.buildUpon().encodedAuthority(newHost).build().toString()
            }
        }
        return url
    }

    fun normalizeCoverUrl(raw: String): String {
        val cleaned = sanitizeUrlString(raw)
        return if (cleaned.startsWith("http")) normalizeHost(cleaned) else cleaned
    }

    fun shouldPreferSignedUrls(results: List<String>, text: String): Boolean {
        if (results.isEmpty()) return false
        if (!text.contains("sign=")) return false
        if (results.any { it.contains("sign=") }) return false
        val allMatch = results.all { url ->
            val host = Uri.parse(url).host?.lowercase() ?: return@all false
            MangaImageNormalizationRules.preferSignedHosts.any { ruleHost ->
                host == ruleHost || host.endsWith(".$ruleHost")
            }
        }
        return allMatch
    }

    fun normalizeEscapedText(text: String): String {
        return text
            .replace("\\u002F", "/")
            .replace("\\/", "/")
            .replace("\\u003F", "?")
            .replace("\\u0026", "&")
    }
}
