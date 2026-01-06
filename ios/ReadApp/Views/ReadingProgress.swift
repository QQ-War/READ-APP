import Foundation

// MARK: - Reading Progress
extension ReadingView {
    func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil
            // 在新架构下，进度比例 pos 由 ReaderContainer 异步汇报并可能已暂存在某个状态中
            // 目前先实现基础的章节存盘
            preferences.saveReadingProgress(bookUrl: bookUrl, chapterIndex: currentChapterIndex, pageIndex: 0, bodyCharIndex: 0)
            try? await apiService.saveBookProgress(bookUrl: bookUrl, index: currentChapterIndex, pos: 0, title: title)
        }
    }
}