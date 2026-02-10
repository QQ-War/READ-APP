import SwiftUI
import UIKit

struct ReadingView: View {
    let book: Book
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var bookshelfStore: BookshelfStore
    @StateObject var ttsManager = TTSManager.shared
    @StateObject var preferences = UserPreferences.shared
    @StateObject private var readerSettings = ReaderSettingsStore(preferences: UserPreferences.shared)
    @StateObject private var replaceRuleViewModel = ReplaceRuleViewModel()

    @State var chapters: [BookChapter] = []
    @State var currentChapterIndex: Int
    @State var currentPos: Double = 0 
    @State private var isMangaMode = false
    @State private var cachedChapters: Set<Int> = []
    
    @State private var showUIControls = false
    @State private var showFontSettings = false
    @State private var showChapterList = false
    @State var isLoading = false
    
    @State private var isForceLandscape = false
    @State private var showDetailFromHeader = false
    @State var toggleTTSAction: (() -> Void)?
    @State var refreshChapterAction: (() -> Void)?
    
    @State private var timerRemaining: Int = 0
    @State private var timerActive = false
    @State private var sleepTimer: Timer? = nil
    
    // 辅助选择相关状态
    @State var showSelectionHelper = false
    @State var textToSelect = ""
    @State var showReplaceRuleEditor = false
    @State var finalPattern = ""

