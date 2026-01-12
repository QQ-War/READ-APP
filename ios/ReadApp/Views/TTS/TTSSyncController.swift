import Foundation

struct TTSStartContext {
    let rawContent: String
    let chapters: [BookChapter]
    let currentIndex: Int
    let bookUrl: String
    let bookSourceUrl: String?
    let bookTitle: String
    let coverUrl: String?
    let processedSentences: [String]
    let startPosition: ReadingPosition
    let onChapterChange: (Int) -> Void
    let textProcessor: ((String) -> String)?
    let replaceRules: [ReplaceRule]?
}

final class TTSSyncController {
    private let ttsManager: TTSManager
    
    init(ttsManager: TTSManager) {
        self.ttsManager = ttsManager
    }
    
    func toggle(startContext: () -> TTSStartContext?) {
        if ttsManager.isPlaying {
            if ttsManager.isPaused { ttsManager.resume() }
            else { ttsManager.pause() }
            return
        }
        guard let ctx = startContext() else { return }
        ttsManager.startReading(
            text: ctx.rawContent,
            chapters: ctx.chapters,
            currentIndex: ctx.currentIndex,
            bookUrl: ctx.bookUrl,
            bookSourceUrl: ctx.bookSourceUrl,
            bookTitle: ctx.bookTitle,
            coverUrl: ctx.coverUrl,
            onChapterChange: ctx.onChapterChange,
            processedSentences: ctx.processedSentences,
            textProcessor: ctx.textProcessor,
            replaceRules: ctx.replaceRules,
            startAtSentenceIndex: ctx.startPosition.sentenceIndex,
            startAtSentenceOffset: ctx.startPosition.sentenceOffset,
            shouldSpeakChapterTitle: ctx.startPosition.isAtChapterStart
        )
    }
    
    func syncReading(isMangaMode: Bool, isUserInteracting: Bool, readingMode: ReadingMode, sentenceIndex: Int, onVertical: (Int) -> Void, onHorizontal: (Int) -> Void) {
        if isMangaMode || isUserInteracting { return }
        if readingMode == .vertical {
            onVertical(sentenceIndex)
        } else if ttsManager.isPlaying {
            onHorizontal(sentenceIndex)
        }
    }
}
