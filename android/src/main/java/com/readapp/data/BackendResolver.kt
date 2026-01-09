package com.readapp.data

object BackendResolver {
    fun resolveBackendAndEndpoints(baseUrl: String, publicUrl: String?): Pair<ApiBackend, List<String>> {
        val backend = resolveBackend(baseUrl)
        val endpoints = buildEndpoints(baseUrl, publicUrl, backend)
        return backend to endpoints
    }

    fun resolveBackend(baseUrl: String): ApiBackend = detectApiBackend(baseUrl)

    fun buildEndpoints(baseUrl: String, publicUrl: String?, backend: ApiBackend): List<String> {
        return if (backend == ApiBackend.Reader) {
            resolveReaderEndpoints(baseUrl)
        } else {
            val actualPublic = ensurePublicUrl(baseUrl, publicUrl)
            val normalizedBase = ensureTrailingSlash(baseUrl)
            listOf(actualPublic, normalizedBase)
        }
    }

    private fun ensureTrailingSlash(url: String): String = if (url.endsWith('/')) url else "$url/"

    private fun ensurePublicUrl(baseUrl: String, publicUrl: String?): String =
        publicUrl?.takeIf { it.isNotBlank() } ?: ensureTrailingSlash(baseUrl)

    private fun resolveReaderEndpoints(baseUrl: String): List<String> {
        return listOf(ensureTrailingSlash(baseUrl))
    }
}
