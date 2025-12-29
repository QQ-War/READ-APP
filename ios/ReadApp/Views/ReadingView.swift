import SwiftUI
import UIKit

// MARK: - Chapter Cache
private struct ChapterCache {
    let pages: [PaginatedPage]
    let store: TextKitRenderStore?
    let contentSentences: [String]
    let attributedText: NSAttributedString
    let paragraphStarts: [Int]
    let chapterPrefixLen: Int
    
    static var empty: ChapterCache {
        ChapterCache(pages: [], store: nil, contentSentences: [], attributedText: NSAttributedString(), paragraphStarts: [], chapterPrefixLen: 0)
    }
}

// MARK: - ReadingView
struct ReadingView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var apiService: APIService
    @StateObject private var ttsManager = TTSManager.shared
    @StateObject private var preferences = UserPreferences.shared
    @StateObject private var replaceRuleViewModel = ReplaceRuleViewModel()

    @State private var chapters: [BookChapter] = []
    @State private var currentChapterIndex: Int
    @State private var currentContent = ""
    @State private var rawContent = ""
    @State private var contentSentences: [String] = []
    @State private var isLoading = false
    @State private var showChapterList = false
    @State private var errorMessage: String?
    @State private var showUIControls = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var lastTTSSentenceIndex: Int?
    @State private var currentVisibleSentenceIndex: Int?
    @State private var showFontSettings = false
    
    // Pagination State
    @State private var currentPageIndex: Int = 0
    @State private var currentCache: ChapterCache = .empty
    @State private var prevCache: ChapterCache = .empty
    @State private var nextCache: ChapterCache = .empty
    @State private var pendingJumpToLastPage = false
    @State private var pendingJumpToFirstPage = false
    @State private var windowBasePageIndex: Int = 0
    @State private var windowStartCharIndex: Int = 0
    @State private var windowEndCharIndex: Int = 0
    @State private var totalPageCount: Int?
    @State private var windowHistory: [WindowAnchor] = []
    @State private var pageSize: CGSize = .zero
    @State private var isWindowShiftInProgress = false
    @State private var isPageTransitioning = false
    @State private var pendingWindowShiftAfterTransition = false
    @State private var ttsBaseIndex: Int = 0
    @State private var pendingFlipId: UUID = UUID()
    @State private var isTTSSyncingPage = false
    @State private var suppressTTSSync = false
    
    // Pagination Cache for seamless transition
    @State private var isAutoFlipping: Bool = false

    // Unified Insets for consistency
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 40
    private let maxCachedPages: Int = 40
    private let windowAdvanceThreshold: Int = 6
    private let windowOverlapPages: Int = 3

    init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.durChapterIndex ?? 0)
        _lastTTSSentenceIndex = State(initialValue: Int(book.durChapterPos ?? 0))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundView
                mainContent(safeArea: proxy.safeAreaInsets)
                
                if showUIControls {
                    topBar(safeArea: proxy.safeAreaInsets)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    bottomBar(safeArea: proxy.safeAreaInsets)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if isLoading { loadingOverlay }
            }
            .animation(.easeInOut(duration: 0.2), value: showUIControls)
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
        .sheet(isPresented: $showChapterList) {
            ChapterListView(
                chapters: chapters,
                currentIndex: currentChapterIndex,
                onSelectChapter: { index in
                    currentChapterIndex = index
                    pendingJumpToFirstPage = true
                    loadChapterContent()
                    showChapterList = false
                }
            )
        }
        .sheet(isPresented: $showFontSettings) {
            FontSizeSheet(preferences: preferences)
        }
        .task {
            await loadChapters()
            await replaceRuleViewModel.fetchRules()
        }
        .onChange(of: replaceRuleViewModel.rules) { _ in
            updateProcessedContent(from: rawContent)
        }
        .alert("错误", isPresented: .constant(errorMessage != nil)) {
            Button("确定") { errorMessage = nil }
        } message: {
            if let error = errorMessage { Text(error) }
        }
        .onDisappear {
            saveProgress()
        }
        .onChange(of: ttsManager.isPlaying) { isPlaying in
            if !isPlaying {
                showUIControls = true
                if ttsManager.currentSentenceIndex > 0 && ttsManager.currentSentenceIndex <= contentSentences.count {
                    lastTTSSentenceIndex = ttsManager.currentSentenceIndex
                }
            }
        }
        .onChange(of: ttsManager.currentSentenceIndex) { newIndex in
            if preferences.readingMode == .horizontal && ttsManager.isPlaying {
                if !suppressTTSSync {
                    syncPageForSentenceIndex(newIndex)
                }
                scheduleAutoFlip(duration: ttsManager.currentSentenceDuration)
                suppressTTSSync = false
            }
        }
        .onChange(of: ttsManager.currentSentenceDuration) { duration in
             if preferences.readingMode == .horizontal && ttsManager.isPlaying {
                 scheduleAutoFlip(duration: duration)
             }
        }
    }

    private var backgroundView: some View {
        Color(UIColor.systemBackground)
    }

    @ViewBuilder
    private func mainContent(safeArea: EdgeInsets) -> some View {
        if preferences.readingMode == .horizontal {
            horizontalReader(safeArea: safeArea)
        } else {
            verticalReader
                .padding(.top, safeArea.top)
                .padding(.bottom, safeArea.bottom)
        }
    }
    
    private var verticalReader: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    let primaryHighlight = ttsManager.isPlaying ? ttsManager.currentSentenceIndex : lastTTSSentenceIndex
                    let secondaryHighlights = ttsManager.isPlaying ? ttsManager.preloadedIndices : Set<Int>()
                    RichTextView(
                        sentences: contentSentences,
                        fontSize: preferences.fontSize,
                        lineSpacing: preferences.lineSpacing,
                        highlightIndex: primaryHighlight,
                        secondaryIndices: secondaryHighlights,
                        isPlayingHighlight: ttsManager.isPlaying,
                        scrollProxy: scrollProxy
                    )
                    .padding()
                }
                .coordinateSpace(name: "scroll")
                .contentShape(Rectangle())
                .onTapGesture {
                    showUIControls.toggle()
                }
                .onChange(of: ttsManager.currentSentenceIndex) { newIndex in
                    if ttsManager.isPlaying && !contentSentences.isEmpty {
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .onPreferenceChange(SentenceFramePreferenceKey.self) { frames in
                    updateVisibleSentenceIndex(frames: frames, viewportHeight: geometry.size.height)
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
        }
    }
    
    private func horizontalReader(safeArea: EdgeInsets) -> some View {
        GeometryReader { geometry in
            // Define desired margins *within* the safe area
            let horizontalMargin: CGFloat = preferences.pageHorizontalMargin
            let verticalMargin: CGFloat = 10
            
            let availableSize = CGSize(
                width: max(0, geometry.size.width - safeArea.leading - safeArea.trailing - horizontalMargin * 2),
                height: max(0, geometry.size.height - safeArea.top - safeArea.bottom - verticalMargin * 2)
            )

            // The precise size for both pagination and rendering
            let contentSize = availableSize

            VStack(spacing: 0) {
                Spacer().frame(height: safeArea.top + verticalMargin)
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: safeArea.leading + horizontalMargin)
                        .contentShape(Rectangle())
                        .onTapGesture { 
                            if ttsManager.isPlaying && preferences.lockPageOnTTS { return }
                            goToPreviousPage() 
                        }
                    
                    if availableSize.width > 0 && availableSize.height > 0 {
                        ZStack(alignment: .bottomTrailing) {
                            ReadPageViewController(
                                snapshot: PageSnapshot(pages: currentCache.pages, renderStore: currentCache.store),
                                prevSnapshot: PageSnapshot(pages: prevCache.pages, renderStore: prevCache.store),
                                nextSnapshot: PageSnapshot(pages: nextCache.pages, renderStore: nextCache.store),
                                currentPageIndex: $currentPageIndex,
                                isAtChapterStart: windowStartCharIndex == 0,
                                isAtChapterEnd: windowEndCharIndex >= currentCache.attributedText.length && currentCache.attributedText.length > 0,
                                isScrollEnabled: !(ttsManager.isPlaying && preferences.lockPageOnTTS),
                                onTransitioningChanged: { transitioning in
                                    isPageTransitioning = transitioning
                                    if !transitioning,
                                       pendingWindowShiftAfterTransition,
                                       !isWindowShiftInProgress,
                                       pageSize.width > 0,
                                       pageSize.height > 0 {
                                        pendingWindowShiftAfterTransition = false
                                        handleWindowShiftIfNeeded(in: pageSize)
                                    }
                                },
                                onTapMiddle: { showUIControls.toggle() },
                                onTapLeft: { 
                                    if ttsManager.isPlaying && preferences.lockPageOnTTS { return }
                                    goToPreviousPage() 
                                },
                                onTapRight: { 
                                    if ttsManager.isPlaying && preferences.lockPageOnTTS { return }
                                    goToNextPage() 
                                },
                                onChapterChange: { offset in
                                    isAutoFlipping = true
                                    handleChapterSwitch(offset: offset)
                                }
                            )
                            .frame(width: contentSize.width, height: contentSize.height)
                            
                            if !showUIControls && currentCache.pages.count > 0 {
                                let displayTotal = max(windowBasePageIndex + currentCache.pages.count, totalPageCount ?? 0)
                                let displayCurrent = windowBasePageIndex + currentPageIndex + 1
                                let safeTotal = max(displayTotal, displayCurrent)
                                let percentage = Int((Double(displayCurrent) / Double(safeTotal)) * 100)
                                Text("\(displayCurrent)/\(safeTotal) (\(percentage)%)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                                    .padding(.bottom, 2)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                            }
                        }
                        .frame(width: availableSize.width, height: availableSize.height)
                    } else {
                        // Placeholder for when size is zero
                        Rectangle().fill(Color.clear)
                    }
                    
                    Color.clear
                        .frame(width: safeArea.trailing + horizontalMargin)
                        .contentShape(Rectangle())
                        .onTapGesture { 
                            if ttsManager.isPlaying && preferences.lockPageOnTTS { return }
                            goToNextPage() 
                        }
                }
                Spacer().frame(height: safeArea.bottom + verticalMargin)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                if contentSize.width > 0 && contentSize.height > 0 {
                    pageSize = contentSize
                    repaginateContent(in: contentSize)
                }
            }
            .onChange(of: contentSentences) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    pageSize = contentSize
                    repaginateContent(in: contentSize)
                }
            }
            .onChange(of: preferences.fontSize) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    pageSize = contentSize
                    repaginateContent(in: contentSize)
                }
            }
            .onChange(of: preferences.lineSpacing) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    pageSize = contentSize
                    repaginateContent(in: contentSize)
                }
            }
            .onChange(of: preferences.pageHorizontalMargin) { _ in
                if contentSize.width > 0 && contentSize.height > 0 {
                    pageSize = contentSize
                    repaginateContent(in: contentSize)
                }
            }
            .onChange(of: geometry.size) { _ in
                 if contentSize.width > 0 && contentSize.height > 0 {
                    pageSize = contentSize
                    repaginateContent(in: contentSize)
                }
            }
            .onChange(of: currentPageIndex) { newIndex in
                // This logic handles TTS restart on manual flip
                if isTTSSyncingPage {
                    isTTSSyncingPage = false
                    if currentCache.pages.indices.contains(newIndex) {
                        lastTTSSentenceIndex = currentCache.pages[newIndex].startSentenceIndex
                    }
                    return
                }
                if ttsManager.isPlaying && !ttsManager.isPaused && !isAutoFlipping {
                    if !preferences.lockPageOnTTS {
                        ttsManager.stop()
                        startTTS(pageIndexOverride: newIndex)
                    }
                }
                isAutoFlipping = false // Reset flag after use

                if currentCache.pages.indices.contains(newIndex) {
                    lastTTSSentenceIndex = currentCache.pages[newIndex].startSentenceIndex
                }
                if isPageTransitioning {
                    pendingWindowShiftAfterTransition = true
                    return
                }
                if !isWindowShiftInProgress, pageSize.width > 0, pageSize.height > 0 {
                    handleWindowShiftIfNeeded(in: pageSize)
                }
            }
        }
    }

    // MARK: - Pagination & Navigation

    private func repaginateContent(in size: CGSize, with newContentSentences: [String]? = nil) {
        let sentences = newContentSentences ?? contentSentences
        let chapterTitle = chapters.indices.contains(currentChapterIndex)
            ? chapters[currentChapterIndex].title
            : nil

        let newAttrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: chapterTitle)
        let newPStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let newPrefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count
        
        guard newAttrText.length > 0, size.width > 0, size.height > 0 else {
            currentCache = .empty
            return
        }

        let globalPageIndex = windowBasePageIndex + currentPageIndex

        if pendingJumpToLastPage {
            buildWindowForLastPage(in: size, from: newAttrText, sentences: sentences, paragraphStarts: newPStarts, prefixLen: newPrefixLen)
            pendingJumpToLastPage = false
            pendingJumpToFirstPage = false
            return
        }

        if pendingJumpToFirstPage || currentCache.pages.isEmpty {
            windowHistory.removeAll()
            totalPageCount = nil
            applyWindow(startCharIndex: 0, basePageIndex: 0, desiredGlobalPageIndex: 0, focusCharIndex: nil, size: size, from: newAttrText, sentences: sentences, pStarts: newPStarts, prefixLen: newPrefixLen)
            pendingJumpToFirstPage = false
            return
        }

        let anchorIndex = max(0, min(currentPageIndex, currentCache.pages.count - 1))
        let dropCount = max(0, anchorIndex - windowOverlapPages)
        let startChar = currentCache.pages[dropCount].globalRange.location
        let basePage = windowBasePageIndex + dropCount
        applyWindow(startCharIndex: startChar, basePageIndex: basePage, desiredGlobalPageIndex: globalPageIndex, focusCharIndex: nil, size: size, from: newAttrText, sentences: sentences, pStarts: newPStarts, prefixLen: newPrefixLen)
    }

    private func applyWindow(startCharIndex: Int, basePageIndex: Int, desiredGlobalPageIndex: Int, focusCharIndex: Int?, size: CGSize, from sourceText: NSAttributedString, sentences: [String], pStarts: [Int], prefixLen: Int) {
        isWindowShiftInProgress = true
        let result = TextKitPaginator.paginateWindow(
            fullText: sourceText,
            paragraphStarts: pStarts,
            prefixLen: prefixLen,
            startCharIndex: startCharIndex,
            maxPages: maxCachedPages,
            size: size
        )

        let newCache = ChapterCache(
            pages: result.pages,
            store: result.renderStore,
            contentSentences: sentences,
            attributedText: sourceText,
            paragraphStarts: pStarts,
            chapterPrefixLen: prefixLen
        )
        currentCache = newCache
        
        windowStartCharIndex = result.windowStart
        windowEndCharIndex = result.windowEnd
        windowBasePageIndex = basePageIndex
        if result.reachedEnd {
            totalPageCount = basePageIndex + result.pages.count
        }

        if !result.pages.isEmpty {
            if let focusIndex = focusCharIndex,
               let page = result.pages.firstIndex(where: { NSLocationInRange(focusIndex, $0.globalRange) }) {
                currentPageIndex = page
            } else {
                let mappedIndex = desiredGlobalPageIndex - basePageIndex
                currentPageIndex = max(0, min(mappedIndex, result.pages.count - 1))
            }
        } else {
            currentPageIndex = 0
        }

        DispatchQueue.main.async {
            isWindowShiftInProgress = false
        }
    }

    private func handleWindowShiftIfNeeded(in size: CGSize) {
        guard !currentCache.pages.isEmpty, currentCache.attributedText.length > 0 else { return }
        let globalPageIndex = windowBasePageIndex + currentPageIndex
        let forwardTriggerIndex = max(0, currentCache.pages.count - windowAdvanceThreshold)

        if currentPageIndex >= forwardTriggerIndex,
           windowEndCharIndex < currentCache.attributedText.length {
            let dropCount = max(0, currentPageIndex - windowOverlapPages)
            guard dropCount > 0 else { return }
            windowHistory.append(WindowAnchor(startCharIndex: windowStartCharIndex, basePageIndex: windowBasePageIndex))
            let newStartChar = currentCache.pages[dropCount].globalRange.location
            let newBasePage = windowBasePageIndex + dropCount
            applyWindow(startCharIndex: newStartChar, basePageIndex: newBasePage, desiredGlobalPageIndex: globalPageIndex, focusCharIndex: nil, size: size, from: currentCache.attributedText, sentences: currentCache.contentSentences, pStarts: currentCache.paragraphStarts, prefixLen: currentCache.chapterPrefixLen)
        } else if currentPageIndex <= windowOverlapPages, let anchor = windowHistory.popLast() {
            applyWindow(startCharIndex: anchor.startCharIndex, basePageIndex: anchor.basePageIndex, desiredGlobalPageIndex: globalPageIndex, focusCharIndex: nil, size: size, from: currentCache.attributedText, sentences: currentCache.contentSentences, pStarts: currentCache.paragraphStarts, prefixLen: currentCache.chapterPrefixLen)
        }
    }

    private func buildWindowForLastPage(in size: CGSize, from sourceText: NSAttributedString, sentences: [String], paragraphStarts: [Int], prefixLen: Int) {
        windowHistory.removeAll()
        totalPageCount = nil

        var startChar = 0
        var baseCount = 0
        var lastResult: WindowPaginationResult?
        var history: [WindowAnchor] = []

        while startChar < sourceText.length {
            let result = TextKitPaginator.paginateWindow(
                fullText: sourceText,
                paragraphStarts: paragraphStarts,
                prefixLen: prefixLen,
                startCharIndex: startChar,
                maxPages: maxCachedPages,
                size: size
            )
            lastResult = result
            baseCount += result.pages.count
            if result.windowEnd >= sourceText.length || result.pages.isEmpty {
                break
            }
            startChar = result.windowEnd
            history.append(WindowAnchor(startCharIndex: startChar, basePageIndex: baseCount))
        }

        guard let finalResult = lastResult else { return }
        let basePageIndex = max(0, baseCount - finalResult.pages.count)
        let desiredGlobalPageIndex = max(0, baseCount - 1)
        windowHistory = history
        applyWindow(startCharIndex: finalResult.windowStart, basePageIndex: basePageIndex, desiredGlobalPageIndex: desiredGlobalPageIndex, focusCharIndex: nil, size: size, from: sourceText, sentences: sentences, pStarts: paragraphStarts, prefixLen: prefixLen)
        totalPageCount = baseCount
    }
    
    private func goToPreviousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        } else if let anchor = windowHistory.popLast(), pageSize.width > 0, pageSize.height > 0 {
            let targetGlobalPage = max(0, windowBasePageIndex - 1)
            applyWindow(
                startCharIndex: anchor.startCharIndex,
                basePageIndex: anchor.basePageIndex,
                desiredGlobalPageIndex: targetGlobalPage,
                focusCharIndex: nil,
                size: pageSize,
                from: currentCache.attributedText,
                sentences: currentCache.contentSentences,
                pStarts: currentCache.paragraphStarts,
                prefixLen: currentCache.chapterPrefixLen
            )
        } else if currentChapterIndex > 0 {
            pendingJumpToLastPage = true
            previousChapter()
        }
    }

    private func goToNextPage() {
        if currentPageIndex < currentCache.pages.count - 1 {
            currentPageIndex += 1
        } else if windowEndCharIndex < currentCache.attributedText.length, pageSize.width > 0, pageSize.height > 0 {
            let anchorIndex = currentPageIndex <= windowOverlapPages ? currentPageIndex : (currentPageIndex - windowOverlapPages)
            windowHistory.append(WindowAnchor(startCharIndex: windowStartCharIndex, basePageIndex: windowBasePageIndex))
            let newStartChar = currentCache.pages.indices.contains(anchorIndex) ? currentCache.pages[anchorIndex].globalRange.location : windowStartCharIndex
            let newBasePage = windowBasePageIndex + anchorIndex
            let targetGlobalPage = windowBasePageIndex + currentPageIndex + 1
            applyWindow(
                startCharIndex: newStartChar,
                basePageIndex: newBasePage,
                desiredGlobalPageIndex: targetGlobalPage,
                focusCharIndex: nil,
                size: pageSize,
                from: currentCache.attributedText,
                sentences: currentCache.contentSentences,
                pStarts: currentCache.paragraphStarts,
                prefixLen: currentCache.chapterPrefixLen
            )
        } else if currentChapterIndex < chapters.count - 1 {
            pendingJumpToFirstPage = true
            nextChapter()
        }
    }

    private func pageIndexForSentence(_ index: Int) -> Int? {
        guard !currentCache.pages.isEmpty else { return nil }
        for i in 0..<currentCache.pages.count {
            let startIndex = currentCache.pages[i].startSentenceIndex
            let nextStart = (i + 1 < currentCache.pages.count)
                ? currentCache.pages[i + 1].startSentenceIndex
                : Int.max
            if index >= startIndex && index < nextStart {
                return i
            }
        }
        return nil
    }

    private func globalCharIndexForSentence(_ index: Int) -> Int? {
        guard index >= 0, index < currentCache.paragraphStarts.count else { return nil }
        return currentCache.paragraphStarts[index] + currentCache.chapterPrefixLen
    }

    private func syncPageForSentenceIndex(_ index: Int) {
        guard index >= 0, preferences.readingMode == .horizontal else { return }
        
        let realIndex = index + ttsBaseIndex
        
        // Only flip page immediately if the sentence starts AFTER the current page.
        // If it starts ON this page (even partially), we wait for auto flip.
        if currentCache.pages.indices.contains(currentPageIndex),
           let sentenceStart = globalCharIndexForSentence(realIndex) {
            let pageRange = currentCache.pages[currentPageIndex].globalRange
            let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
            if sentenceLen > 0 {
                let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
                if NSIntersectionRange(sentenceRange, pageRange).length > 0 {
                    return
                }
            } else if NSLocationInRange(sentenceStart, pageRange) {
                return
            }
        }

        if let pageIndex = pageIndexForSentence(realIndex), pageIndex != currentPageIndex {
            isTTSSyncingPage = true
            withAnimation { currentPageIndex = pageIndex }
            DispatchQueue.main.async {
                isTTSSyncingPage = false
            }
            return
        }
        if let globalCharIndex = globalCharIndexForSentence(realIndex), pageSize.width > 0, pageSize.height > 0 {
            isTTSSyncingPage = true
            applyWindow(
                startCharIndex: max(0, globalCharIndex),
                basePageIndex: windowBasePageIndex,
                desiredGlobalPageIndex: windowBasePageIndex + currentPageIndex,
                focusCharIndex: globalCharIndex,
                size: pageSize,
                from: currentCache.attributedText,
                sentences: currentCache.contentSentences,
                pStarts: currentCache.paragraphStarts,
                prefixLen: currentCache.chapterPrefixLen
            )
            DispatchQueue.main.async {
                isTTSSyncingPage = false
            }
        }
    }
    
    private func scheduleAutoFlip(duration: TimeInterval) {
        guard duration > 0, ttsManager.isPlaying, preferences.readingMode == .horizontal else { return }
        
        pendingFlipId = UUID()
        let taskId = pendingFlipId
        
        let index = ttsManager.currentSentenceIndex
        let realIndex = index + ttsBaseIndex
        
        guard currentCache.pages.indices.contains(currentPageIndex),
              let sentenceStart = globalCharIndexForSentence(realIndex) else { return }
              
        let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
        guard sentenceLen > 0 else { return }
        
        let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
        let pageRange = currentCache.pages[currentPageIndex].globalRange
        
        let intersection = NSIntersectionRange(sentenceRange, pageRange)
        let sentenceEnd = NSMaxRange(sentenceRange)
        let pageStart = pageRange.location
        let pageEnd = NSMaxRange(pageRange)

        if sentenceStart >= pageStart, sentenceEnd > pageEnd, intersection.length > 0 {
            let visibleRatio = Double(intersection.length) / Double(sentenceLen)
            let delay = duration * visibleRatio

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.pendingFlipId == taskId {
                    isAutoFlipping = true
                    goToNextPage()
                }
            }
        }
    }
    
    private func prepareAdjacentChapters(for chapterIndex: Int) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        
        // Prepare Next Chapter "gate"
        let nextIndex = chapterIndex + 1
        if nextIndex < chapters.count {
            Task {
                if let cache = await paginateChapter(at: nextIndex, forGate: true) {
                    await MainActor.run { self.nextCache = cache }
                }
            }
        } else {
            nextCache = .empty
        }
        
        // Prepare Previous Chapter "gate"
        let prevIndex = chapterIndex - 1
        if prevIndex >= 0 {
            Task {
                if let cache = await paginateChapter(at: prevIndex, forGate: true, fromEnd: true) {
                    await MainActor.run { self.prevCache = cache }
                }
            }
        } else {
            prevCache = .empty
        }
    }

    private func handleChapterSwitch(offset: Int) {
        // Cancel any pending timed flip
        pendingFlipId = UUID()
        
        if offset == 1 { // Switched to Next Chapter
            guard !nextCache.pages.isEmpty else { return }
            currentChapterIndex += 1
            prevCache = currentCache
            currentCache = nextCache
            nextCache = .empty
            currentPageIndex = 0
            
        } else if offset == -1 { // Switched to Prev Chapter
            guard !prevCache.pages.isEmpty else { return }
            currentChapterIndex -= 1
            nextCache = currentCache
            currentCache = prevCache
            prevCache = .empty
            currentPageIndex = currentCache.pages.count - 1
        }

        // Reset window state for the new chapter
        windowHistory.removeAll()
        windowBasePageIndex = 0
        totalPageCount = nil // Will be recalculated if needed
        
        // Trigger full window load for the new current chapter & preload for new adjacent chapters
        loadChapterContent()
    }
    
    // This function re-paginates the current chapter with a full window,
    // replacing the "gate" cache if necessary.
    private func repaginateCurrentChapterWindow(sentences: [String]? = nil) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        
        if let sentences = sentences, !sentences.isEmpty {
            repaginateContent(in: pageSize, with: sentences)
            return
        }
        
        guard !rawContent.isEmpty else { return } // Should be called after content is loaded
        let processed = applyReplaceRules(to: rawContent)
        let newSentences = splitIntoParagraphs(processed)
        repaginateContent(in: pageSize, with: newSentences)
    }

    private func paginateChapter(at index: Int, forGate: Bool, fromEnd: Bool = false) async -> ChapterCache? {
        guard let content = try? await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index) else {
            return nil
        }
        
        let cleaned = removeHTMLAndSVG(content)
        let processed = applyReplaceRules(to: cleaned)
        let sentences = splitIntoParagraphs(processed)
        let title = chapters[index].title
        
        let attrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: title)
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let prefixLen = (title.isEmpty) ? 0 : (title + "\n").utf16.count
        
        var result: WindowPaginationResult
        if forGate {
            if fromEnd {
                // For prev chapter, we need last N pages. The simplest way is to paginate all and take last.
                // This is a trade-off for simplicity over performance for huge chapters.
                let fullResult = TextKitPaginator.paginateWindow(fullText: attrText, paragraphStarts: pStarts, prefixLen: prefixLen, startCharIndex: 0, maxPages: 2000, size: pageSize)
                let pages = Array(fullResult.pages.suffix(windowAdvanceThreshold))
                // Note: This creates a new store with just the last pages.
                let gateResult = TextKitPaginator.paginateWindow(fullText: attrText, paragraphStarts: pStarts, prefixLen: prefixLen, startCharIndex: pages.first?.globalRange.location ?? 0, maxPages: windowAdvanceThreshold, size: pageSize)
                result = gateResult
            } else {
                // For next chapter, just paginate first N pages.
                result = TextKitPaginator.paginateWindow(fullText: attrText, paragraphStarts: pStarts, prefixLen: prefixLen, startCharIndex: 0, maxPages: windowAdvanceThreshold, size: pageSize)
            }
        } else {
            // Paginate a full window for the current chapter
            result = TextKitPaginator.paginateWindow(fullText: attrText, paragraphStarts: pStarts, prefixLen: prefixLen, startCharIndex: 0, maxPages: maxCachedPages, size: pageSize)
        }

        return ChapterCache(
            pages: result.pages,
            store: result.renderStore,
            contentSentences: sentences,
            attributedText: attrText,
            paragraphStarts: pStarts,
            chapterPrefixLen: prefixLen
        )
    }

    // MARK: - Logic & Actions (Loading, Saving, etc.)
    
    private func updateProcessedContent(from rawText: String) {
        let processedContent = applyReplaceRules(to: rawText)
        currentContent = processedContent.isEmpty ? "章节内容为空" : processedContent
        contentSentences = splitIntoParagraphs(currentContent)
    }

    private func applyReplaceRules(to content: String) -> String {
        var processedContent = content
        let enabledRules = replaceRuleViewModel.rules.filter { $0.isEnabled == true }
        for rule in enabledRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: processedContent.utf16.count)
                processedContent = regex.stringByReplacingMatches(in: processedContent, options: [], range: range, withTemplate: rule.replacement)
            }
        }
        return processedContent
    }

    private func removeHTMLAndSVG(_ text: String) -> String {
        var result = text
        let svgPattern = "<svg[^>]*>.*?</svg>"
        if let svgRegex = try? NSRegularExpression(pattern: svgPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            result = svgRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        let imgPattern = "<img[^>]*>"
        if let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            result = imgRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        return result
    }
    
    private func splitIntoParagraphs(_ text: String) -> [String] {
        // First split by newlines to preserve paragraph structure as much as possible
        let blocks = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            
        var sentences: [String] = []
        // Simple regex to split by common sentence terminators while keeping them attached to the sentence if possible.
        // Or simply split. Splitting by punctuation improves TTS granularity.
        // Let's use a simple approach: split by [。！？!?] followed by nothing or whitespace
        // But re-joining them with \n in createAttributedText will alter layout.
        // CONSTRAINT: We cannot easily change sentence splitting without affecting layout if createAttributedText joins with \n.
        // However, if we split a long paragraph into multiple "sentences", they will be rendered as separate paragraphs.
        // This is a trade-off. For now, let's keep the original logic to strictly preserve layout,
        // relying on the Lazy Flip logic to handle cross-page reading.
        // Only if the user explicitly requested finer granularity should we do this.
        // User said: "根据字符时间的长度来大体计算".
        // Let's stick to the original logic for now to ensure layout correctness.
        return blocks
    }
    
    private func loadChapters() async {
        isLoading = true
        do {
            chapters = try await apiService.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            loadChapterContent()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func loadChapterContent() {
        guard currentChapterIndex < chapters.count else { return }
        isLoading = true
        Task {
            do {
                let content = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: currentChapterIndex)
                await MainActor.run {
                    let cleanedContent = removeHTMLAndSVG(content)
                    resetPaginationState()
                    rawContent = cleanedContent
                    updateProcessedContent(from: cleanedContent)
                    isLoading = false
                    ttsBaseIndex = 0
                    if ttsManager.isPlaying {
                        if ttsManager.bookUrl != book.bookUrl || ttsManager.currentChapterIndex != currentChapterIndex {
                            ttsManager.stop()
                        }
                    }
                    prepareAdjacentChapters(for: currentChapterIndex)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "闂傚倸鍊搁崐鎼佸磹閹间礁纾归柟闂寸绾惧綊鏌熼梻瀵割槮缁炬儳缍婇弻鐔兼⒒鐎靛壊妲紒鐐劤缂嶅﹪寮婚悢鍏尖拻閻庨潧澹婂Σ顔剧磼閻愵剙鍔ょ紓宥咃躬瀵鎮㈤崗灏栨嫽闁诲酣娼ф竟濠偽ｉ鍓х＜闁绘劦鍓欓崝銈囩磽瀹ュ拑韬€殿喖顭烽幃銏ゅ礂鐏忔牗瀚介梺璇查叄濞佳勭珶婵犲伣锝夘敊閸撗咃紲闂佺粯鍔﹂崜娆撳礉閵堝洨纾界€广儱鎷戦煬顒傗偓娈垮枛椤兘骞冮姀銈呯閻忓繑鐗楃€氫粙姊虹拠鏌ュ弰婵炰匠鍕彾濠电姴浼ｉ敐澶樻晩闁告挆鍜冪床闂備胶绮崝锕傚礈濞嗘挸绀夐柕鍫濇川绾剧晫鈧箍鍎遍幏鎴︾叕椤掑倵鍋撳▓鍨灈妞ゎ厾鍏橀獮鍐閵堝懐顦ч柣蹇撶箲閻楁鈧矮绮欏铏规嫚閺屻儱寮板┑鐐板尃閸曨厾褰炬繝鐢靛Т娴硷綁鏁愭径妯绘櫓闂佸憡鎸嗛崪鍐簥闂傚倷娴囬鏍垂鎼淬劌绀冮柨婵嗘閻﹂亶姊婚崒娆掑厡妞ゃ垹锕ら埢宥夊即閵忕姷顔夐梺鎼炲労閸撴瑩鎮橀幎鑺ョ厸闁告劑鍔庢晶鏇犵磼閳ь剟宕橀埞澶哥盎闂婎偄娲ゅù鐑剿囬敃鈧湁婵犲﹤鐗忛悾娲煛鐏炶濡奸柍瑙勫灴瀹曞崬鈻庤箛鎾寸槗缂傚倸鍊烽梽宥夊礉瀹€鍕ч柟闂寸閽冪喖鏌ｉ弬鍨倯闁稿骸鐭傞弻娑樷攽閸曨偄濮㈤悶姘剧畵濮婄粯鎷呴崨濠冨創闂佹椿鍘奸ˇ杈╂閻愬鐟归柍褜鍓熸俊瀛樻媴閸撳弶寤洪梺閫炲苯澧存鐐插暙閳诲酣骞樺畷鍥跺晣婵＄偑鍊栭幐楣冨闯閵夈儙娑滎樄婵﹤顭峰畷鎺戔枎閹寸姷宕叉繝鐢靛仒閸栫娀宕楅悙顒傗槈闁宠閰ｉ獮瀣倷鐎涙﹩鍞堕梻鍌欑濠€閬嶅磿閵堝鈧啴骞囬鍓ь槸闂佸搫绉查崝搴ｅ姬閳ь剟姊婚崒姘卞濞撴碍顨婂畷鏇㈠箛閻楀牏鍘搁梺鍛婁緱閸犳岸宕ｉ埀顒勬⒑閸濆嫭婀扮紒瀣灴閸┿儲寰勯幇顒傤攨闂佺粯鍔曞Ο濠傤焽缂佹ü绻嗛柣鎰典簻閳ь剚鍨垮畷鏇㈠箵閹烘梹娈曠紓浣割儐椤戞瑥顭囬弽顓熺叄闊洦鍑瑰鎰版倵濮橆厼鍝洪柡灞剧☉閳诲氦绠涢敐鍠帮箓姊虹悰鈥充壕濡炪倖鎸鹃崕鎰€掓繝姘厪闁割偅绻堥妤€霉濠婂嫮鐭嬮柕鍥у閺佸倻鎷犻懠顑垮寲闂備礁鎲￠悷銉╁箠濡綍娑㈠川閹碱厽鏅濋梺闈涚箚閳ь剚鍓氬Σ杈╃磽閸屾瑧顦︽い鎴濇瀹曞湱鎲撮崟顓犲骄闂佸搫娲㈤崹褰掓煥閵堝棔绻嗛柕鍫濆閸忓矂鏌涘Ο鍏兼毈婵﹨娅ｉ幏鐘诲灳瀹曞洣鍖栧┑鐘媰閸曞灚鐤侀柦妯煎枎椤潡鎳滈棃娑橆潔闂佺粯鎸鹃崰鏍蓟閻斿吋鍊绘俊顖濇娴犲吋绻涚€电校闁烩晩鍨跺濠氬即閵忕姷鍊為悷婊冪Ч椤㈡棃顢橀悤浣诡啍闂佺粯鍔栧娆徝归绛嬫闁绘劕妯婇崕鏃€銇勯姀锛勨槈妞ゎ偅绻堥、妤佸緞鐎ｎ偆銈紓鍌氬€搁崐鎼佸磹閹间礁纾瑰瀣捣閻棗銆掑锝呬壕闁芥ɑ绻堝娲敆閳ь剛绮旈幘顔煎嚑濞达絿纭堕弨浠嬫煟濡櫣鏋冨瑙勶耿閺岋箓宕橀鍕€剧紓浣虹帛閻╊垶鐛€ｎ亖鏋庨煫鍥ㄦ磻閻ヮ亪姊绘担渚劸妞ゆ垵妫濆畷婵單旈崨顓犲姦濡炪倖甯掗崰姘焽閹邦厾绠鹃柛娆忣槺婢ь亪鎮￠妶澶嬬厪闁割偅绻嶅Σ鎼佹煟閹惧瓨绀嬮柡灞剧洴椤㈡洟濡堕崨顔句簴缂傚倷璁插褔宕戦幘缁樷拻濞撴埃鍋撴繛浣冲嫷娈介煫鍥ㄦ礈缁€濠囨煕閳╁喚娈㈤柣鎺嶇矙閺岀喖鏌囬敃鈧獮妯肩磼閻樿崵鐣洪柡灞诲€楅崰濠囧础閻愬樊娼婚梻浣告惈椤戝懘鏌婇敐澶婅摕闁挎繂顦伴弲鎻掝熆閼哥灙鎴λ夐弽顐ょ＝濞撴艾娲ら弸鐔兼煟閻旀繂娲ょ粻顖炴煟濡偐甯涢柛濠囨敱閵囧嫰骞掑鍫敼闂佺懓鍢茬紞濠傤潖濞差亝鍋￠柡澶嬪浜涢梻浣侯攰濞呮洟鏁嬮梺浼欑悼閸忔﹢銆侀弴銏℃櫇闁逞屽墰缁牏鈧綆鍋佹禍婊堟煙閹佃櫕娅呴柍褜鍏欓崐婵嗙暦閵壯€鍋撻敐搴℃灍闁抽攱甯￠弻娑氫沪閹规劕顥濋梺閫炲苯澧柟顔煎€搁悾鐑藉箛椤掑倹娈濋梺鐟板暱閿曘倗绱炴繝鍌滄殾闁割偅娲﹂弫鍡楊熆鐠轰警鍎愭繛鍛濮婄粯鎷呴崨濠冨創缂備礁顑勭欢姘暦閵忥紕闄勭紒瀣仢閻庮參姊虹粙璺ㄧ伇闁稿鍋ら幃锟犳晲婢跺苯褰勯梺鎼炲劦椤ユ捇宕氶弶妫电懓顭ㄩ崟顓犵暫缂備胶绮惄顖氱暦閵娾晩鏁嶆慨锝呭皡缁插€熷絹闂佹悶鍎滃鍫濇儓濠电姷顣介埀顒€纾崺锝団偓瑙勬磸閸旀垿銆佸▎鎾村亗閹肩补妲呭姘攽閻樺灚鏆╁┑顔诲嵆瀹曞綊鎮℃惔妯荤亙濠电偞鍨崺鍕极閸曨垱鐓曟繛鎴濆船閻忊剝銇勯幇顏嗙煓闁哄矉缍侀獮鍥敊閻撳骸顬嗛梻浣虹帛閹稿鎮烽埡渚囨綎婵炲樊浜堕弫鍥煏婵炑冩噺濞堢鈹戦悩顐ｅ闁告侗鍙庨弳顓㈡⒑闂堟稒鎼愰悗姘緲椤曪綁顢氶埀顒勫春閳ь剚銇勯幒鎴濐仼缂佲偓婢跺绠鹃柛鈩冾殕缁傚绻涢崗鑲╁缂佺粯绋戦蹇涱敊閼姐倗娉垮┑鐐殿棎閸嬫劖绻涢埀顒勬煛鐏炲墽娲寸€殿喗鎸抽幃娆撳礂閸濄儵鈹忛梻浣芥〃缁€渚€鎮ч幘鎰佹綎缂備焦蓱婵挳鏌ц箛鎾剁暛闁逞屽墮閿曨亪寮婚敓鐘插窛妞ゆ梻鍋撻崚娑㈡⒑鏉炴壆顦﹂柛鐔告尦閵嗕線寮崼婵嬪敹闂佺粯妫佸〒鍦姳閸偂绻嗛柣鎰典簻閳ь剚鐗滈弫顕€骞掗弬鍝勪壕婵ê宕崢瀵糕偓娈垮櫘閸嬪﹤鐣烽崡鐐╂婵炲棙鍨甸獮鍫ユ⒒娴ｅ憡鎯堟繛灞傚灲瀹曟繄浠﹂悙顒佺彿婵炲鍘ч悺銊╂偂閺囩喍绻嗘い鏍ㄧ矌鐢盯鏌涙繝鍐ㄥ闁哄备鈧磭鏆嗛悗锝庡墰琚ｇ紓鍌欒兌婵敻鎯勯姘煎殨闁圭虎鍠楅崐鐑芥煛婢跺顕滈柟灞傚灩閳规垿鏁嶉崟顐℃澀闂佺锕ラ悧鏇㈠煝閺冨牊鏅濋柛灞炬皑閸婄偤鎮峰鍐鐎规洘绻堥弫鍐焵椤掑嫧鈧棃宕橀鍢壯囨煕閳╁喚娈橀柣鐔稿姍濮婃椽鎮℃惔鈩冩瘣婵犫拃鍐╂崳闁告帗甯楃换婵嗩潩椤撶偐鍋撻悜鑺ョ厵缁炬澘宕獮妤併亜閺冣偓濡啫顫忛搹鍦＜婵☆垰鎼～鎴濐渻閵堝棙绀冪紒顔肩焸椤㈡瑨绠涘☉妯溿劑鏌嶉崫鍕偓濠氬储閹剧粯鐓熼柣鏂挎憸閹冲啴鎮楀鐓庡⒋闁诡喗锕㈤崺锟犲川椤旀儳甯楅柣鐔哥矋缁挸鐣峰鍫澪╃憸蹇曠矆婵犲洦鐓曢柍鈺佸枤閻掕姤銇勯埡鍌滃弨闁哄矉缍侀獮鍥敂閸ヨ泛濡抽梻浣芥〃缁€浣该洪銏犺摕闁挎繂顦粻濠氭煕閹邦垰鐨烘俊鍙夋緲閳规垿鎮欑€涙ê纰嶅銈庡幘閸忔ê顕ｆ繝姘嵆闁靛繒濞€閸炶泛鈹戦悩缁樻锭婵炴潙鍊歌灋闁炽儲鍓氬〒濠氭煏閸繂鏆欓柛鏃€纰嶆穱濠囶敃閿濆洨鐤勯悗娈垮枦椤曆囧煡婢跺娼╅柨婵嗘噸婢规洟姊洪幐搴ｇ畵濡ょ姴鎲＄粋宥咁煥閸愶絾鏂€濡炪倖妫侀崑鎰櫠閿曞倹鐓涚€光偓鐎ｎ剛鐦堥悗瑙勬磸閸旀垿銆佸鈧幃鈺呮嚑椤掆偓楠炴鈹戦敍鍕杭闁稿﹥鍨垮畷褰掓惞閸︻厾鐓撻梺纭呮彧鐠侊絿绱為弽銊х瘈闂傚牊渚楅崕鎰版煛閸涱喚鍙€闁哄本鐩崺鍕礂閳哄倸鐏ユい顓炴健楠炲鏁傜憴锝嗗闂備胶顭堥張顒勬偡閵娾晛绀傜€光偓閳ь剛妲愰幒妤婃晪闁告侗鍘炬禒鎼佹倵鐟欏嫭绀冪紒璇插€介悘鎺楁⒒閸屾艾鈧悂顢氶銏犵闁靛鍎弨浠嬫煟閹邦剙绾фい銉у仱閺岀喓绮欓幐搴㈠枑缂備緡鍠涢褏鍙呭銈呯箰閹虫劙宕㈤挊澶嗘斀闁宠棄妫楅悘鐘绘煕濮橆剦鍎旂€殿喗濞婇崺锟犲礃椤忓拑绱￠梻浣筋嚃閸ㄥ酣宕橀埡浣插亾椤栫偞鈷戦梻鍫熺⊕閹兼劙鎮楀顓熺凡妞ゆ洩缍侀、姘跺焵椤掆偓閻ｇ兘骞嗛柇锔叫ㄦ繝娈垮枦椤銆冩繝鍌ゆ綎闁惧繗顫夌€氭岸鏌ょ喊鍗炲妞ゆ梹鍨剁换娑氣偓娑欘焽閻倝鏌涢幘瀵糕槈閸楅亶鏌熼悧鍫熺凡缂佺姵濞婇弻鐔煎箚瑜滈崵鐔虹磼婢跺﹦鍩ｆ慨濠呮閳ь剙婀辨慨鐢稿Υ閸愨晙绻嗛柣鎰綑缁楁帡鏌嶇拋宕囩煓妞ゃ垺妫冨畷鍗炩枎閹搭垳闂繝鐢靛仩閹活亞绱為埀顒佺箾閸滃啰鎮奸柡渚囧枛閳藉顫濇潏鈺嬬床闂佽崵濮村ú鈺冧焊濞嗘劖娅犻柡鍥ュ灪閻撶喖鏌ㄥ┑鍡樻悙闁告ê鐡ㄩ〃銉╂倷閸欏妫﹂梺鍝勮嫰濞差參寮崒婊勫枂闁挎繂妫涢埀顒勪憾濮婂宕掑顑藉亾閻戣姤鍤勯柛顐ｆ磸閳ь兛鐒︾换婵嬪礃閳轰礁浼庨梻渚€娼ч悧鍡涘箖閸啔娲敂閸曨偄鏁ゆ俊鐐€栭幐楣冨磻閻旂厧鍌ㄩ柟缁㈠枟閳锋垹鐥鐐村櫤鐟滄妸鍥ㄢ拻闁告洦鍋勯顓犫偓瑙勬礃閸旀瑩骞冨鍫熷殟闁靛／鍐ㄧ婵犵數濮伴崹鐓庘枖濞戙埄鏁勯柛娑樼摠閸婂爼鏌嶆潪鐗堚偓銉ㄣ亹閹烘挸浜瑰┑鐐叉缁绘垶寰勯崟顖涚厓闂佸灝顑呴悘鎾煛瀹€鈧崰鏍箠閺嶎厼鐓涘ù锝夘棑閹规洖鈹戦悩娈挎毌闁逞屽墲濞呮洟宕戦妷鈺傜厸鐎光偓閳ь剟宕伴弽顓炵鐟滅増甯╅弫鍐煥濠靛棙鍣介柨娑欐崌閺岋絾鎯旈姀鈺佹櫛闂侀潻缍嗛崳锝呯暦閹寸偟绡€闁搞儯鍎崑鎾存媴閸撳弶鍍甸柣鐘荤細濞咃綁宕濋敃鈧—鍐Χ閸℃娼戦梺绋款儐閹稿濡甸崟顖ｆ晝闁靛繈鍨婚濠勭磽娴ｄ粙鍝洪悽顖涘笩閻忔帡姊洪崗鑲┿偞闁哄懏绮撳畷闈涚暆閸曨兘鎷绘繛鎾村焹閸嬫捇鏌嶈閸撴盯宕戝☉銏″殣妞ゆ牗绋掑▍鐘炽亜閺傛娼熷ù婊勭矋閵囧嫰骞樼捄杞版勃缂備礁鏈€笛囧Φ閸曨垱鏅滈柤鎭掑劚閸炲姊洪崫鍕伇闁哥姵鐗犻幃浼搭敋閳ь剙鐣疯ぐ鎺濇晩闁告瑣鍎崇粈鍕⒑鐠囧弶鍞夋い顐㈩槸鐓ら柡宓懏娈惧銈嗗笒鐎氼剟鎮￠垾鎰佺唵閻犲搫銈介敓鐘冲亜闁告繂瀚悗鎶芥煛婢跺﹦澧戦柛鎾讳憾婵″爼宕ㄩ鍛澑闂備胶绮敋闁诲繑宀稿鎶藉煛娴ｅ弶鏂€闂佺粯鍔忛弲娑欑閻愵剛绡€闁汇垽娼ф禒鎺楁煕閺嶎偄鈻堢€规洖鐖奸幊婊堝垂椤愶絿褰堥梻鍌氬€烽懗鍓佹兜閸洖绀堟繝闈涚墢閻瑩鏌熺€电孝妞ゃ儲鑹鹃埞鎴︽偐瀹曞浂鏆￠梺缁樻尵閸犳牠寮婚敓鐘茬＜婵ê褰夐搹搴ㄦ⒑鐠団€虫灍闁搞劌娼″濠氭晲婢跺﹦顔掗柣搴＄仛閹爼鍩€椤掍礁娴柡灞界Х椤т線鏌涢幘瀵告噮缂侇喛顕ч鍏煎緞婵犲嫸绱甸梺鍝勵槸閻楁粓鎮￠崼婵冩灁濞寸姴顑嗛悡娆撴⒒閸屾粠妫庨柛蹇撶灱閳ь剝顫夐幐鐑芥倿閿旂晫鈹嶅┑鐘叉搐鍥撮梺鍛婁緱閸犳牕鈻嶉妶澶嬧拺缂備焦蓱鐏忣參鏌涢悢鍛婄稇妞ゎ偄绻愮叅妞ゅ繐瀚悗顓烆渻閵堝棙绀€闁瑰啿閰ｅ畷婊勫鐎涙ǚ鎷洪柣鐘叉穿鐏忔瑧绮婚弻銉︾厵闁告稑锕ら埢鏇犫偓娈垮枛椤兘寮澶婄妞ゅ繐鎳庢刊浼存⒒娴ｅ憡鍟為柟绋挎閸┾偓妞ゆ巻鍋撻崡閬嶆煕椤愮姴鍔滈柍閿嬪灴閹宕烽鐐愶絾銇勯妷銉Ч闁靛洤瀚伴弫鍌滄嫚閼碱兛妗撻梻浣瑰缁诲嫰宕戝☉鈶┾偓锕傚Ω閳轰線鍞跺┑鐘绘涧濡粓鍩€椤掆偓閻忔繈鍩為幋锔藉€烽柛娆忣樈濡偟绱撴担铏瑰笡闁告梹顨呴銉︾節閸パ呯暰閻熸粌顦靛銊︾鐎ｎ偆鍘藉┑鈽嗗灥濞咃絾绂掑☉銏＄厸闁糕€崇箲濞呭﹪鏌＄仦鍓с€掗柍褜鍓ㄧ紞鍡涘磻閸℃娲箻椤旂晫鍘靛銈嗘煟閸斿瞼鈧凹鍠氬褔鍩€椤掑嫭鈷戠紒瀣儥閸庢盯鏌涢妸銈呭祮妤犵偞鐗犻、鏇㈡晜閸忓浜鹃柨鏇炲€告儫闂佸疇妗ㄧ欢姘跺船鐠鸿　鏀介柣妯肩帛濞懷囨煟濡も偓濡瑩骞堥妸鈺傛櫆闁瑰瓨甯炵粻姘舵⒑缂佹ê濮﹀ù婊勭矒閸┾偓妞ゆ帊鑳舵晶顏呫亜閺傝法绠茬紒缁樼箓椤繈顢楅崒锔惧耿闂傚倷鑳堕幊鎾存櫠閻ｅ苯鍨濇い鏍仦閸嬪倿鏌￠崶鈺佹瀺缂佽妫欓妵鍕冀閵娧呯暤闂佸憡鑹剧紞濠囧蓟閿濆鏁囬柣鏃堫棑椤戝倿姊洪柅鐐茶嫰婢у弶銇勯銏╂Ц閻撱倖鎱ㄥ璇蹭壕閻庤娲栫紞濠傜暦缁嬭鏃堝礃閵娧佸亰濠电姷顣藉Σ鍛村垂閻㈢纾婚柟閭﹀枛椤ユ岸鏌涜箛娑欙紵缂佽妫欓妵鍕冀閵娧呯厐闁汇埄鍨甸崺鏍€冮妷鈺傚€烽柤纰卞劮瑜庨幈銊︾節閸屻倗鍚嬮悗瑙勬礃鐢帡锝炲┑瀣垫晞闁芥ê顦竟鏇㈡⒑瑜版帗锛熺紒鈧担鍝勵棜鐟滅増甯楅悡娆撴⒒閸屾凹鍤熼悹鎰嵆閺屸剝鎷呴崜鎻掑壉闂侀潧娲ょ€氫即鐛鈧、娑樷槈濡崵鏋€闂傚倷鐒﹂幃鍫曞磿濞差亜绀堟慨妯挎硾閻ょ偓绻濋棃娑卞剱闁绘挻娲熼幃姗€鎮欓幓鎺嗘寖闂侀潧妫欑敮锟犲蓟濞戞ǚ鏋庨煫鍥ㄦ尰濞堣鈹戦纭锋敾婵＄偠妫勯悾鐑藉Ω閿斿墽鐦堥梺绋挎湰椤曟挳寮撮悢铏诡啎闁诲孩绋掗…鍥儗鐎ｎ剛纾兼い鏃囧Г鐏忣厽銇勯弴顏嗘偧缂侇喗鐟﹂幆鏃堝箻閹碱厽缍岄梻鍌欑窔濞佳勵殽韫囨洘顫曢柡鍥ュ灩閸屻劑鏌熼梻瀵稿妽闁绘挾鍠栭悡顐﹀炊閵婏妇顦ユ繛瀵稿Л閺呮粓濡甸崟顖氬嵆闁糕剝顨呴褏绱掔拠鍙夘棞闁宠鍨垮畷鎺戭潩椤撶偞娈橀梻浣虹帛閹告悂宕幘顔肩畺鐎瑰嫭澹嬮弸搴ㄧ叓閸ャ劍鎯勫ù鐘层偢濮婅櫣鎷犻懠顒傤唶濡炪倖娲﹂崣鍐春閳ь剚銇勯幒鎴濇灓婵炲吋鍔栫换娑㈠矗婢跺苯鈪归梺浼欑悼閸忔﹢銆佸Δ鍛妞ゅ繐鍟抽崺鍛存⒒閸屾艾鈧兘鎳楅崜浣稿灊妞ゆ牜鍋涢崹鍌炴煙椤栨粌顣奸柟鍐茬焸濮婄粯鎷呴搹鐟扮缂備浇顕ч崐鍧楀箖閵夆晜鍋傞幖鎼枟缂嶅孩绻濋悽闈浶ｉ柤鐟板⒔婢规洟宕楅懖鈺冾啎闂佺硶鍓濋敋缂佹甯￠弻娑橆潨閸垻锛熺紓浣介哺閹歌崵绮悢鐓庣倞鐟滃酣鎮甸鈧娲箹閻愭彃顫呭┑鐐差槹閻╊垶銆佸鑸垫櫜闁糕剝鐟ч惁鍫濃攽椤旀枻渚涢柛搴ｆ暬閸╋繝宕ㄩ鎯у笚闂佸搫顦遍崑鐔告櫠濡ゅ啰鐭堥柟娈垮枟閸嬫牗绻濋棃娑卞剱闁抽攱鍨块幃褰掑炊閵娿儳绁烽梺鎼炲€涙禍顒傛閹炬剚鍚嬮柛娑卞櫘濡箓鎮楃憴鍕；闁告鍟块锝嗙鐎ｅ灚鏅濋梺闈涚箚閺呮粓藟閿熺姵鈷掑〒姘ｅ亾婵炶壈宕甸埀顒勬涧閻倸鐣烽姀銈呯鐟滃秹藟濮樿埖鐓㈡俊顖欒濡妇鎲搁悧鍫濈瑲闁哄懏鐓￠弻娑橆煥閳ь剟鎮為敂鍓х婵せ鍋撴慨濠冩そ瀹曟鎳栭埞鍨沪闂備礁鎼幊蹇曞垝瀹€鍕仼闁绘垼妫勯拑鐔兼煏婢舵稑顩柛姗€浜跺娲棘閵夛附鐝旈梺鍛婄懃濞层倝鈥﹂妸鈺佺妞ゆ挆鍕暅濠电姷鏁告慨鎾晝閵堝鍋嬪┑鐘叉处閸嬪倹绻涢幋鐐茬劰闁稿鎹囬悰顕€宕归鐓庮潛闂備礁鎽滈崳銉╁磻閸涱喚鈹嶅┑鐘插瀹曞鏌曟繛褍鎷戠槐鏌ユ⒒娴ｈ櫣甯涢柨鏇楁櫊瀹曚即寮介鐐殿槷闂佹寧娲栭崐褰掓偂濞戙垺鍊堕柣鎰絻閳锋梹绻涢崣澶嬬稇闁宠鍨块崹鎯х暦閸パ呭幗闁诲氦顫夊ú鏍х暦椤掑嫬鐓濋幖娣妼缁犳稒銇勯幒宥堝厡鐟滅増鎸冲濠氬磼濮橆兘鍋撴搴ｇ焼濞撴埃鍋撴鐐寸墵椤㈡洟鏁冮埀顒傗偓姘槹閵囧嫰骞掗幋婵愪痪闂佺楠哥€涒晠濡甸崟顖氬唨妞ゆ劦婢€閹寸兘鎮楃憴鍕矮闁绘帪绠撻獮鍫ュΩ閵夘喗瀵岄柣鐘叉穿瀵挻绔熼弴銏♀拻濞达絼璀﹂弨鐗堢箾閸涱喗绀堥柛鎺撳浮楠炴ê鐣烽崶銊︻啎闁荤喐绮庢晶妤冩暜閳哄懎鏋侀柛鎰靛枟閻撱儲绻濋棃娑欘棡濠㈣泛瀚妵鍕敃閿濆洨鐓佺紓浣虹帛缁诲牓骞冩禒瀣棃婵炵顔愮徊楣冨Φ閸曨垰绫嶉柍褜鍓熼幃褔鎮╅懠顒佹婵炴潙鍚嬪娆撳礃閳ь剙顪冮妶鍡樺暗闁哥姵鍔曢埢宥夊炊椤掍讲鎷洪梻鍌氱墛娓氭危閸洘鐓曢幖绮瑰墲閹牓鏌曢崱妯虹瑲缂佺粯绻傞～婵嬵敇閻樻彃绫嶅┑鐘殿暯濡插懘宕归婊勫闁挎洍鍋撻崡杈ㄧ箾瀹割喕绨奸柣鎾寸洴閺屾盯鍩ラ崱妤€绫嶅┑锛勮檸閸犳氨妲愰幒鏃傜＜婵☆垵鍋愰悾铏圭磽娴ｈ櫣甯涚紒璇茬墕閻ｇ兘骞掗幋鏃€顫嶉悗瑙勬礀濞层劑藝椤栨埃鏀介柣妯活問閺嗩垶鏌涢幘瀵哥畾闁靛洦鍔欏畷姗€顢欓崗澶婁壕闁挎洍鍋撻柣锝忕節閺屽洭鏁傞悾宀€鈻夊┑鐘垫暩閸嬫稑螣婵犲啰顩叉繝濠傚枤閸熷懏绻濋棃娑欘棏闁衡偓娴犲鐓熸俊顖濐嚙缁插鏌＄€ｃ劌鈧牗绌辨繝鍥舵晝闁挎繂娲ら埛鍫㈢磽娴ｄ粙鍝洪柟绋款煼楠炲繘宕ㄩ弶鎴滅炊闂佸憡娲橀崺濠勭礊娓氣偓瀵鎮㈤崗鐓庝画闂佺粯顨呴悧濠囧箖濞嗗浚娓婚柕鍫濇缁岃法绱掗幓鎺撳仴妤犵偛绻橀幃鈺冩啑娴ｅ憡璐￠柍褜鍓ㄧ紞鍡涘磻閹烘埈鐒介柡鍐ㄧ墛閳锋帒銆掑锝呬壕濠电偘鍖犻崨顔煎簥闂佸湱鍎ら幐濠氬矗韫囨稒鐓熼柟瀵稿Х閹藉倿鏌℃担闈╄含闁哄瞼鍠栭幃婊冾潨閸℃鏆﹂梻浣虹帛閹搁箖宕伴弽顓犲祦闁哄稁鐏旀惔顭戞晢闁逞屽墯娣囧﹪鎳為妷褏顔曢梺鐟板暱閸㈡彃煤閿曞倹鍋傛繛鍡樻尰閻撶娀鏌熼鐔风瑨闁告柣鍊濋弻锝夘敇閻旈攱璇為梺鍝勭灱閸犳牠銆佸▎鎾崇畾鐟滃本绔熼弴鐘电＝濞达綀濮ら妴鍐磼椤旂晫鎳冮柣锝囧厴婵℃悂鏁傞崜褜鍟庨梻浣虹帛閸旓箓宕滃▎鎿冩晜鐟滅増甯楅埛鎺楁煕鐏炲墽鎳勭紒浣瑰閳ь剝顫夊ú婊堝极鐠囪尙鏆﹀ù鍏兼綑缁犳稒銇勯幘璺盒ョ憸浼寸畺濮婅櫣鍖栭弴鐐测拤缂備礁顑嗙敮鈥崇暦閹达箑鐓涢柛灞久肩花濠氭⒑鐟欏嫬鍔ょ€规洦鍓熼幃姗€顢旈崼鐔哄幗闂佽鍎抽悺銊х矆鐎ｎ喗鐓涢悘鐐靛亾缁€鍐磼缂佹娲寸€规洖缍婇、娆撴偂楠烆喗鍨圭槐鎾诲磼濞嗘埈妲銈忛檮濠㈡﹢鈥旈崘鈺冾浄閻庯綆浜ｉ幗鏇炩攽閻愭潙鐏熼柛銊ョ秺閹€斥槈閵忥紕鍘遍梺瑙勫閺呮稒淇婇悜妯圭箚闁告瑥顦慨鍥懚閺嶎厽鐓熸慨妞诲亾婵炰匠鍕浄婵犲﹤瀚ㄦ禍婊堟煙鐎涙绠ユ俊顖楀亾婵°倗濮烽崑娑㈠疮閹绢喖鏄ラ柨鐔哄Т濡炶棄霉閿濆牜娼愭繛鍛处娣囧﹪鎮欓鍕ㄥ亾閵堝纾婚柟鐑橆殔閸屻劌鈹戦崒娑欑秳濠㈣泛顭鈺呮煠閸濄儺鏆柟椋庣帛缁绘稒娼忛崜褎鍋ч梺纭呮珪閹瑰洭銆佸顒夌叆闁告侗鍨抽敍婊堟煟閻樺弶澶勭憸鏉垮暣閸┾偓妞ゆ巻鍋撴い顓犲厴楠炲﹪鎮欑€涙绉堕梺闈浤涢崶顭戔偓宥囩磽閸屾瑧顦︽い鎴濈墕閳绘棃寮撮姀鈥充痪闂佸憡绋戦悺銊╁煕閹寸姷纾藉ù锝咁潠椤忓懏鍙忛柨鏇炲€归悡鏇㈡煙閹屽殶闁靛棙甯炵槐鎺楊敊閸撗冪闂侀潧鐗炵紞浣哥暦濮椻偓閸╋繝宕橀妸銉ь啈闂傚倸鍊峰ù鍥綖婢舵劕纾块柟鎯版閻ゎ噣鏌涜椤ㄥ懘宕ヨぐ鎺撯拺妞ゆ巻鍋撶紒澶屾暬钘熷┑鐘插暔娴滄粓鏌熼悜妯虹劸婵¤尙顭堥…鑳檨闁搞劌鐖煎濠氭偄閸濄儳鎳濋梺鍓茬厛閸犳牠鈥栨径宀€纾藉ù锝堟鐢稓绱掔拠鑼闁伙絽鍢查～婊堝焵椤掑嫬鏄ラ柣鎰綑缁剁偞鎱ㄥ┑鍡樻拱妞ゅ孩顨婂濠氬磼濮橆兘鍋撳畡鎳婂綊宕堕澶嬫櫔闂佸搫绋侀崢鑲╃玻濡や椒绻嗛柕鍫濇噺閸ｆ椽鏌涚€ｅ墎绡€闁哄苯绉瑰畷顐﹀礋椤掆偓濞咃絿绱撴担鍝勑ｆ繝銏★耿閸╃偤骞嬮敂钘変汗闂佸湱绮敮妤€鈻撻鐘电＝濞达絿顭堥。鎶芥煕鐎ｎ偆娲撮柛鈺冨仱楠炲鏁傞挊澶夋睏闂備礁婀辩划顖滄暜婵犲嫯濮抽柦妯侯槴閺€浠嬫煟閹邦厼绲婚柟顔藉灴閺岋綁鍩℃繝鍌滀哗濡炪値鍋勭换鎴犳崲濠靛棭娼╂い鎺戝亰缁卞弶绻濋悽闈涗粶婵☆偅鐟╁畷娲醇濠㈩亷缍侀、姘跺焵椤掆偓椤繘鎼圭憴鍕幑闂佸憡渚楅崢婊堝箻閸撲胶锛滃銈嗘婵倗浜搁銏＄厽闁挎繂顦伴弫閬嶆倵闂堟稏鍋㈢€殿喖鐖奸獮瀣偐閸偅绶繝纰夌磿閸嬫垿宕愰弽褜娼栧┑鐘宠壘缁犵娀鏌熼幆褜鍤熸い鈺傜叀閺屾盯骞樺Δ鈧幊鎰版晬濠婂啠鏀介幒鎶藉磹閹剧粯鍤勯柛顐ｆ礀閻撯€愁熆鐠轰警鍎戠紒鐘荤畺閹﹢鎮欓幓鎺嗗亾閹间礁鐒垫い鎺嶇贰濞堟﹢鏌涢幒鎾崇瑲缂佺粯绻傞～婵嬵敇閻愨晛浜鹃柣鎴ｅГ閻撶喖鏌熺€电鍓遍柣鎺嶇矙閺屾稑顫滈崱鏇犲嚬缂備胶绮换鍫ュ箖娴犲顥堟繛鎴烆殕閸╂盯姊绘担渚劸妞ゆ垵妫濋獮鎰板箹娴ｅ摜鍘洪悗骞垮劚椤︻垰顔忓┑鍥ヤ簻闁圭儤鏌ㄧ敮鍓佺磽瀹ュ拑韬鐐诧躬瀵粙顢橀悙闈涘箰濠电偠鎻徊钘夘嚕閸洘鍊靛ù鐓庣摠閳锋帒霉閿濆懏鍟為柟顖氱墦閺岋繝宕奸銏狀潻闁绘挶鍊栨穱濠囶敍濠靛棔姹楅梺鍛婎殕瀹€鎼佸蓟閿濆绫嶉柛灞绢殕鐎氭盯姊烘潪鎵槮缂佸鏁婚獮鍫ュΩ閵夘喗寤洪梺绯曞墲椤ㄥ懐绮昏ぐ鎺撯拺缂備焦顭囩粻鏍ㄦ叏婵犲懎鍚规俊鍙夊姍楠炴鈧稒锚椤庢挾绱撴担鍓插創闁稿骸顭峰畷娲倷閻戞ǚ鎷洪梺鍛婄缚閸庨亶寮告惔銏㈢缁绢參顥撶弧鈧悗瑙勬礃濡炰粙骞冨▎鎾充紶闁告洦鍙庨崥鍛存⒒娴ｇ懓顕滄俊顐＄铻為柛鏇ㄥ灠閻掑灚銇勯幒鎴濃偓鎼佸储閹绢喗鐓欐い鏃傜摂濞堟棃鏌嶉挊澶樻Ц闁宠绉归、妯款槺闂侇収鍨辨穱濠囶敃閵忕媭浠煎銈嗘尭閸氬顕ラ崟顓涘亾閿涘崬瀚褰掓⒒閸屾瑨鍏岄柛妯犲懐绀婂┑鐘叉搐绾捐鈹戦悩鎻掍簽闁绘帊绮欓弻鐔煎箥椤旂⒈鏆梺缁樻尰濞茬喖鐛弽銊︾秶闁告挆鍜冪吹闂備焦瀵х粙鎴犵矓瑜版帒钃熸繛鎴炃氶弸搴ㄧ叓閸ャ劍鐓ユ繛鍫燁殔閳规垿顢欑涵閿嬫暰濠碉紕鍋犲Λ鍕亱闂佸憡鍔戦崝澶娢ｉ崼鐔稿弿婵妫楁晶濠氭煛閸♀晛浜濆ǎ鍥э躬閹瑩顢旈崟銊ヤ壕鐟滃繘鍩€椤掑嫭娑ч柣顓炲€搁悾鐑藉捶椤撶喎纾梺鎯х箺椤鈻撻幆褉鏀介柣鎰级椤ョ偤鏌熺粙娆剧吋鐎规洘鍨块獮鍥敊閻熼澹曢柣鐔哥懃鐎氼厾绮堥埀顒€鈹戦悙鑼勾闁告梹鍨块妴浣糕枎閹惧啿宓嗛梺闈涚箚濡狙囧箯濞差亝鈷戦柤濮愬€曢弸娑㈡煕鐎ｎ亷韬€规洜鏁婚幃銏ゅ礂閼测晛骞堥梺鐟板悑閻ｎ亪宕硅ぐ鎺撳€堕柨鏂垮⒔绾惧吋淇婇妶鍛殭闁哄閰ｉ弻宥夋寠婢舵ɑ鈻堟繝娈垮枓閸嬫捇姊洪幐搴ｂ槈閻庢凹鍓熼悰顔嘉旈崨顔规嫽婵炶揪绲介幉锟犲箚閸儲鐓曞┑鐘插€圭拹锟犳煃瑜滈崜娑㈡偡閹惰棄鐐婂ù锝呭濡偓闂佽鍠掗弲婵堟閹烘嚦鐔兼偂鎼达紕顓奸梻鍌氬€峰ù鍥磻閹版澘鐓曢柛顐犲劚缁€鍫ユ煥閺囩偛鈧綊宕愰崹顔ユ棃鏁愰崨顓熸闂佺粯鎸鹃崰鏍蓟閵娿儮鏀介柛鈩冿供濡倗绱撴担鍝勑ラ柛瀣ㄥ€濆璇测槈閵忕姷鍘撮梺璇″瀻閸屾凹妫滃┑鐘殿暜缁辨洟宕戦幋锕€纾归柡宥庡亝閺嗘粓鏌熼悜妯荤厸闁稿鎸搁～婵嬫偂鎼粹槅娼剧紓鍌欑贰閸犳牠鎮ч幘宕囨殾闁告鍋愬Σ鍫熺箾閸℃ê鐏ユ鐐茬Ч濮婄粯鎷呴搹鐟扮闂佹悶鍔岄悥濂稿极鐎ｎ喗鈷戦悹鍥皺缁犳壆绱掓径濠勭Ш鐎殿喖顭烽弫宥夊礋閵娿儰澹曢梺鎸庣箓缁ㄥジ鏌囬鐐寸厱婵炲棗绻愰顓㈡煛鐏炵硶鍋撳畷鍥ㄦ畷闂侀€炲苯澧寸€规洑鍗冲浠嬵敇閻樿尙銈﹂梻浣侯攰閹活亞绮婚幋鐘典笉婵炴垶鐟ｆ禍婊堟煙閹规劖纭剧悮銊╂⒑闁偛鑻晶顖炴煕閺冣偓椤ㄥ牆危? \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func resetPaginationState() {
        currentCache = .empty
        prevCache = .empty
        nextCache = .empty
        windowBasePageIndex = 0
        windowStartCharIndex = 0
        windowEndCharIndex = 0
        totalPageCount = nil
        windowHistory.removeAll()
        currentPageIndex = 0
    }
    
    private func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        loadChapterContent()
        saveProgress()
    }
    
    private func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        currentChapterIndex += 1
        loadChapterContent()
        saveProgress()
    }
    
    private func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused { ttsManager.resume() } else { ttsManager.pause() }
        } else {
            startTTS()
        }
    }
    
    private func startTTS(pageIndexOverride: Int? = nil) {
        showUIControls = true
        suppressTTSSync = true
        let fallbackIndex = lastTTSSentenceIndex ?? Int(book.durChapterPos ?? 0)
        
        var startIndex = fallbackIndex
        var textForTTS = contentSentences.joined(separator: "\n")
        let pageIndex = pageIndexOverride ?? currentPageIndex
        
        if preferences.readingMode == .horizontal {
            if currentCache.pages.indices.contains(pageIndex) {
                let page = currentCache.pages[pageIndex]
                startIndex = page.startSentenceIndex
                
                if currentCache.paragraphStarts.indices.contains(startIndex) {
                    let sentenceStartGlobal = currentCache.paragraphStarts[startIndex] + currentCache.chapterPrefixLen
                    let pageStartGlobal = page.globalRange.location
                    let offset = max(0, pageStartGlobal - sentenceStartGlobal)
                    
                    if offset > 0 && startIndex < contentSentences.count {
                        let firstSentence = contentSentences[startIndex]
                        if offset < firstSentence.utf16.count {
                            let start = firstSentence.utf16.index(firstSentence.utf16.startIndex, offsetBy: offset)
                            if let strIndex = String.Index(start, within: firstSentence) {
                                let partialFirstSentence = String(firstSentence[strIndex...])
                                var sentences = [partialFirstSentence]
                                if startIndex + 1 < contentSentences.count {
                                    sentences.append(contentsOf: contentSentences[(startIndex + 1)...])
                                }
                                textForTTS = sentences.joined(separator: "\n")
                                ttsBaseIndex = startIndex
                                startIndex = 0
                            }
                        }
                    } else if startIndex < contentSentences.count {
                        let sentences = contentSentences[startIndex...]
                        textForTTS = sentences.joined(separator: "\n")
                        ttsBaseIndex = startIndex
                        startIndex = 0
                    }
                }
            }
        } else {
            startIndex = currentVisibleSentenceIndex ?? fallbackIndex
            ttsBaseIndex = 0
        }

        let trimmedText = textForTTS.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        lastTTSSentenceIndex = ttsBaseIndex + startIndex

        let shouldSpeakChapterTitle = preferences.readingMode == .horizontal
            && pageIndex == 0
            && currentCache.chapterPrefixLen > 0

        ttsManager.startReading(
            text: textForTTS,
            chapters: chapters,
            currentIndex: currentChapterIndex,
            bookUrl: book.bookUrl ?? "",
            bookSourceUrl: book.origin,
            bookTitle: book.name ?? "\u{9605}\u{8BFB}",
            coverUrl: book.displayCoverUrl,
            onChapterChange: { newIndex in
                currentChapterIndex = newIndex
                loadChapterContent()
                saveProgress()
            },
            startAtSentenceIndex: startIndex,
            shouldSpeakChapterTitle: shouldSpeakChapterTitle
        )
    }
    
    private func preloadNextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        Task { _ = try? await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: currentChapterIndex + 1) }
    }
    
    private func saveProgress() {
        guard let bookUrl = book.bookUrl else { return }
        Task {
            let title = currentChapterIndex < chapters.count ? chapters[currentChapterIndex].title : nil
            let position = Double(ttsManager.isPlaying ? ttsManager.currentSentenceIndex : (lastTTSSentenceIndex ?? 0))
            try? await apiService.saveBookProgress(bookUrl: bookUrl, index: currentChapterIndex, pos: position, title: title)
        }
    }

    private func updateVisibleSentenceIndex(frames: [Int: CGRect], viewportHeight: CGFloat) {
        let visible = frames.filter { $0.value.maxY > 0 && $0.value.minY < viewportHeight }
        if let first = visible.min(by: { $0.value.minY < $1.value.minY }) {
            if first.key != currentVisibleSentenceIndex { currentVisibleSentenceIndex = first.key }
        }
    }

    // MARK: - UI Components
    @ViewBuilder private func topBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("返回") { dismiss() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                    Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "未知章节")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.top, safeArea.top).padding(.horizontal, 12).padding(.bottom, 8).background(.thinMaterial)
            Spacer()
        }
    }
    
    @ViewBuilder private func bottomBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            Spacer()
            controlBar.padding(.bottom, safeArea.bottom).background(.thinMaterial)
        }
    }
    
    private var loadingOverlay: some View {
        ProgressView("加载中...").padding().background(Color(UIColor.systemBackground).opacity(0.8)).cornerRadius(10).shadow(radius: 10)
    }

    @ViewBuilder private var controlBar: some View {
        if ttsManager.isPlaying && !contentSentences.isEmpty {
            TTSControlBar(ttsManager: ttsManager, currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true })
        } else {
            NormalControlBar(currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, onPreviousChapter: previousChapter, onNextChapter: nextChapter, onShowChapterList: { showChapterList = true }, onToggleTTS: toggleTTS, onShowFontSettings: { showFontSettings = true })
        }
    }
}

