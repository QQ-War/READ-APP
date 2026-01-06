import SwiftUI
import UIKit
import Combine

// MARK: - 辅助模型
struct PaginatedPage {
    let range: NSRange
    let startSentenceIndex: Int
}

// MARK: - SwiftUI 桥接入口
struct ReaderContainerRepresentable: UIViewControllerRepresentable {
    let book: Book
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var ttsManager: TTSManager
    
    var onToggleMenu: () -> Void
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
        vc.onAddReplaceRuleWithText = onAddReplaceRule
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
class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    // 外部依赖
    var book: Book!
    var chapters: [BookChapter] = []
    var preferences: UserPreferences!
    var ttsManager: TTSManager!
    
    // 回调
    var onToggleMenu: (() -> Void)?
    var onAddReplaceRuleWithText: ((String) -> Void)?
    var onProgressChanged: ((Int, Double) -> Void)?
    
    // 状态核心
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentReadingMode: ReadingMode = .vertical
    private var contentSentences: [String] = []
    private var renderStore: TextKit2RenderStore?
    
    // 进度锚点 (Source of Truth)
    private var currentCharOffset: Int = 0 
    
    // 子组件
    private var verticalVC: VerticalTextViewController?
    private var horizontalVC: UIPageViewController?
    
    // 分页缓存
    private var pages: [PaginatedPage] = []
    private var currentPageIndex: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        currentChapterIndex = book.durChapterIndex ?? 0
        currentReadingMode = preferences.readingMode
        loadChapters()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 确保容器尺寸变化时更新布局
        if let v = verticalVC { v.view.frame = view.bounds }
        if let h = horizontalVC { h.view.frame = view.bounds }
    }

    func updatePreferences(_ prefs: UserPreferences) {
        self.preferences = prefs
        // 如果字体变了，需要重新计算排版和页码
        if renderStore != nil {
            loadChapterContent(at: currentChapterIndex, maintainOffset: true)
        }
    }
    
    func jumpToChapter(_ index: Int) {
        currentChapterIndex = index
        loadChapterContent(at: index, resetOffset: true)
    }
    
    func switchReadingMode(to mode: ReadingMode) {
        // 1. 捕获当前进度偏移
        captureCurrentProgress()
        
        // 2. 切换模式
        currentReadingMode = mode
        setupReaderMode()
        
        // 3. 应用进度偏移
        applyCapturedProgress()
    }
    
    private func captureCurrentProgress() {
        if currentReadingMode == .vertical, let v = verticalVC {
            // 从垂直视图获取当前第一行字符偏移
            currentCharOffset = v.getCurrentCharOffset()
        } else if currentReadingMode == .horizontal {
            // 从当前页获取偏移
            if currentPageIndex < pages.count {
                currentCharOffset = pages[currentPageIndex].range.location
            }
        }
    }
    
    private func applyCapturedProgress() {
        if currentReadingMode == .vertical {
            verticalVC?.scrollToCharOffset(currentCharOffset, animated: false)
        } else if currentReadingMode == .horizontal {
            let targetPage = pages.firstIndex(where: { NSLocationInRange(currentCharOffset, $0.range) }) ?? 0
            updateHorizontalPage(to: targetPage, animated: false)
        }
    }

    func syncTTSState() {
        let hIndex = ttsManager.currentSentenceIndex
        if currentReadingMode == .vertical {
            verticalVC?.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: hIndex, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying)
            if ttsManager.isPlaying { verticalVC?.ensureSentenceVisible(index: hIndex) }
        } else if currentReadingMode == .horizontal {
            // 水平高亮与翻页逻辑...
            if ttsManager.isPlaying {
                syncHorizontalPageToTTS(sentenceIndex: hIndex)
            }
        }
    }

    // MARK: - 数据加载
    private func loadChapters() {
        Task {
            do {
                let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
                await MainActor.run { 
                    self.chapters = list
                    loadChapterContent(at: currentChapterIndex) 
                } 
            } catch { print("加载目录失败") }
        }
    }
    
    private func loadChapterContent(at index: Int, resetOffset: Bool = false, maintainOffset: Bool = false) {
        guard index >= 0 && index < chapters.count else { return }
        Task {
            do {
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index)
                await MainActor.run {
                    let cleaned = removeHTMLAndSVG(content)
                    self.contentSentences = cleaned.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    
                    // 构建 RenderStore
                    prepareRenderStore()
                    
                    // 如果是水平模式，执行分页
                    if currentReadingMode == .horizontal {
                        performPagination()
                    }
                    
                    setupReaderMode()
                    
                    if resetOffset {
                        verticalVC?.scrollToTop(animated: false)
                        updateHorizontalPage(to: 0, animated: false)
                    } else if maintainOffset {
                        applyCapturedProgress()
                    }
                }
            } catch { print("加载内容失败") }
        }
    }
    
    private func prepareRenderStore() {
        let fullText = contentSentences.joined(separator: "\n")
        let attrString = NSAttributedString(string: fullText, attributes: [
            .font: UIFont.systemFont(ofSize: preferences.fontSize),
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = preferences.lineSpacing
                p.paragraphSpacing = preferences.lineSpacing * 0.8
                return p
            }()
        ])
        let width = view.bounds.width > 0 ? view.bounds.width - preferences.pageHorizontalMargin * 2 : 350
        if let store = renderStore {
            store.update(attributedString: attrString, layoutWidth: width)
        } else {
            renderStore = TextKit2RenderStore(attributedString: attrString, layoutWidth: width)
        }
    }
    
    private func performPagination() {
        guard let store = renderStore else { return }
        let pStarts = calculateParagraphStarts()
        let result = TextKit2Paginator.paginate(
            renderStore: store,
            pageSize: view.bounds.size,
            paragraphStarts: pStarts,
            prefixLen: 0,
            contentInset: 20
        )
        self.pages = result.pageInfos.map { PaginatedPage(range: $0.range, startSentenceIndex: $0.startSentenceIndex) }
    }
    
    private func calculateParagraphStarts() -> [Int] {
        var starts: [Int] = []
        var currentPos = 0
        for s in contentSentences {
            starts.append(currentPos)
            currentPos += s.count + 1
        }
        return starts
    }

    // MARK: - 模式切换核心
    private func setupReaderMode() {
        // 清理旧视图
        verticalVC?.view.removeFromSuperview(); verticalVC?.removeFromParent(); verticalVC = nil
        horizontalVC?.view.removeFromSuperview(); horizontalVC?.removeFromParent(); horizontalVC = nil
        
        if currentReadingMode == .vertical {
            let v = VerticalTextViewController()
            v.onVisibleIndexChanged = { [weak self] idx in
                self?.onProgressChanged?(self?.currentChapterIndex ?? 0, Double(idx) / Double(max(1, self?.contentSentences.count ?? 1)))
            }
            v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }
            v.onTapMenu = { [weak self] in self?.onToggleMenu?() }
            
            addChild(v)
            view.addSubview(v.view)
            v.view.frame = view.bounds
            v.didMove(toParent: self)
            v.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlaying: ttsManager.isPlaying)
            self.verticalVC = v
        } else {
            // 水平翻页模式
            let h = UIPageViewController(transitionStyle: preferences.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil)
            h.dataSource = self
            h.delegate = self
            
            addChild(h)
            view.addSubview(h.view)
            h.view.frame = view.bounds
            h.didMove(toParent: self)
            self.horizontalVC = h
            
            updateHorizontalPage(to: currentPageIndex, animated: false)
        }
    }

    // MARK: - UIPageViewController Logic
    private func updateHorizontalPage(to index: Int, animated: Bool) {
        guard let h = horizontalVC, index >= 0 && index < pages.count else { return }
        currentPageIndex = index
        let vc = createPageVC(at: index)
        h.setViewControllers([vc], direction: .forward, animated: animated)
    }
    
    private func createPageVC(at index: Int) -> UIViewController {
        let vc = UIViewController()
        let pageView = ReadContent2View(frame: .zero)
        pageView.renderStore = renderStore
        if index < pages.count {
            let page = pages[index]
            // 这里利用现有的 TK2PageInfo 结构
            pageView.pageInfo = TK2PageInfo(range: page.range, yOffset: 0, pageHeight: view.bounds.height, actualContentHeight: view.bounds.height, startSentenceIndex: page.startSentenceIndex, contentInset: 20)
        }
        pageView.onTapLocation = { [weak self] loc in
            if loc == .middle { self?.onToggleMenu?() }
            else { self?.handlePageTap(isNext: loc == .right) }
        }
        vc.view.addSubview(pageView)
        pageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: vc.view.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            pageView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
        ])
        return vc
    }
    
    private func handlePageTap(isNext: Bool) {
        let target = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        if target >= 0 && target < pages.count {
            updateHorizontalPage(to: target, animated: true)
        } else if isNext {
            jumpToChapter(currentChapterIndex + 1)
        } else {
            jumpToChapter(currentChapterIndex - 1)
        }
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        return currentPageIndex > 0 ? createPageVC(at: currentPageIndex - 1) : nil
    }
    
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        return currentPageIndex < pages.count - 1 ? createPageVC(at: currentPageIndex + 1) : nil
    }
    
    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let visibleVC = pvc.viewControllers?.first {
            // 获取新页面的索引并同步状态
            if let pageView = visibleVC.view.subviews.first(where: { $0 is ReadContent2View }) as? ReadContent2View,
               let range = pageView.pageInfo?.range {
                if let index = pages.firstIndex(where: { $0.range == range }) {
                    self.currentPageIndex = index
                    self.currentCharOffset = range.location
                    self.onProgressChanged?(currentChapterIndex, Double(index) / Double(max(1, pages.count)))
                }
            }
        }
    }

    private func syncHorizontalPageToTTS(sentenceIndex: Int) {
        let pStarts = calculateParagraphStarts()
        guard sentenceIndex < pStarts.count else { return }
        let offset = pStarts[sentenceIndex]
        if let targetPage = pages.firstIndex(where: { NSLocationInRange(offset, $0.range) }), targetPage != currentPageIndex {
            updateHorizontalPage(to: targetPage, animated: true)
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
