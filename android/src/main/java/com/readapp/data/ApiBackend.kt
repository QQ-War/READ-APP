package com.readapp.data

enum class ApiBackend {
    Read,
    Reader
}

fun detectApiBackend(serverUrl: String): ApiBackend {
    val normalized = serverUrl.lowercase()
    return when {
        normalized.contains("/reader3") -> ApiBackend.Reader
        normalized.contains("/api/") -> ApiBackend.Read
        else -> ApiBackend.Read
    }
}

fun normalizeApiBaseUrl(serverUrl: String, backend: ApiBackend): String {
    if (serverUrl.isBlank()) return serverUrl
    val trimmed = serverUrl.trimEnd('/')
    return when (backend) {
        ApiBackend.Reader -> if (trimmed.contains("/reader3")) trimmed else "$trimmed/reader3"
        ApiBackend.Read -> if (trimmed.contains("/api/")) trimmed else "$trimmed/api/5"
    }
}

fun stripApiBasePath(serverUrl: String): String {
    val trimmed = serverUrl.trimEnd('/')
    return trimmed
        .replace(Regex("/api/\\d+$"), "")
        .replace(Regex("/reader3$"), "")
        .trimEnd('/')
}