// MARK: - UIPageViewController Wrapper
struct PageSnapshot {
    let pages: [PaginatedPage]
    let renderStore: TextKitRenderStore?
}

struct ReadPageViewController: UIViewControllerRepresentable {
    var snapshot: PageSnapshot
    var prevSnapshot: PageSnapshot?
    var nextSnapshot: PageSnapshot?
    
    @Binding var currentPageIndex: Int
    var isAtChapterStart: Bool
    var isAtChapterEnd: Bool
    var isScrollEnabled: Bool
    var onTransitioningChanged: (Bool) -> Void
    var onTapMiddle: () -> Void
    var onTapLeft: () -> Void
    var onTapRight: () -> Void
    var onChapterChange: (Int) -> Void // offset: -1 or 1

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        // pvc.dataSource is set in updateUIViewController
        pvc.delegate = context.coordinator
        context.coordinator.pageViewController = pvc
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pvc.view.addGestureRecognizer(tap)
        
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        
        // Dynamically enable/disable swipe
        if isScrollEnabled {
            pvc.dataSource = context.coordinator
        } else {
            pvc.dataSource = nil
        }
        
        context.coordinator.updateSnapshotIfNeeded(snapshot, currentPageIndex: currentPageIndex)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReadPageViewController
        private var isAnimating = false
        private var snapshot: PageSnapshot?
        private var pendingSnapshot: PageSnapshot?
        weak var pageViewController: UIPageViewController?

