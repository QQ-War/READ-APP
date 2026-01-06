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
    
    @State private var showUIControls = false
    @State private var showFontSettings = false
    @State private var showChapterList = false
    @State var isLoading = false
    
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
        ZStack {
            // 核心容器：忽略安全区以铺满全屏
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
            
            // 控件层：必须显式处理安全区
            if showUIControls {
                VStack(spacing: 0) {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                    
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // 关键：确保控件贴边且避开刘海/底条
                .ignoresSafeArea(edges: .bottom) 
            }
            
            if isLoading { ProgressView("加载中...").padding().background(.ultraThinMaterial).cornerRadius(10) }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
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
            ReaderOptionsSheet(preferences: preferences, isMangaMode: false) 
        }
    }

    private var backgroundView: some View { Color(UIColor.systemBackground) }

    private var topBar: some View {
        VStack(spacing: 0) {
            // 顶部的安全区填充
            Color.clear.frame(height: UIApplication.shared.windows.first?.safeAreaInsets.top ?? 44)
            
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left").font(.title3).padding(8)
                }
                
                Button(action: { showDetailFromHeader = true }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.name ?? "阅读").font(.headline).fontWeight(.bold).lineLimit(1)
                        Text(chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "加载中...").font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    NavigationLink(destination: BookDetailView(book: book).environmentObject(apiService), isActive: $showDetailFromHeader) { EmptyView() }
                )
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(.thinMaterial)
    }
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            controlBar
            // 底部的安全区填充
            Color.clear.frame(height: UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 34)
        }
        .background(.thinMaterial)
    }

    @ViewBuilder private var controlBar: some View {
        if ttsManager.isPlaying {
            TTSControlBar(ttsManager: ttsManager, currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, timerRemaining: timerRemaining, timerActive: timerActive, onPreviousChapter: { previousChapter() }, onNextChapter: { nextChapter() }, onShowChapterList: { showChapterList = true }, onTogglePlayPause: toggleTTS, onSetTimer: { m in toggleSleepTimer(minutes: m) })
        } else {
            NormalControlBar(currentChapterIndex: currentChapterIndex, chaptersCount: chapters.count, isMangaMode: false, isForceLandscape: $isForceLandscape, onPreviousChapter: { previousChapter() }, onNextChapter: { nextChapter() }, onShowChapterList: { showChapterList = true }, onToggleTTS: toggleTTS, onShowFontSettings: { showFontSettings = true })
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
        timerRemaining = minutes; timerActive = true
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if self.timerRemaining > 1 { self.timerRemaining -= 1 }
            else { self.timerActive = false; self.sleepTimer?.invalidate(); self.ttsManager.stop() }
        }
    }
}
