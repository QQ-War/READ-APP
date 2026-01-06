import Foundation

// MARK: - Reading Progress
extension ReadingView {
    func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        let chapterIdx = self.currentChapterIndex
        let pos = self.currentPos
        
        Task {
            let title = chapters.indices.contains(chapterIdx) ? chapters[chapterIdx].title : nil
            // 保存到本地
            preferences.saveReadingProgress(bookUrl: bookUrl, chapterIndex: chapterIdx, pageIndex: 0, bodyCharIndex: Int(pos * 10000))
            // 保存到服务器
            try? await apiService.saveBookProgress(bookUrl: bookUrl, index: chapterIdx, pos: pos, title: title)
        }
    }
}