        init(_ parent: ReadPageViewController) { self.parent = parent }
        
        func updateSnapshotIfNeeded(_ newSnapshot: PageSnapshot, currentPageIndex: Int) {
            guard let store = newSnapshot.renderStore, !newSnapshot.pages.isEmpty else { return }
            // Only update if store changed or page count changed drastically (re-pagination)
            // Or if we need to force reset
            if shouldReplaceSnapshot(with: newSnapshot) {
                if isAnimating {
                    pendingSnapshot = newSnapshot
                    return
                }
                snapshot = newSnapshot
            }
            let activeSnapshot = snapshot ?? newSnapshot
            
            // Sync UI if needed
            guard let pvc = pageViewController else { return }
            
            // Check current visible VC
            if let currentVC = pvc.viewControllers?.first as? ReadContentViewController,
               currentVC.chapterOffset == 0,
               currentVC.pageIndex == currentPageIndex,
               currentVC.renderStore === store {
                return
            }
            
            // Set new VC
            if currentPageIndex < activeSnapshot.pages.count {
                let vc = ReadContentViewController(pageIndex: currentPageIndex, renderStore: store, chapterOffset: 0)
                pvc.setViewControllers([vc], direction: .forward, animated: false)
            }
        }
        
        private func shouldReplaceSnapshot(with newSnapshot: PageSnapshot) -> Bool {
            guard let current = snapshot else { return true }
            if current.renderStore !== newSnapshot.renderStore { return true }
            if current.pages.count != newSnapshot.pages.count { return true }
            return false
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            
            // Logic for Current Chapter
            if vc.chapterOffset == 0 {
                let index = vc.pageIndex
                if index > 0 {
                    return ReadContentViewController(pageIndex: index - 1, renderStore: vc.renderStore, chapterOffset: 0)
                } else {
                    // Reached start of current chapter -> Try to fetch Previous Chapter
                    if let prev = parent.prevSnapshot, let store = prev.renderStore, !prev.pages.isEmpty {
                        let lastIndex = prev.pages.count - 1
                        return ReadContentViewController(pageIndex: lastIndex, renderStore: store, chapterOffset: -1)
                    }
                }
            }
            // Logic for Previous Chapter (user is scrolling back deeper into prev chapter)
            else if vc.chapterOffset == -1 {
                let index = vc.pageIndex
                if index > 0 {
                    return ReadContentViewController(pageIndex: index - 1, renderStore: vc.renderStore, chapterOffset: -1)
                }
                // If we reach start of prev chapter, we stop (or could implement prev-prev)
            }
            // Logic for Next Chapter (user scrolled back from next chapter to current)
            else if vc.chapterOffset == 1 {
                let index = vc.pageIndex
                if index > 0 {
                    return ReadContentViewController(pageIndex: index - 1, renderStore: vc.renderStore, chapterOffset: 1)
                } else {
                    // Reached start of Next Chapter -> Go back to Current Chapter
                    if let current = parent.snapshot.renderStore, !parent.snapshot.pages.isEmpty {
                        let lastIndex = parent.snapshot.pages.count - 1
                        return ReadContentViewController(pageIndex: lastIndex, renderStore: current, chapterOffset: 0)
                    }
                }
            }
            
            return nil
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ReadContentViewController else { return nil }
            
            // Logic for Current Chapter
            if vc.chapterOffset == 0 {
                let index = vc.pageIndex
                let pageCount = vc.renderStore.containers.count
                if index < pageCount - 1 {
                    return ReadContentViewController(pageIndex: index + 1, renderStore: vc.renderStore, chapterOffset: 0)
                } else {
                    // Reached end of current chapter -> Try to fetch Next Chapter
                    if let next = parent.nextSnapshot, let store = next.renderStore, !next.pages.isEmpty {
                        return ReadContentViewController(pageIndex: 0, renderStore: store, chapterOffset: 1)
                    }
                }
            }
            // Logic for Next Chapter (user is scrolling deeper into next chapter)
            else if vc.chapterOffset == 1 {
                let index = vc.pageIndex
                let pageCount = vc.renderStore.containers.count
                if index < pageCount - 1 {
                    return ReadContentViewController(pageIndex: index + 1, renderStore: vc.renderStore, chapterOffset: 1)
                }
            }
            // Logic for Previous Chapter (user scrolled forward from prev to current)
            else if vc.chapterOffset == -1 {
                let index = vc.pageIndex
                let pageCount = vc.renderStore.containers.count
                if index < pageCount - 1 {
                    return ReadContentViewController(pageIndex: index + 1, renderStore: vc.renderStore, chapterOffset: -1)
                } else {
                     // Reached end of Prev Chapter -> Go to Current Chapter
                     if let current = parent.snapshot.renderStore, !parent.snapshot.pages.isEmpty {
                         return ReadContentViewController(pageIndex: 0, renderStore: current, chapterOffset: 0)
                     }
                }
            }
            
            return nil
        }
        
        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isAnimating = true
            parent.onTransitioningChanged(true)
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let visibleVC = pvc.viewControllers?.first as? ReadContentViewController {
                // If we are still in current chapter (offset 0), update index
                if visibleVC.chapterOffset == 0 {
                    parent.currentPageIndex = visibleVC.pageIndex
                } 
                // If we successfully switched to Next/Prev chapter
                else {
                    // Notify parent to switch data source completely
                    parent.onChapterChange(visibleVC.chapterOffset)
                }
            }
            isAnimating = false
            parent.onTransitioningChanged(false)
            if let nextSnapshot = pendingSnapshot {
                snapshot = nextSnapshot
                pendingSnapshot = nil
                updateSnapshotIfNeeded(nextSnapshot, currentPageIndex: parent.currentPageIndex)
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let x = gesture.location(in: gesture.view).x
            let w = gesture.view?.bounds.width ?? 0
            if x < w / 3 { parent.onTapLeft() } else if x > w * 2 / 3 { parent.onTapRight() } else { parent.onTapMiddle() }
        }
    }
}

