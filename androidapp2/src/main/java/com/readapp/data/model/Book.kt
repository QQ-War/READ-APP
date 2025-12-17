package com.readapp.data.model

data class Book(
    val name: String = "",
    val author: String = "",
    val bookUrl: String? = null,
    val origin: String? = null,
    val originName: String? = null,
    val coverUrl: String? = null,
    val intro: String? = null,
    val durChapterTitle: String? = null,
    val durChapterIndex: Int? = null,
    val durChapterPos: Double? = null,
    val totalChapterNum: Int? = null,
    val latestChapterTitle: String? = null,
    val kind: String? = null,
    val type: Int? = null,
    val durChapterTime: Long? = null,
    val coverEmoji: String = "📘",
    val progress: Float = 0f,
    val currentChapter: Int = 0,
    val totalChapters: Int = 0
) {
    val id: String = bookUrl ?: name
    val title: String
        get() = name

    fun toUiModel(): Book {
        val safeTotal = totalChapterNum ?: totalChapters.takeIf { it > 0 }
        val safeIndex = durChapterIndex ?: (currentChapter - 1)
        val computedProgress = safeTotal?.takeIf { it > 0 }?.let {
            (safeIndex + 1).toFloat() / it
        } ?: progress

        val emoji = coverEmoji.ifBlank { deriveEmojiFromTitle(name) }

        return copy(
            coverEmoji = emoji,
            currentChapter = (safeIndex + 1).coerceAtLeast(0),
            totalChapters = safeTotal ?: totalChapters,
            progress = computedProgress.coerceIn(0f, 1f)
        )
    }

    private fun deriveEmojiFromTitle(title: String?): String {
        if (title.isNullOrBlank()) return "📖"
        val codePoint = title.codePointAt(0)
        val index = (codePoint % emojiSeeds.size).toInt()
        return emojiSeeds[index]
    }

    companion object {
        private val emojiSeeds = listOf("📘", "📙", "📗", "📕", "📓", "📔", "📒", "📚", "📖", "🧾")
    }
}
