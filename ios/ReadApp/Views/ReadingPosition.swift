import Foundation

struct ReadingPosition: Equatable {
    let chapterIndex: Int
    let sentenceIndex: Int
    let sentenceOffset: Int
    let charOffset: Int
    
    var isAtChapterStart: Bool {
        sentenceIndex == 0 && sentenceOffset == 0
    }
}