// MARK: - Content View Controller
class ReadContentViewController: UIViewController {
    let pageIndex: Int
    let renderStore: TextKitRenderStore
    let textContainer: NSTextContainer
    let chapterOffset: Int // 0: Current, -1: Prev, 1: Next
    
    private lazy var textView: UITextView = {
        let tv = UITextView(frame: CGRect(origin: .zero, size: renderStore.size), textContainer: textContainer)
        tv.isEditable = false; tv.isScrollEnabled = false; tv.isSelectable = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    init(pageIndex: Int, renderStore: TextKitRenderStore, chapterOffset: Int) {
        self.pageIndex = pageIndex
        self.renderStore = renderStore
        self.textContainer = renderStore.containers[pageIndex]
        self.chapterOffset = chapterOffset
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor), // No extra padding here
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

// MARK: - TextKit Paginator
struct PaginatedPage { let globalRange: NSRange; let startSentenceIndex: Int }
struct WindowPaginationResult {
    let pages: [PaginatedPage]
    let renderStore: TextKitRenderStore?
    let windowStart: Int
    let windowEnd: Int
    let reachedEnd: Bool
}

struct WindowAnchor {
    let startCharIndex: Int
    let basePageIndex: Int
}

final class TextKitRenderStore {
    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    let containers: [NSTextContainer]
    let size: CGSize

    init(textStorage: NSTextStorage, layoutManager: NSLayoutManager, containers: [NSTextContainer], size: CGSize) {
        self.textStorage = textStorage
        self.layoutManager = layoutManager
        self.containers = containers
        self.size = size
    }
}

struct TextKitPaginator {
    static func paginateWindow(
        fullText: NSAttributedString,
        paragraphStarts: [Int],
        prefixLen: Int,
        startCharIndex: Int,
        maxPages: Int,
        size: CGSize
    ) -> WindowPaginationResult {
        guard fullText.length > 0, size.width > 0, size.height > 0 else {
            return WindowPaginationResult(pages: [], renderStore: nil, windowStart: 0, windowEnd: 0, reachedEnd: true)
        }

        let clampedStart = max(0, min(startCharIndex, max(fullText.length - 1, 0)))
        let windowRange = NSRange(location: clampedStart, length: fullText.length - clampedStart)
        let windowText = fullText.attributedSubstring(from: windowRange)

        let textStorage = NSTextStorage(attributedString: windowText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var pages: [PaginatedPage] = []
        var containers: [NSTextContainer] = []
        var windowEnd = clampedStart

        for _ in 0..<maxPages {
            let textContainer = NSTextContainer(size: size)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)
            containers.append(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            if charRange.length == 0 {
                layoutManager.removeTextContainer(at: containers.count - 1)
                containers.removeLast()
                break
            }

            let globalRange = NSRange(location: clampedStart + charRange.location, length: charRange.length)
            let adjustedLocation = max(0, globalRange.location - prefixLen)
            let startIdx = paragraphStarts.lastIndex(where: { $0 <= adjustedLocation }) ?? 0
            pages.append(PaginatedPage(globalRange: globalRange, startSentenceIndex: startIdx))
            windowEnd = NSMaxRange(globalRange)

            if windowEnd >= fullText.length {
                break
            }
        }

        let renderStore = TextKitRenderStore(textStorage: textStorage, layoutManager: layoutManager, containers: containers, size: size)
        let reachedEnd = windowEnd >= fullText.length
        return WindowPaginationResult(pages: pages, renderStore: renderStore, windowStart: clampedStart, windowEnd: windowEnd, reachedEnd: reachedEnd)
    }
    
    static func createAttributedText(sentences: [String], fontSize: CGFloat, lineSpacing: CGFloat, chapterTitle: String?) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = fontSize * 0.5
        paragraphStyle.alignment = .justified
        paragraphStyle.firstLineHeadIndent = fontSize * 2
        
        let result = NSMutableAttributedString()
        if let title = chapterTitle, !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center; titleStyle.paragraphSpacing = fontSize * 2
            result.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: fontSize + 6), .paragraphStyle: titleStyle, .foregroundColor: UIColor.label]))
        }
        
        let body = sentences
            .map { sentence in sentence.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
        result.append(NSAttributedString(string: body, attributes: [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: UIColor.label]))
        return result
    }
    
    static func paragraphStartIndices(sentences: [String]) -> [Int] {
        var starts: [Int] = []; var current = 0
        for (idx, s) in sentences.enumerated() {
            starts.append(current)
            current += (s.trimmingCharacters(in: .whitespacesAndNewlines)).utf16.count + (idx < sentences.count - 1 ? 1 : 0)
        }
        return starts
    }
}

