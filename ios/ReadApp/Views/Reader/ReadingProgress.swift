import Foundation

// MARK: - Reading Progress
extension ReadingView {
    func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        let chapterIdx = self.currentChapterIndex
        let pos = self.currentPos
        let title = chapters.indices.contains(chapterIdx) ? chapters[chapterIdx].title : nil

        // 立即更新本地内存状态，确保返回书架时无需等待网络请求即可看到最新进度
        Task { @MainActor in
            bookshelfStore.updateProgress(bookUrl: bookUrl, index: chapterIdx, pos: pos, title: title)
        }
        
        Task {
            // 保存到本地持久化
            preferences.saveReadingProgress(bookUrl: bookUrl, chapterIndex: chapterIdx, pageIndex: 0, bodyCharIndex: Int(pos * 10000))
            // 保存到服务器
            try? await APIService.shared.saveBookProgress(bookUrl: bookUrl, index: chapterIdx, pos: pos, title: title)
        }
    }
}
