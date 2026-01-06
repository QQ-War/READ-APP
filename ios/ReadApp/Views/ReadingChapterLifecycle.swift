import SwiftUI

// 旧排版逻辑已废弃，现在由 ReaderContainer 托管
extension ReadingView {
    func previousChapter() {
        if currentChapterIndex > 0 {
            currentChapterIndex -= 1
        }
    }
    func nextChapter() {
        if currentChapterIndex < chapters.count - 1 {
            currentChapterIndex += 1
        }
    }
    func loadChapters() async {
        do {
            let list = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            await MainActor.run { self.chapters = list }
        } catch { print("Main view load chapters failed") }
    }
}