struct ChapterListView: View {
    let chapters: [BookChapter]
    let currentIndex: Int
    let onSelectChapter: (Int) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var isReversed = false
    
    var displayedChapters: [(offset: Int, element: BookChapter)] {
        let enumerated = Array(chapters.enumerated())
        return isReversed ? Array(enumerated.reversed()) : enumerated
    }
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List {
                    ForEach(displayedChapters, id: \.element.id) {
                        item in
                        Button(action: {
                            onSelectChapter(item.offset)
                            dismiss()
                        }) {
                            HStack {
                                Text(item.element.title)
                                    .foregroundColor(item.offset == currentIndex ? .blue : .primary)
                                    .fontWeight(item.offset == currentIndex ? .semibold : .regular)
                                Spacer()
                                if item.offset == currentIndex {
                                    Image(systemName: "book.fill").foregroundColor(.blue).font(.caption)
                                }
                            }
                        }
                        .id(item.offset)
                        .listRowBackground(item.offset == currentIndex ? Color.blue.opacity(0.1) : Color.clear)
                    }
                }
                .navigationTitle("目录（共\(chapters.count)章）")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            withAnimation { isReversed.toggle() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation { proxy.scrollTo(currentIndex, anchor: .center) }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isReversed ? "arrow.up" : "arrow.down")
                                Text(isReversed ? "倒序" : "正序")
                            }
                            .font(.caption)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation { proxy.scrollTo(currentIndex, anchor: .center) }
                    }
                }
            }
        }
    }
}

