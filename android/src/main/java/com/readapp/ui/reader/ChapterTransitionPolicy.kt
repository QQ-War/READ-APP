package com.readapp.ui.reader

import com.readapp.data.ReadingMode

data class SectionOffsets(
    val currentStart: Int,
    val currentEndExclusive: Int,
    val prevStart: Int?,
    val nextStart: Int?
)

data class ChapterTransitionAction(
    val direction: Int,
    val anchorParagraphIndex: Int
)

class ChapterTransitionPolicy(
    private val cooldownMs: Long = 800
) {
    private var lastSwitchTime = 0L

    fun evaluate(
        firstVisibleIndex: Int,
        isScrolling: Boolean,
        isInfiniteScrollEnabled: Boolean,
        isMangaMode: Boolean,
        readingMode: ReadingMode,
        offsets: SectionOffsets
    ): ChapterTransitionAction? {
        if (!isInfiniteScrollEnabled || isMangaMode || readingMode != ReadingMode.Vertical) return null
        if (isScrolling) return null
        val now = System.currentTimeMillis()
        if (now - lastSwitchTime < cooldownMs) return null

        val nextStart = offsets.nextStart
        if (nextStart != null && firstVisibleIndex >= nextStart + 1) {
            val anchorIndex = (firstVisibleIndex - nextStart - 1).coerceAtLeast(0)
            lastSwitchTime = now
            return ChapterTransitionAction(direction = 1, anchorParagraphIndex = anchorIndex)
        }

        val prevStart = offsets.prevStart
        if (prevStart != null && firstVisibleIndex <= offsets.currentStart - 2) {
            val anchorIndex = (firstVisibleIndex - prevStart - 1).coerceAtLeast(0)
            lastSwitchTime = now
            return ChapterTransitionAction(direction = -1, anchorParagraphIndex = anchorIndex)
        }

        return null
    }

    fun resetCooldown() {
        lastSwitchTime = 0L
    }
}
