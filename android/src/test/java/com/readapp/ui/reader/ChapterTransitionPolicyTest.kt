package com.readapp.ui.reader

import com.readapp.data.ReadingMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChapterTransitionPolicyTest {
    @Test
    fun `returns action for next chapter when past boundary`() {
        val policy = ChapterTransitionPolicy(cooldownMs = 0)
        val offsets = SectionOffsets(
            currentStart = 0,
            currentEndExclusive = 10,
            prevStart = null,
            nextStart = 10
        )

        val action = policy.evaluate(
            firstVisibleIndex = 12,
            isScrolling = false,
            isInfiniteScrollEnabled = true,
            isMangaMode = false,
            readingMode = ReadingMode.Vertical,
            offsets = offsets
        )

        assertEquals(1, action?.direction)
        assertEquals(1, action?.anchorParagraphIndex)
    }

    @Test
    fun `returns action for previous chapter when above boundary`() {
        val policy = ChapterTransitionPolicy(cooldownMs = 0)
        val offsets = SectionOffsets(
            currentStart = 10,
            currentEndExclusive = 20,
            prevStart = 0,
            nextStart = null
        )

        val action = policy.evaluate(
            firstVisibleIndex = 8,
            isScrolling = false,
            isInfiniteScrollEnabled = true,
            isMangaMode = false,
            readingMode = ReadingMode.Vertical,
            offsets = offsets
        )

        assertEquals(-1, action?.direction)
        assertEquals(7, action?.anchorParagraphIndex)
    }

    @Test
    fun `honors cooldown between switches`() {
        val policy = ChapterTransitionPolicy(cooldownMs = 100000)
        val offsets = SectionOffsets(
            currentStart = 0,
            currentEndExclusive = 10,
            prevStart = null,
            nextStart = 10
        )

        val first = policy.evaluate(
            firstVisibleIndex = 12,
            isScrolling = false,
            isInfiniteScrollEnabled = true,
            isMangaMode = false,
            readingMode = ReadingMode.Vertical,
            offsets = offsets
        )
        val second = policy.evaluate(
            firstVisibleIndex = 12,
            isScrolling = false,
            isInfiniteScrollEnabled = true,
            isMangaMode = false,
            readingMode = ReadingMode.Vertical,
            offsets = offsets
        )

        assertEquals(1, first?.direction)
        assertNull(second)
    }
}