    init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.durChapterIndex ?? 0)
        _currentPos = State(initialValue: book.durChapterPos ?? 0)
    }

    private var currentChapterIsManga: Bool {
        book.type == 2 || readerSettings.manualMangaUrls.contains(book.bookUrl ?? "")
    }

    var body: some View {
        NavigationView {
            GeometryReader { fullScreenProxy in
                ZStack {
                    backgroundView.ignoresSafeArea()
                    
                    let readerView = ReaderContainerRepresentable(
                        book: book,
                        readerSettings: readerSettings,
                        ttsManager: ttsManager,
                        replaceRuleViewModel: replaceRuleViewModel,
                        chapters: $chapters,
                        currentChapterIndex: $currentChapterIndex,
                        isMangaMode: $isMangaMode,
                        isLoading: $isLoading,
                                            onToggleMenu: { withAnimation { showUIControls.toggle() } },
                                            onAddReplaceRule: { text in presentReplaceRuleEditor(selectedText: text) },
                                            onProgressChanged: { _, pos in self.currentPos = pos },
                                            onToggleTTS: { action in self.toggleTTSAction = action },
                                            onRefreshChapter: { action in self.refreshChapterAction = action },
                                            readingMode: readerSettings.readingMode,
                                            safeAreaInsets: fullScreenProxy.safeAreaInsets
                                        )
                    readerView
                        .ignoresSafeArea()
                        .animation(nil, value: showUIControls)

                    NavigationLink(destination: BookDetailView(book: book).environmentObject(bookshelfStore), isActive: $showDetailFromHeader) {
                        EmptyView()
                    }
                    .hidden()
                    
                    if showUIControls {
                        VStack(spacing: 0) {
                            topBar(safeArea: fullScreenProxy.safeAreaInsets)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            Spacer()
                            bottomBar(safeArea: fullScreenProxy.safeAreaInsets)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .ignoresSafeArea(edges: .vertical)
                    }
                    if isLoading { ProgressView().padding().background(.ultraThinMaterial).cornerRadius(ReaderConstants.UI.overlayCornerRadius) }
                }
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .onAppear { refreshCachedStatus() }
            .onChange(of: chapters.count) { _ in refreshCachedStatus() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .id(preferences.isLiquidGlassEnabled)
        .onChange(of: isForceLandscape) { newValue in updateAppOrientation(landscape: newValue) }
        .onDisappear {
            if isForceLandscape { updateAppOrientation(landscape: false) }
            saveProgress()
        }
        .sheet(isPresented: $showChapterList) {
            ChapterListView(
                chapters: chapters,
                currentIndex: currentChapterIndex,
                bookUrl: book.bookUrl ?? "",
                cachedChapters: $cachedChapters,
                onSelectChapter: { index in
                    currentChapterIndex = index
                    showChapterList = false
                },
                onRebuildChapterUrls: {
                    await rebuildChapterUrls()
                }
            )
        }
        .sheet(isPresented: $showFontSettings) { 
            ReaderOptionsSheet(preferences: preferences, isMangaMode: isMangaMode) 
        }
        .sheet(isPresented: $showSelectionHelper) {
            TextSelectionHelperSheet(originalText: textToSelect) { selected in
                self.finalPattern = selected
                self.showReplaceRuleEditor = true
            }
        }
        .sheet(isPresented: $showReplaceRuleEditor) {
            ReplaceRuleEditView(viewModel: replaceRuleViewModel, rule: ReplaceRule(
                id: nil,
                name: "新规则",
                groupname: "手动添加",
                pattern: finalPattern,
                replacement: "",
                scope: book.name,
                scopeTitle: false,
                scopeContent: true,
                excludeScope: "",
                isEnabled: true,
                isRegex: false,
                timeoutMillisecond: 3000,
                ruleorder: 0
            ))
        }
    }

    private var backgroundView: some View {
        ZStack {
            UserPreferences.shared.readingTheme.backgroundSwiftUIColor
        }
    }

    @ViewBuilder
    private func topBar(safeArea: EdgeInsets) -> some View {
        if preferences.isLiquidGlassEnabled {
            // 液态玻璃模式：悬浮胶囊
            HStack(spacing: ReaderConstants.UI.topBarSpacing) {
                Button(action: { dismiss() }) { 
                    Image(systemName: "chevron.left")
                        .font(.system(size: ReaderConstants.UI.topBarButtonSize, weight: .semibold))
                        .padding(ReaderConstants.UI.topBarButtonPadding) 
                }
                
                Button(action: { showDetailFromHeader = true }) {
                    VStack(alignment: .leading, spacing: ReaderConstants.UI.selectionHeaderSpacing) {
                        Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                        Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "正在加载...").font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { refreshChapterAction?() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: ReaderConstants.UI.topBarSecondaryButtonSize, weight: .semibold))
                        .padding(ReaderConstants.UI.topBarButtonPadding)
                }
            }
            .padding(.horizontal, ReaderConstants.UI.topBarHorizontalPadding)
            .padding(.vertical, 8)
            .glassyCard(cornerRadius: 20, padding: 0)
            .padding(.horizontal, 12)
            .padding(.top, safeArea.top + 8)
        } else {
            // 普通模式：原始贴边布局
            VStack(spacing: 0) {
                Color.clear.frame(height: safeArea.top)
                HStack(spacing: ReaderConstants.UI.topBarSpacing) {
                    Button(action: { dismiss() }) { Image(systemName: "chevron.left").font(.system(size: ReaderConstants.UI.topBarButtonSize, weight: .semibold)).padding(ReaderConstants.UI.topBarButtonPadding) }
                    Button(action: { showDetailFromHeader = true }) {
                        VStack(alignment: .leading, spacing: ReaderConstants.UI.selectionHeaderSpacing) {
                            Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                            Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "正在加载...").font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button(action: { refreshChapterAction?() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: ReaderConstants.UI.topBarSecondaryButtonSize, weight: .semibold))
                            .padding(ReaderConstants.UI.topBarButtonPadding)
                    }
                }
                .padding(.horizontal, ReaderConstants.UI.topBarHorizontalPadding).padding(.bottom, ReaderConstants.UI.topBarBottomPadding)
            }
            .background(.thinMaterial)
        }
    }
    
    @ViewBuilder
    private func bottomBar(safeArea: EdgeInsets) -> some View {
        if preferences.isLiquidGlassEnabled {
            // 液态玻璃模式：悬浮胶囊
            VStack(spacing: 0) {
                controlBar
            }
            .padding(.vertical, 8)
            .glassyCard(cornerRadius: 24, padding: 0)
            .padding(.horizontal, 12)
            .padding(.bottom, safeArea.bottom + 12)
        } else {
            // 普通模式：原始贴边布局
            VStack(spacing: 0) {
                controlBar
                Color.clear.frame(height: safeArea.bottom)
            }
            .background(.thinMaterial)
        }
    }

    @ViewBuilder private var controlBar: some View {
        if ttsManager.isPlaying && !isMangaMode {
            TTSControlBar(ttsManager: ttsManager, currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, timerRemaining: timerRemaining, timerActive: timerActive, onPreviousChapter: { previousChapter() }, onNextChapter: { nextChapter() }, onShowChapterList: { showChapterList = true }, onTogglePlayPause: toggleTTS, onSetTimer: { m in toggleSleepTimer(minutes: m) }, onShowFontSettings: { showFontSettings = true })
        } else {
            NormalControlBar(currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, isMangaMode: isMangaMode, isForceLandscape: $isForceLandscape, onPreviousChapter: { previousChapter() }, onNextChapter: { nextChapter() }, onShowChapterList: { showChapterList = true }, onToggleTTS: toggleTTS, onShowFontSettings: { showFontSettings = true })
        }
    }

    private func updateAppOrientation(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
        } else { UIDevice.current.setValue(mask.rawValue, forKey: "orientation") }
    }
    
    private func toggleSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        if minutes == 0 { timerActive = false; return }
        timerRemaining = minutes; timerActive = true
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if self.timerRemaining > 1 { self.timerRemaining -= 1 }
            else { self.timerActive = false; self.sleepTimer?.invalidate(); self.ttsManager.stop() }
        }
    }

    private func refreshCachedStatus() {
        var cached = Set<Int>()
        for chapter in chapters {
            if LocalCacheManager.shared.isChapterCached(bookUrl: book.bookUrl ?? "", index: chapter.index) {
                cached.insert(chapter.index)
            }
        }
        self.cachedChapters = cached
    }

    private func rebuildChapterUrls() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            await MainActor.run {
                chapters = list
                if currentChapterIndex >= list.count {
                    currentChapterIndex = max(0, list.count - 1)
                }
            }
            await MainActor.run {
                refreshChapterAction?()
            }
        } catch {
            print("Rebuild chapter URLs failed: \(error)")
        }
    }
}

