import SwiftUI
import UIKit

struct ReadingView: View {
    let book: Book
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var apiService: APIService
    @StateObject var ttsManager = TTSManager.shared
    @StateObject var preferences = UserPreferences.shared
    @StateObject private var replaceRuleViewModel = ReplaceRuleViewModel()

    @State var chapters: [BookChapter] = []
    @State var currentChapterIndex: Int
    @State var currentPos: Double = 0 
    @State private var isMangaMode = false
    
    @State private var showUIControls = false
    @State private var showFontSettings = false
    @State private var showChapterList = false
    @State var isLoading = false
    
    @State private var isForceLandscape = false
    @State private var showDetailFromHeader = false
    @State var toggleTTSAction: (() -> Void)?
    
    @State private var timerRemaining: Int = 0
    @State private var timerActive = false
    @State private var sleepTimer: Timer? = nil

    init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.durChapterIndex ?? 0)
        _currentPos = State(initialValue: book.durChapterPos ?? 0)
    }

    private var currentChapterIsManga: Bool {
        book.type == 2 || preferences.manualMangaUrls.contains(book.bookUrl ?? "")
    }

    var body: some View {
        NavigationView {
            GeometryReader { fullScreenProxy in
                ZStack {
                    backgroundView.ignoresSafeArea()
                    
                    ReaderContainerRepresentable(
                        book: book,
                        preferences: preferences,
                        ttsManager: ttsManager,
                        replaceRuleViewModel: replaceRuleViewModel,
                        chapters: $chapters,
                        currentChapterIndex: $currentChapterIndex,
                        isMangaMode: $isMangaMode,
                                            onToggleMenu: { withAnimation { showUIControls.toggle() } },
                                            onAddReplaceRule: { text in presentReplaceRuleEditor(selectedText: text) },
                                            onProgressChanged: { _, pos in self.currentPos = pos },
                                            onToggleTTS: { action in self.toggleTTSAction = action },
                                            readingMode: preferences.readingMode,
                                            safeAreaInsets: fullScreenProxy.safeAreaInsets
                                        )                    .ignoresSafeArea()

                    NavigationLink(destination: BookDetailView(book: book).environmentObject(apiService), isActive: $showDetailFromHeader) {
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
                    if isLoading { ProgressView().padding().background(.ultraThinMaterial).cornerRadius(10) }
                }
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: isForceLandscape) { newValue in updateAppOrientation(landscape: newValue) }
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
            ReaderOptionsSheet(preferences: preferences, isMangaMode: isMangaMode) 
        }
    }

    private var backgroundView: some View { Color(UIColor.systemBackground) }

    private func topBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: safeArea.top)
            HStack(spacing: 12) {
                Button(action: { dismiss() }) { Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).padding(8) }
                Button(action: { showDetailFromHeader = true }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                        Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "正在加载...").font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
        .background(.thinMaterial)
    }
    
    private func bottomBar(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            controlBar
            Color.clear.frame(height: safeArea.bottom)
        }
        .background(.thinMaterial)
    }

    @ViewBuilder private var controlBar: some View {
        if ttsManager.isPlaying && !isMangaMode {
            TTSControlBar(ttsManager: ttsManager, currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, timerRemaining: timerRemaining, timerActive: timerActive, onPreviousChapter: { previousChapter() }, onNextChapter: { nextChapter() }, onShowChapterList: { showChapterList = true }, onTogglePlayPause: toggleTTS, onSetTimer: { m in toggleSleepTimer(minutes: m) })
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
}
