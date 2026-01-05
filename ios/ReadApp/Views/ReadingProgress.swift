import Foundation

// MARK: - Reading Progress
extension ReadingView {
    func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil
            let bodyIndex = currentProgressBodyCharIndex()
            if let index = bodyIndex {
                preferences.saveReadingProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, pageIndex: currentPageIndex, bodyCharIndex: index)
            }
            let pos = progressRatio(for: bodyIndex)
            try? await apiService.saveBookProgress(bookUrl: bookUrl, index: currentChapterIndex, pos: pos, title: title)
        }
    }

    private func progressRatio(for bodyIndex: Int?) -> Double {
        guard let bodyIndex = bodyIndex else { return 0 }
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: contentSentences)
        let bodyLength = (pStarts.last ?? 0) + (contentSentences.last?.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count ?? 0)
        guard bodyLength > 0 else { return 0 }
        let clamped = max(0, min(bodyIndex, max(0, bodyLength - 1)))
        return Double(clamped) / Double(bodyLength)
    }

    private func currentProgressBodyCharIndex() -> Int? {
        if preferences.readingMode == .horizontal {
            guard let range = pageRange(for: currentPageIndex) else { return nil }
            let offset = max(0, min(range.length - 1, range.length / 2))
            return max(0, range.location - currentCache.chapterPrefixLen + offset)
        }
        let sentenceIndex = currentVisibleSentenceIndex ?? lastTTSSentenceIndex ?? 0
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: contentSentences)
        guard pStarts.indices.contains(sentenceIndex) else { return nil }
        return pStarts[sentenceIndex]
    }
}
