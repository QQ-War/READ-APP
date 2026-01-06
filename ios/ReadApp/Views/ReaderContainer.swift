import SwiftUI
import UIKit
import Combine

// MARK: - SwiftUI 桥接入口
struct ReaderContainerRepresentable: UIViewControllerRepresentable {
    let book: Book
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var ttsManager: TTSManager
    
    var onToggleMenu: () -> Void
    var onShowChapterList: () -> Void
    var onAddReplaceRule: (String) -> Void
    var onProgressChanged: (Int, Double) -> Void
    
    var pendingChapterIndex: Int?
    var readingMode: ReadingMode
    
    func makeUIViewController(context: Context) -> ReaderContainerViewController {
        let vc = ReaderContainerViewController()
        vc.book = book
        vc.preferences = preferences
        vc.ttsManager = ttsManager
        vc.onToggleMenu = onToggleMenu
        vc.onAddReplaceRule = onAddReplaceRule
        vc.onProgressChanged = onProgressChanged
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        vc.updatePreferences(preferences)
        if let chapterIndex = pendingChapterIndex, vc.currentChapterIndex != chapterIndex {
            vc.jumpToChapter(chapterIndex)
        }
        if vc.currentReadingMode != readingMode {
            vc.switchReadingMode(to: readingMode)
        }
        vc.syncTTSState()
    }
}

// MARK: - UIKit 核心容器
class ReaderContainerViewController: UIViewController {
    var book: Book!
    var chapters: [BookChapter] = []
    var preferences: UserPreferences!
    var ttsManager: TTSManager!
    var onToggleMenu: (() -> Void)?
    var onAddReplaceRule: (() -> Void)? // 修改签名以匹配内部逻辑
    var onAddReplaceRuleWithText: ((String) -> Void)?
    var onProgressChanged: ((Int, Double) -> Void)?
    
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentReadingMode: ReadingMode = .vertical
    private var contentSentences: [String] = []
    private var isLoading = false
    
    private var verticalVC: VerticalTextViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        currentChapterIndex = book.durChapterIndex ?? 0
        currentReadingMode = preferences.readingMode
        loadChapters()
    }
    
    func updatePreferences(_ prefs: UserPreferences) {
        self.preferences = prefs
        verticalVC?.update(sentences: contentSentences, fontSize: prefs.fontSize, lineSpacing: prefs.lineSpacing, margin: prefs.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlaying: ttsManager.isPlaying)
    }
    
    func jumpToChapter(_ index: Int) {
        currentChapterIndex = index
        loadChapterContent(at: index, resetOffset: true)
    }
    
    func switchReadingMode(to mode: ReadingMode) {
        currentReadingMode = mode
        setupReaderMode()
    }
    
    func syncTTSState() {
        if currentReadingMode == .vertical {
            verticalVC?.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: ttsManager.currentSentenceIndex, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying)
            if ttsManager.isPlaying { verticalVC?.ensureSentenceVisible(index: ttsManager.currentSentenceIndex) }
        }
    }

    private func loadChapters() {
        Task {
            do {
                let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
                await MainActor.run { self.chapters = list; loadChapterContent(at: currentChapterIndex) }
            } catch { print("加载目录失败") }
        }
    }
    
    private func loadChapterContent(at index: Int, resetOffset: Bool = false) {
        guard index < chapters.count else { return }
        Task {
            do {
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index)
                await MainActor.run {
                    let cleaned = removeHTMLAndSVG(content)
                    self.contentSentences = cleaned.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    setupReaderMode()
                    if resetOffset { verticalVC?.scrollToTop(animated: false) }
                }
            } catch { print("加载内容失败") }
        }
    }
    
    private func setupReaderMode() {
        verticalVC?.view.removeFromSuperview()
        verticalVC?.removeFromParent()
        if currentReadingMode == .vertical {
            let v = VerticalTextViewController()
            v.onVisibleIndexChanged = { [weak self] idx in
                self?.onProgressChanged?(self?.currentChapterIndex ?? 0, Double(idx) / Double(max(1, self?.contentSentences.count ?? 1)))
            }
            v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }
            addChild(v)
            view.addSubview(v.view)
            v.view.frame = view.bounds
            v.didMove(toParent: self)
            v.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlaying: ttsManager.isPlaying)
            self.verticalVC = v
        }
    }

    private func removeHTMLAndSVG(_ text: String) -> String {
        var res = text
        let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "")
            }
        }
        return res.replacingOccurrences(of: "&nbsp;", with: " ")
    }
}