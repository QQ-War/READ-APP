import SwiftUI
import UIKit

// MARK: - Core Types
struct PageTurnRequest: Equatable {
    let direction: UIPageViewController.NavigationDirection
    let animated: Bool
    let targetIndex: Int
    let targetSnapshot: PageSnapshot? // 跨章节时携带目标快照
    let targetChapterIndex: Int?     // 目标章节索引
    let timestamp: TimeInterval

    init(
        direction: UIPageViewController.NavigationDirection,
        animated: Bool,
        targetIndex: Int,
        targetSnapshot: PageSnapshot? = nil,
        targetChapterIndex: Int? = nil
    ) {
        self.direction = direction
        self.animated = animated
        self.targetIndex = targetIndex
        self.targetSnapshot = targetSnapshot
        self.targetChapterIndex = targetChapterIndex
        self.timestamp = Date().timeIntervalSince1970
    }
    
    static func == (lhs: PageTurnRequest, rhs: PageTurnRequest) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
}

struct PaginatedPage: Equatable {
    let globalRange: NSRange
    let startSentenceIndex: Int
}

struct TK2PageInfo {
    let range: NSRange
    let yOffset: CGFloat
    let pageHeight: CGFloat // Allocated page height (e.g., pageSize.height)
    let actualContentHeight: CGFloat // Actual height used by content on this page
    let startSentenceIndex: Int
    let contentInset: CGFloat
}

struct ChapterCache {
    let pages: [PaginatedPage]
    let renderStore: TextKit2RenderStore?
    let pageInfos: [TK2PageInfo]?
    let contentSentences: [String]
    let rawContent: String
    let attributedText: NSAttributedString
    let paragraphStarts: [Int]
    let chapterPrefixLen: Int
    let isFullyPaginated: Bool
    let chapterUrl: String? // 新增
    
    static var empty: ChapterCache {
        ChapterCache(pages: [], renderStore: nil, pageInfos: nil, contentSentences: [], rawContent: "", attributedText: NSAttributedString(), paragraphStarts: [], chapterPrefixLen: 0, isFullyPaginated: false, chapterUrl: nil)
    }
}



final class ReadContentViewControllerCache: ObservableObject {
    struct Key: Hashable {
        let storeID: ObjectIdentifier
        let pageIndex: Int
        let chapterOffset: Int
    }

    private var controllers: [Key: ReadContentViewController] = [:]

    func controller(
        for store: TextKit2RenderStore,
        pageIndex: Int,
        chapterOffset: Int,
        builder: () -> ReadContentViewController
    ) -> ReadContentViewController {
        let key = Key(storeID: ObjectIdentifier(store), pageIndex: pageIndex, chapterOffset: chapterOffset)
        if let cached = controllers[key] {
            return cached
        }
        let controller = builder()
        controllers[key] = controller
        return controller
    }

    func retainActive(stores: [TextKit2RenderStore?]) {
        let activeIDs = Set(stores.compactMap { $0.map { ObjectIdentifier($0) } })
        if activeIDs.isEmpty {
            controllers.removeAll()
            return
        }
        controllers = controllers.filter { activeIDs.contains($0.key.storeID) }
    }
}

struct PageSnapshot {
    let pages: [PaginatedPage]
    let renderStore: TextKit2RenderStore?
    let pageInfos: [TK2PageInfo]?
    let contentSentences: [String]? // 新增：保存原始句子用于漫画渲染
    let chapterUrl: String? // 新增
}