// MARK: - Text Selection Helper
struct TextSelectionHelperSheet: View {
    let originalText: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var selectedText: String = ""
    
    private var displayLines: String {
        if originalText.count > 500 {
            return String(originalText.prefix(500))
        }
        return originalText
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if originalText.count > 500 {
                    Text("提示：段落过长，已截取前 500 个字符")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, ReaderConstants.UI.selectionNoticeTopPadding)
                }
                
                NativeTextViewWrapper(text: displayLines, selectedText: $selectedText)
                    .padding()
                
                Divider()
                
                HStack {
                    Button(action: { dismiss() }) {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(ReaderConstants.UI.selectionButtonCornerRadius)
                    }
                    
                    Button(action: {
                        onConfirm(selectedText.isEmpty ? displayLines : selectedText)
                        dismiss()
                    }) {
                        Text(selectedText.isEmpty ? "净化全段" : "净化选定内容")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(ReaderConstants.UI.selectionButtonCornerRadius)
                    }
                }
                .padding()
            }
            .navigationTitle("精确选择规则内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NativeTextViewWrapper: UIViewRepresentable {
    let text: String
    @Binding var selectedText: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 18)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.becomeFirstResponder()
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeTextViewWrapper
        init(_ parent: NativeTextViewWrapper) { self.parent = parent }
        func textViewDidChangeSelection(_ textView: UITextView) {
            if let range = textView.selectedTextRange {
                let selected = textView.text(in: range) ?? ""
                DispatchQueue.main.async {
                    self.parent.selectedText = selected
                }
            }
        }
    }
}
