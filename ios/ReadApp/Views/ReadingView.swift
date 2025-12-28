import SwiftUI
import UIKit

// MARK: - ReadingView (Main View)
struct ReadingView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var apiService: APIService
    @StateObject private var ttsManager = TTSManager.shared
    @StateObject private var preferences = UserPreferences.shared
    @StateObject private var replaceRuleViewModel = ReplaceRuleViewModel()

    // Chapter & Content State
    @State private var chapters: [BookChapter] = []
    @State private var currentChapterIndex: Int
    
    // Pagination Engine
    @State private var paginator: TextKitPaginator?
    @State private var currentPageIndex: Int = 0
    @State private var pendingJumpToLastPage = false
    
    // UI State
    @State private var isLoading = false
    @State private var showChapterList = false
    @State private var showFontSettings = false
    @State private var showUIControls = false
    @State private var errorMessage: String?
    
    // Progress Tracking
    @State private var lastReadSentenceIndex: Int?

    init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.durChapterIndex ?? 0)
        _lastReadSentenceIndex = State(initialValue: Int(book.durChapterPos ?? 0))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundView
                mainContent(geometry: proxy)
                
                if showUIControls {
                    topBar(safeArea: proxy.safeAreaInsets)
                    bottomBar(safeArea: proxy.safeAreaInsets)
                }
                
                if isLoading { loadingOverlay }
            }
            .animation(.easeInOut(duration: 0.2), value: showUIControls)
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
        .sheet(isPresented: $showChapterList) { chapterListSheet }
        .sheet(isPresented: $showFontSettings) { fontSettingsSheet }
        .task {
            await loadChapters()
            await replaceRuleViewModel.fetchRules()
        }
        .onDisappear(perform: saveProgress)
        .onChange(of: ttsManager.isPlaying) { isPlaying in
            if !isPlaying, ttsManager.currentSentenceIndex > 0 {
                lastReadSentenceIndex = ttsManager.currentSentenceIndex
            }
        }
    }
    
    // MARK: - Subviews
    private var backgroundView: some View { Color(UIColor.systemBackground) }

    @ViewBuilder
    private func mainContent(geometry: GeometryProxy) -> some View {
        if preferences.readingMode == .horizontal {
            horizontalReader(geometry: geometry)
        } else {
            verticalReader(geometry: geometry)
        }
    }

    private func horizontalReader(geometry: GeometryProxy) -> some View {
        // Define desired margins *within* the safe area
        let horizontalMargin: CGFloat = 10
        let verticalMargin: CGFloat = 10
        let safeArea = geometry.safeAreaInsets
        
        // The precise size for both pagination and rendering
        let contentSize = CGSize(
            width: max(0, geometry.size.width - safeArea.leading - safeArea.trailing - horizontalMargin * 2),
            height: max(0, geometry.size.height - safeArea.top - safeArea.bottom - verticalMargin * 2)
        )

        return VStack {
            if let paginator = paginator {
                ZStack(alignment: .bottomTrailing) {
                    ReadPageViewController(
                        paginator: paginator,
                        currentPageIndex: $currentPageIndex,
                        onTapMiddle: { showUIControls.toggle() },
                        onTapLeft: { goToPreviousPage() },
                        onTapRight: { goToNextPage() },
                        onSwipeToPreviousChapter: {
                            if currentChapterIndex > 0 {
                                pendingJumpToLastPage = true
                                previousChapter()
                            }
                        },
                        onSwipeToNextChapter: {
                            if currentChapterIndex < chapters.count - 1 {
                                nextChapter()
                            }
                        }
                    )
                    
                    if !showUIControls && paginator.pageCount > 0 {
                        let percentage = Int((Double(currentPageIndex + 1) / Double(paginator.pageCount)) * 100)
                        Text("\(currentPageIndex + 1)/\(paginator.pageCount) (\(percentage)%) ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .onAppear {
                    // This is necessary in case the view appears/disappears without content change
                    if paginator.pageSize != contentSize {
                        repaginateContent(for: paginator.rawContent, size: contentSize)
                    }
                }
                .onChange(of: geometry.size) { _ in
                    repaginateContent(for: paginator.rawContent, size: contentSize)
                }
            } else {
                // Show a progress view while the paginator is being created
                ProgressView()
            }
        }
        .padding(.top, safeArea.top + verticalMargin)
        .padding(.bottom, safeArea.bottom + verticalMargin)
        .padding(.horizontal, safeArea.leading + horizontalMargin)
        .frame(width: geometry.size.width, height: geometry.size.height)
    }

    private func verticalReader(geometry: GeometryProxy) -> some View {
        // Vertical reader implementation remains unchanged
        // ...
        Text("Vertical Reader (Not shown in this refactor)")
    }
    
    // MARK: - Pagination and Navigation
    
    private func repaginateContent(for content: String, size: CGSize) {
        guard !content.isEmpty, size.width > 0, size.height > 0 else {
            self.paginator = nil
            return
        }
        
        let chapterTitle = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil
        let newPaginator = TextKitPaginator(
            content: content,
            chapterTitle: chapterTitle,
            pageSize: size,
            fontSize: preferences.fontSize,
            lineSpacing: preferences.lineSpacing
        )
        self.paginator = newPaginator
        
        // After repagination, jump to the correct page
        if pendingJumpToLastPage {
            currentPageIndex = max(0, newPaginator.pageCount - 1)
            pendingJumpToLastPage = false
        } else {
            if let sentenceIndex = lastReadSentenceIndex, let pageIndex = newPaginator.pageIndex(for: sentenceIndex) {
                currentPageIndex = pageIndex
            } else {
                currentPageIndex = 0
            }
        }
    }
    
    private func goToPreviousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        } else {
            if currentChapterIndex > 0 {
                pendingJumpToLastPage = true
                previousChapter()
            }
        }
    }

    private func goToNextPage() {
        if let paginator = paginator, currentPageIndex < paginator.pageCount - 1 {
            currentPageIndex += 1
        } else {
            if currentChapterIndex < chapters.count - 1 {
                nextChapter()
            }
        }
    }

    // MARK: - Data Loading & Content Processing
    
    private func loadChapters() async {
        isLoading = true
        do {
            chapters = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            await loadChapterContent()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func loadChapterContent() async {
        guard currentChapterIndex < chapters.count else { return }
        isLoading = true
        paginator = nil // Clear old paginator
        do {
            let content = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: currentChapterIndex)
            await MainActor.run {
                let cleanedContent = removeHTMLAndSVG(content)
                let processedContent = applyReplaceRules(to: cleanedContent)
                
                // Set initial paginator in onAppear of horizontalReader
                // Store raw content for repagination on font change
                self.rawContent = processedContent.isEmpty ? "章节内容为空" : processedContent
                
                // Defer pagination until view size is known
                isLoading = false
                preloadNextChapter()
            }
        } catch {
            await MainActor.run {
                errorMessage = "获取章节失败: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    // ... other helper methods like previous/next chapter, saveProgress, TTS, etc.
    // These methods now call `loadChapterContent` which async loads and then triggers repagination
    private func previousChapter() { Task { await loadChapterContent() } }
    private func nextChapter() { Task { await loadChapterContent() } }
    private func saveProgress() { /* ... */ }
    private func startTTS() { /* ... */ }
    private func toggleTTS() { /* ... */ }
    private func applyReplaceRules(to content: String) -> String { /* ... */ return content }
    private func removeHTMLAndSVG(_ text: String) -> String { /* ... */ return text }
    private func splitIntoParagraphs(_ text: String) -> [String] { return text.components(separatedBy: .newlines) }
    private func preloadNextChapter() { /* ... */ }

    // MARK: - UI Components (unchanged)
    private var fontSettingsSheet: some View { /* ... */ Text("Font Settings") }
    private var chapterListSheet: some View { /* ... */ Text("Chapters") }
    private var loadingOverlay: some View { /* ... */ Text("Loading...") }
    @ViewBuilder private func topBar(safeArea: EdgeInsets) -> some View { /* ... */ }
    @ViewBuilder private func bottomBar(safeArea: EdgeInsets) -> some View { /* ... */ }
}

// MARK: - TextKit Paginator (The New Engine)
class TextKitPaginator {
    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    let pageSize: CGSize
    let rawContent: String
    private(set) var pageCount: Int = 0
    private var sentenceStartOffsets: [Int] = []

    init(content: String, chapterTitle: String?, pageSize: CGSize, fontSize: CGFloat, lineSpacing: CGFloat) {
        self.rawContent = content
        self.pageSize = pageSize
        
        let fullAttributedText = Self.createAttributedText(content: content, chapterTitle: chapterTitle, fontSize: fontSize, lineSpacing: lineSpacing)
        self.sentenceStartOffsets = Self.calculateSentenceStartOffsets(from: content)

        self.textStorage = NSTextStorage(attributedString: fullAttributedText)
        self.layoutManager = NSLayoutManager()
        self.textStorage.addLayoutManager(self.layoutManager)

        paginate()
    }
    
    private func paginate() {
        // Clear existing containers
        while let lastContainer = layoutManager.textContainers.last {
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        
        var rangeOffset = 0
        while rangeOffset < layoutManager.numberOfGlyphs {
            let textContainer = NSTextContainer(size: pageSize)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)
            
            // Force layout up to this point to get the correct used range
            layoutManager.glyphRange(for: textContainer)
            
            rangeOffset = NSMaxRange(layoutManager.glyphRange(for: textContainer))
        }
        self.pageCount = layoutManager.textContainers.count
    }
    
    func attributedString(forPage pageIndex: Int) -> NSAttributedString? {
        guard pageIndex < layoutManager.textContainers.count else { return nil }
        let container = layoutManager.textContainers[pageIndex]
        let glyphRange = layoutManager.glyphRange(for: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        guard charRange.location + charRange.length <= textStorage.length else { return nil }
        return textStorage.attributedSubstring(from: charRange)
    }

    func pageIndex(for sentenceIndex: Int) -> Int? {
        guard sentenceIndex < sentenceStartOffsets.count else { return nil }
        let charOffset = sentenceStartOffsets[sentenceIndex]
        
        for i in 0..<layoutManager.textContainers.count {
            let container = layoutManager.textContainers[i]
            let glyphRange = layoutManager.glyphRange(for: container)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if NSLocationInRange(charOffset, charRange) {
                return i
            }
        }
        return nil
    }
    
    // Static helper to create the attributed string
    private static func createAttributedText(content: String, chapterTitle: String?, fontSize: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = fontSize * 0.5
        paragraphStyle.alignment = .justified
        
        let result = NSMutableAttributedString()
        if let title = chapterTitle, !title.isEmpty {
            let titleStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            titleStyle.alignment = .center
            titleStyle.paragraphSpacing = fontSize * 2
            result.append(NSAttributedString(string: title + "\n\n", attributes: [.font: UIFont.boldSystemFont(ofSize: fontSize + 6), .paragraphStyle: titleStyle, .foregroundColor: UIColor.label]))
        }
        
        let body = content.replacingOccurrences(of: "\n", with: "\n　　")
        result.append(NSAttributedString(string: "　　" + body, attributes: [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: UIColor.label]))
        return result
    }

    private static func calculateSentenceStartOffsets(from content: String) -> [Int] {
        var offsets: [Int] = []
        var currentOffset = 0
        content.enumerateSubstrings(in: content.startIndex..., options: .byParagraphs) { substring, range, _, _ in
            guard let substring = substring, !substring.isEmpty else { return }
            offsets.append(currentOffset)
            currentOffset += substring.utf16.count
        }
        return offsets
    }
}

// MARK: - UIPageViewController Wrapper
struct ReadPageViewController: UIViewControllerRepresentable {
    let paginator: TextKitPaginator
    @Binding var currentPageIndex: Int
    
    // Callbacks
    var onTapMiddle: () -> Void
    var onTapLeft: () -> Void
    var onTapRight: () -> Void
    var onSwipeToPreviousChapter: () -> Void
    var onSwipeToNextChapter: () -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pvc.view.addGestureRecognizer(tap)
        
        context.coordinator.setupPanGesture(on: pvc.view)
        
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        
        let newIndex = currentPageIndex
        guard newIndex < paginator.pageCount else { return }
        
        let direction: UIPageViewController.NavigationDirection = {
            if let currentVC = pvc.viewControllers?.first as? ReadContentViewController {
                return newIndex > currentVC.pageIndex ? .forward : .reverse
            }
            return .forward
        }()
        
        let vc = context.coordinator.makeViewController(for: newIndex)
        pvc.setViewControllers([vc], direction: direction, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReadPageViewController

        init(_ parent: ReadPageViewController) { self.parent = parent }
        
        func makeViewController(for pageIndex: Int) -> UIViewController {
            guard pageIndex >= 0 && pageIndex < parent.paginator.pageCount else { return UIViewController() }
            let textContainer = parent.paginator.layoutManager.textContainers[pageIndex]
            return ReadContentViewController(pageIndex: pageIndex, textContainer: textContainer, layoutManager: parent.paginator.layoutManager)
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController, vc.pageIndex > 0 else { return nil }
            return makeViewController(for: vc.pageIndex - 1)
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController, vc.pageIndex < parent.paginator.pageCount - 1 else { return nil }
            return makeViewController(for: vc.pageIndex + 1)
        }
        
        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let visibleVC = pvc.viewControllers?.first as? ReadContentViewController {
                parent.currentPageIndex = visibleVC.pageIndex
            }
        }
        
        // ... Gesture handlers ...
        func setupPanGesture(on view: UIView) { /* ... */ }
        @objc func handleTap(_ gesture: UITapGestureRecognizer) { /* ... */ }
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) { /* ... */ }
    }
}

// MARK: - Content View Controller (New Initializer)
class ReadContentViewController: UIViewController {
    let pageIndex: Int
    private let textContainer: NSTextContainer
    private weak var layoutManager: NSLayoutManager?
    
    private lazy var textView: UITextView = {
        let tv = UITextView(frame: .zero, textContainer: self.textContainer)
        tv.isEditable = false; tv.isScrollEnabled = false; tv.isSelectable = false
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    init(pageIndex: Int, textContainer: NSTextContainer, layoutManager: NSLayoutManager) {
        self.pageIndex = pageIndex
        self.textContainer = textContainer
        self.layoutManager = layoutManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

// Other helper views (TTSControlBar, etc.) are omitted for brevity but should be kept
struct TTSControlBar: View { /* ... */ var body: some View { Text("TTS Controls") } }
struct NormalControlBar: View { /* ... */ var body: some View { Text("Normal Controls") } }
struct FontSizeSheet: View { /* ... */ var body: some View { Text("Font Settings") } }
struct RichTextView: View { /* ... */ var body: some View { Text("Vertical Reader") } }
struct ChapterListView: View { /* ... */ var body: some View { Text("Chapters") } }
private struct SentenceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}