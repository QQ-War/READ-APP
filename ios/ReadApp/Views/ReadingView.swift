import SwiftUI
import UIKit

// MARK: - ReadingView
enum ReaderTapLocation {
    case left, right, middle
}

struct ReadingView: View {
    let book: Book
    private let logger = LogManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var apiService: APIService
    @StateObject var ttsManager = TTSManager.shared
    @StateObject var preferences = UserPreferences.shared
    @StateObject private var replaceRuleViewModel = ReplaceRuleViewModel()

    // 状态对齐：与 ReaderContainer 共享
    @State var chapters: [BookChapter] = []
    @State var currentChapterIndex: Int
    @State var currentPos: Double = 0 
    
    @State private var showUIControls = false
    @State private var showFontSettings = false
    @State private var showChapterList = false
    @State var isLoading = false
    @State var errorMessage: String?
    
    @State private var isForceLandscape = false
    @State private var showDetailFromHeader = false
    
    @State private var timerRemaining: Int = 0
    @State private var timerActive = false
    @State private var sleepTimer: Timer? = nil

    init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.durChapterIndex ?? 0)
        _currentPos = State(initialValue: book.durChapterPos ?? 0)
    }

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                ZStack {
                    backgroundView
                    
                    // 核心容器：接管所有阅读渲染与逻辑
                    ReaderContainerRepresentable(
                        book: book,
                        preferences: preferences,
                        ttsManager: ttsManager,
                        replaceRuleViewModel: replaceRuleViewModel,
                        chapters: $chapters,
                        currentChapterIndex: $currentChapterIndex,
                        onToggleMenu: { withAnimation { showUIControls.toggle() } },
                        onAddReplaceRule: { text in presentReplaceRuleEditor(selectedText: text) },
                        onProgressChanged: { _, pos in self.currentPos = pos },
                        readingMode: preferences.readingMode
                    )
                    .ignoresSafeArea()
                    
                    if showUIControls {
                        topBar(safeArea: proxy.safeAreaInsets)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        bottomBar(safeArea: proxy.safeAreaInsets)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if isLoading { loadingOverlay }
                }
                .animation(.easeInOut(duration: 0.2), value: showUIControls)
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: isForceLandscape) { newValue in
            updateAppOrientation(landscape: newValue)
        }
        .onDisappear {
            if isForceLandscape { updateAppOrientation(landscape: false) }
            saveProgress()
        }
        .sheet(isPresented: $showChapterList) { 
            ChapterListView(chapters: chapters, currentIndex: currentChapterIndex, bookUrl: book.bookUrl ?? "") { index in
                currentChapterIndex = index
                showChapterList = false
            } 
        }
        .sheet(isPresented: $showFontSettings) { 
            ReaderOptionsSheet(preferences: preferences, isMangaMode: false) 
        }
    }

    private var backgroundView: some View { Color(UIColor.systemBackground) }

    @ViewBuilder private func topBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("返回") { dismiss() }
                
                Button(action: { showDetailFromHeader = true }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                        Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "未知章节").font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    NavigationLink(destination: BookDetailView(book: book).environmentObject(apiService), isActive: $showDetailFromHeader) {
                        EmptyView()
                    }
                )
                
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

    private var loadingOverlay: some View { ProgressView("加载中...").padding().background(Material.regular).cornerRadius(10).shadow(radius: 10) }

    @ViewBuilder private var controlBar: some View {
        if ttsManager.isPlaying {
            TTSControlBar(
                ttsManager: ttsManager,
                currentChapterIndex: currentChapterIndex,
                chaptersCount: chapters.count,
                timerRemaining: timerRemaining,
                timerActive: timerActive,
                onPreviousChapter: { previousChapter() },
                onNextChapter: { nextChapter() },
                onShowChapterList: { showChapterList = true },
                onTogglePlayPause: toggleTTS,
                onSetTimer: { minutes in toggleSleepTimer(minutes: minutes) }
            )
        } else {
            NormalControlBar(
                currentChapterIndex: currentChapterIndex,
                chaptersCount: chapters.count,
                isMangaMode: false,
                isForceLandscape: $isForceLandscape,
                onPreviousChapter: { previousChapter() },
                onNextChapter: { nextChapter() },
                onShowChapterList: { showChapterList = true },
                onToggleTTS: toggleTTS,
                onShowFontSettings: { showFontSettings = true }
            )
        }
    }

    private func updateAppOrientation(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
        } else {
            UIDevice.current.setValue(mask.rawValue, forKey: "orientation")
        }
    }
    
    private func toggleSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        if minutes == 0 { timerActive = false; return }
        timerRemaining = minutes
        timerActive = true
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if self.timerRemaining > 1 { self.timerRemaining -= 1 }
            else { self.timerActive = false; self.sleepTimer?.invalidate(); self.ttsManager.stop() }
        }
    }
}
