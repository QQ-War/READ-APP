package com.readapp.data.manga

object MangaImageExtractor {
    private const val minExpectedImageCount = 3

    fun extractImageUrls(rawContent: String): List<String> {
        val results = linkedSetOf<String>()
        val attrPatterns = listOf(
            """data-original=["']([^"']+)["']""",
            """data-src=["']([^"']+)["']""",
            """data-lazy=["']([^"']+)["']""",
            """data-echo=["']([^"']+)["']""",
            """data-img=["']([^"']+)["']""",
            """data-url=["']([^"']+)["']""",
            """src=["']([^"']+)["']"""
        ).map { it.toRegex(RegexOption.IGNORE_CASE) }

        val imgTagPattern = """<img\s+([^>]+)>""".toRegex(RegexOption.IGNORE_CASE)
        imgTagPattern.findAll(rawContent).forEach { match ->
            val attrs = match.groupValues.getOrNull(1).orEmpty()
            for (regex in attrPatterns) {
                val m = regex.find(attrs)
                if (m != null) {
                    results.add(m.groupValues[1])
                    break
                }
            }
        }

        val tokenPattern = """__IMG__(\S+)""".toRegex()
        tokenPattern.findAll(rawContent).forEach { match ->
            results.add(match.groupValues[1])
        }

        val normalizedText = MangaImageNormalizer.normalizeEscapedText(rawContent)
        if (results.isEmpty() || results.size < minExpectedImageCount || MangaImageNormalizer.shouldPreferSignedUrls(results.toList(), normalizedText)) {
            val fallbackResults = linkedSetOf<String>()
            val patterns = listOf(
                """https?://[^\s"'<>]+(?:\?|&)(?:sign|t)=[^\s"'<>]+""",
                """https?://[^\s"'<>]+(?:\.(?:jpg|jpeg|png|webp|gif|bmp))(?:\?[^\"'\s<>]*)?"""
            ).map { it.toRegex(RegexOption.IGNORE_CASE) }
            for (regex in patterns) {
                regex.findAll(normalizedText).forEach { match ->
                    fallbackResults.add(match.value)
                }
            }
            if (fallbackResults.isNotEmpty()) {
                results.clear()
                results.addAll(fallbackResults)
            }
        }

        return results.toList()
    }
}