struct RichTextView: View {
    let sentences: [String]
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let highlightIndex: Int?
    let secondaryIndices: Set<Int>
    let isPlayingHighlight: Bool
    let scrollProxy: ScrollViewProxy?
    
    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.8) {
            ForEach(Array(sentences.enumerated()), id: \.offset) {
                index, sentence in
                Text(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SentenceFramePreferenceKey.self,
                                value: [index: proxy.frame(in: .named("scroll"))]
                            )
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlightColor(for: index))
                            .animation(.easeInOut, value: highlightIndex)
                    )
                    .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let highlightIndex = highlightIndex, let scrollProxy = scrollProxy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { scrollProxy.scrollTo(highlightIndex, anchor: .center) }
                }
            }
        }
    }

    private func highlightColor(for index: Int) -> Color {
        if isPlayingHighlight {
            if index == highlightIndex {
                return Color.blue.opacity(0.2)
            }
            if secondaryIndices.contains(index) {
                return Color.green.opacity(0.18)
            }
            return .clear
        }
        return index == highlightIndex ? Color.orange.opacity(0.2) : .clear
    }
}


private struct SentenceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct TTSControlBar: View {
    @ObservedObject var ttsManager: TTSManager
    let currentChapterIndex: Int
    let chaptersCount: Int
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                Button(action: { ttsManager.previousSentence() }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.backward.circle.fill").font(.title)
                        Text("\u{4E0A}\u{4E00}\u{6BB5}").font(.caption)
                    }
                    .foregroundColor(ttsManager.currentSentenceIndex <= 0 ? .gray : .blue)
                }
                .disabled(ttsManager.currentSentenceIndex <= 0)
                
                Spacer()
                VStack(spacing: 4) {
                    Text("\u{6BB5}\u{843D}\u{8FDB}\u{5EA6}").font(.caption).foregroundColor(.secondary)
                    Text("\(ttsManager.currentSentenceIndex + 1) / \(ttsManager.totalSentences)")
                        .font(.title2).fontWeight(.semibold)
                }
                Spacer()
                
                Button(action: { ttsManager.nextSentence() }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.forward.circle.fill").font(.title)
                        Text("\u{4E0B}\u{4E00}\u{6BB5}").font(.caption)
                    }
                    .foregroundColor(ttsManager.currentSentenceIndex >= ttsManager.totalSentences - 1 ? .gray : .blue)
                }
                .disabled(ttsManager.currentSentenceIndex >= ttsManager.totalSentences - 1)
            }
            .padding(.horizontal, 20).padding(.top, 12)
            
            Divider().padding(.horizontal, 20)
            
            HStack(spacing: 25) {
                Button(action: onPreviousChapter) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.title3)
                        Text("\u{4E0A}\u{4E00}\u{7AE0}").font(.caption2)
                    }
                }.disabled(currentChapterIndex <= 0)
                
                Button(action: onShowChapterList) {
                    VStack(spacing: 2) {
                        Image(systemName: "list.bullet").font(.title3)
                        Text("\u{76EE}\u{5F55}").font(.caption2)
                    }
                }
                
                Spacer()
                Button(action: {
                    if ttsManager.isPaused { ttsManager.resume() } else { ttsManager.pause() }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: ttsManager.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.system(size: 36)).foregroundColor(.blue)
                        Text(ttsManager.isPaused ? "\u{64AD}\u{653E}" : "\u{6682}\u{505C}").font(.caption2)
                    }
                }
                Spacer()
                
                Button(action: { ttsManager.stop() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.red)
                        Text("\u{9000}\u{51FA}").font(.caption2).foregroundColor(.red)
                    }
                }
                
                Button(action: onNextChapter) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.right").font(.title3)
                        Text("\u{4E0B}\u{4E00}\u{7AE0}").font(.caption2)
                    }
                }.disabled(currentChapterIndex >= chaptersCount - 1)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

