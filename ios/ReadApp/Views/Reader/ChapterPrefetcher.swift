import Foundation

struct ChapterPrefetchResult {
    let store: TextKit2RenderStore
    let pages: [PaginatedPage]
    let pageInfos: [TK2PageInfo]
    let sentences: [String]
    let rawContent: String
}

final class ChapterPrefetcher {
    private var nextTask: Task<Void, Never>?
    private var prevTask: Task<Void, Never>?
    
    func cancel() {
        nextTask?.cancel()
        prevTask?.cancel()
        nextTask = nil
        prevTask = nil
    }
    
    func prefetchAdjacent(
        book: Book,
        chapters: [BookChapter],
        index: Int,
        contentType: Int,
        buildResult: @escaping (_ content: String, _ title: String) -> ChapterPrefetchResult?,
        onNext: @escaping (ChapterPrefetchResult) -> Void,
        onPrev: @escaping (ChapterPrefetchResult) -> Void
    ) {
        cancel()
        
        if index + 1 < chapters.count {
            nextTask = Task {
                if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index + 1, contentType: contentType) {
                    await MainActor.run { [weak self] in
                        guard let self = self, !(self.nextTask?.isCancelled ?? true) else { return }
                        guard let result = buildResult(content, chapters[index + 1].title) else { return }
                        onNext(result)
                    }
                }
            }
        }
        
        if index - 1 >= 0 {
            prevTask = Task {
                if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index - 1, contentType: contentType) {
                    await MainActor.run { [weak self] in
                        guard let self = self, !(self.prevTask?.isCancelled ?? true) else { return }
                        guard let result = buildResult(content, chapters[index - 1].title) else { return }
                        onPrev(result)
                    }
                }
            }
        }
    }
}
