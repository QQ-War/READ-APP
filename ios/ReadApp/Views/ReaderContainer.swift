import SwiftUI
import UIKit
import Combine

// MARK: - SwiftUI 桥接入口
struct ReaderContainerRepresentable: UIViewControllerRepresentable {
    let book: Book
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var ttsManager: TTSManager
    
    // 回调给 SwiftUI 的事件
    var onToggleMenu: () -> Void
    var onShowChapterList: () -> Void
    var onAddReplaceRule: (String) -> Void
    var onProgressChanged: (Int, Double) -> Void // 章节索引, 进度比例
    
    // 指令 (SwiftUI -> UIKit)
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
        // 更新偏好设置
        vc.updatePreferences(preferences)
        
        // 处理外部跳章指令
        if let chapterIndex = pendingChapterIndex, vc.currentChapterIndex != chapterIndex {
            vc.jumpToChapter(chapterIndex)
        }
        
        // 模式切换（容器内部处理无损转换）
        if vc.currentReadingMode != readingMode {
            vc.switchReadingMode(to: readingMode)
        }
        
        // TTS 状态同步
        vc.syncTTSState()
    }
}

// MARK: - UIKit 核心容器
class ReaderContainerViewController: UIViewController {
    // 数据源
    var book: Book!
    var chapters: [BookChapter] = []
    var preferences: UserPreferences!
    var ttsManager: TTSManager!
    
    // 回调
    var onToggleMenu: (() -> Void)?
    var onAddReplaceRule: ((String) -> Void)?
    var onProgressChanged: ((Int, Double) -> Void)?
    
    // 状态
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentReadingMode: ReadingMode = .vertical
    private var contentSentences: [String] = []
    private var isLoading = false
    
    // 子控制器
    private var verticalVC: VerticalTextViewController?
    private var horizontalVC: UIPageViewController? // 后续补全
    
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        // 初始加载
        currentChapterIndex = book.durChapterIndex ?? 0
        currentReadingMode = preferences.readingMode
        
        loadChapters()
    }
    
    func updatePreferences(_ prefs: UserPreferences) {
        self.preferences = prefs
        // 如果字号变了，通知子视图重排
        verticalVC?.update(
            sentences: contentSentences,
            fontSize: prefs.fontSize,
            lineSpacing: prefs.lineSpacing,
            margin: prefs.pageHorizontalMargin,
            highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil,
            secondaryIndices: [], // 暂时简化
            isPlaying: ttsManager.isPlaying
        )
    }
    
    func jumpToChapter(_ index: Int) {
        guard index >= 0 && index < chapters.count else { return }
        currentChapterIndex = index
        loadChapterContent(at: index, resetOffset: true)
    }
    
    func switchReadingMode(to mode: ReadingMode) {
        let oldMode = currentReadingMode
        currentReadingMode = mode
        
        // 核心：在内存中直接计算进度转换
        // 如果从垂直切水平，获取当前垂直的 index，反推水平页码
        // 逻辑待后续细化，目前先实现基础切换
        setupReaderMode()
    }
    
    func syncTTSState() {
        // 将 TTSManager 的状态同步给当前的渲染器
        if currentReadingMode == .vertical {
            verticalVC?.update(
                sentences: contentSentences,
                fontSize: preferences.fontSize,
                lineSpacing: preferences.lineSpacing,
                margin: preferences.pageHorizontalMargin,
                highlightIndex: ttsManager.currentSentenceIndex,
                secondaryIndices: Set(ttsManager.preloadedIndices),
                isPlaying: ttsManager.isPlaying
            )
            if ttsManager.isPlaying {
                verticalVC?.ensureSentenceVisible(index: ttsManager.currentSentenceIndex)
            }
        }
    }

    private func loadChapters() {
        Task {
            do {
                let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
                await MainActor.run {
                    self.chapters = list
                    loadChapterContent(at: currentChapterIndex)
                }
            } catch {
                print("加载目录失败: \(error)")
            }
        }
    }
    
    private func loadChapterContent(at index: Int, resetOffset: Bool = false) {
        guard index < chapters.count else { return }
        let chapter = chapters[index]
        
        Task {
            do {
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index)
                await MainActor.run {
                    // 分句
                    self.contentSentences = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    setupReaderMode()
                    if resetOffset {
                        verticalVC?.scrollToTop(animated: false)
                    }
                }
            } catch {
                print("加载内容失败: \(error)")
            }
        }
    }
    
    private func setupReaderMode() {
        // 移除旧视图
        verticalVC?.view.removeFromSuperview()
        verticalVC?.removeFromParent()
        
        if currentReadingMode == .vertical {
            let v = VerticalTextViewController()
            v.onVisibleIndexChanged = { [weak self] idx in
                self?.onProgressChanged?(self?.currentChapterIndex ?? 0, Double(idx) / Double(max(1, self?.contentSentences.count ?? 1)))
            }
            v.onAddReplaceRule = onAddReplaceRule
            
            addChild(v)
            view.addSubview(v.view)
            v.view.frame = view.bounds
            v.didMove(toParent: self)
            
            v.update(
                sentences: contentSentences,
                fontSize: preferences.fontSize,
                lineSpacing: preferences.lineSpacing,
                margin: preferences.pageHorizontalMargin,
                highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil,
                secondaryIndices: [],
                isPlaying: ttsManager.isPlaying
            )
            self.verticalVC = v
        }
        // TODO: 水平翻页模式集成
    }
}