struct NormalControlBar: View {
    let currentChapterIndex: Int
    let chaptersCount: Int
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onToggleTTS: () -> Void
    let onShowFontSettings: () -> Void
    
    var body: some View {
        HStack(spacing: 30) {
            Button(action: onPreviousChapter) {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.title2)
                    Text("\u{4E0A}\u{4E00}\u{7AE0}").font(.caption2)
                }
            }.disabled(currentChapterIndex <= 0)
            
            Button(action: onShowChapterList) {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet").font(.title2)
                    Text("\u{76EE}\u{5F55}").font(.caption2)
                }
            }
            
            Spacer()
            Button(action: onToggleTTS) {
                VStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .font(.system(size: 32)).foregroundColor(.blue)
                    Text("\u{542C}\u{4E66}").font(.caption2).foregroundColor(.blue)
                }
            }
            Spacer()
            
            Button(action: onShowFontSettings) {
                VStack(spacing: 4) {
                    Image(systemName: "textformat.size").font(.title2)
                    Text("\u{5B57}\u{4F53}").font(.caption2)
                }
            }
            
            Button(action: onNextChapter) {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.title2)
                    Text("\u{4E0B}\u{4E00}\u{7AE0}").font(.caption2)
                }
            }.disabled(currentChapterIndex >= chaptersCount - 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

struct FontSizeSheet: View {
    @ObservedObject var preferences: UserPreferences
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("\u{5B57}\u{4F53}\u{5927}\u{5C0F}: \(String(format: "%.0f", preferences.fontSize))")
                        .font(.headline)
                    Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                }
                
                VStack(spacing: 8) {
                    Text("\u{5DE6}\u{53F3}\u{8FB9}\u{8DDD}: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                        .font(.headline)
                    Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                }

                Toggle("播放时锁定翻页", isOn: $preferences.lockPageOnTTS)
                    .padding(.top)

                Spacer()
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("\u{5B8C}\u{6210}") { 
                        dismiss() 
                    }
                }
            }
        }
    }
}
