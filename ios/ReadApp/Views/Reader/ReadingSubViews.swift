import SwiftUI
import UIKit

struct SentenceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Other Views
class ReadContentViewController: UIViewController, UIGestureRecognizerDelegate {
    let pageIndex: Int
    let renderStore: TextKit2RenderStore?
    let sentences: [String]?
    let chapterUrl: String? // 新增
    let chapterOffset: Int
    let onAddReplaceRule: ((String) -> Void)?
    let onTapLocation: ((ReaderTapLocation) -> Void)?
    let onImageTapped: ((URL) -> Void)?
    
    // Highlight state
    var highlightIndex: Int?
    var secondaryIndices: Set<Int> = []
    var isPlayingHighlight: Bool = false
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
    private var tk2View: ReadContent2View?
    private var pendingPageInfo: TK2PageInfo?
    
    init(pageIndex: Int, renderStore: TextKit2RenderStore?, sentences: [String]? = nil, chapterUrl: String? = nil, chapterOffset: Int, onAddReplaceRule: ((String) -> Void)?, onTapLocation: ((ReaderTapLocation) -> Void)?, onImageTapped: ((URL) -> Void)? = nil) {
        self.pageIndex = pageIndex
        self.renderStore = renderStore
        self.sentences = sentences
        self.chapterUrl = chapterUrl
        self.chapterOffset = chapterOffset
        self.onAddReplaceRule = onAddReplaceRule
        self.onTapLocation = onTapLocation
        self.onImageTapped = onImageTapped
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        if let store = renderStore {
            setupTK2View(store: store)
        }
    }
    
    private func setupTK2View(store: TextKit2RenderStore) {
         let v = ReadContent2View(frame: view.bounds)
         v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
         v.renderStore = store
         v.onTapLocation = onTapLocation
         v.onImageTapped = onImageTapped
         v.onAddReplaceRule = onAddReplaceRule
         v.highlightIndex = highlightIndex
         v.secondaryIndices = secondaryIndices
         v.isPlayingHighlight = isPlayingHighlight
         v.paragraphStarts = paragraphStarts
         v.chapterPrefixLen = chapterPrefixLen
         view.addSubview(v)
         self.tk2View = v
         if let pendingPageInfo {
             v.pageInfo = pendingPageInfo
             v.setNeedsDisplay()
         }
    }
    
    func updateHighlights(index: Int?, secondary: Set<Int>, isPlaying: Bool, starts: [Int], prefixLen: Int) {
        self.highlightIndex = index
        self.secondaryIndices = secondary
        self.isPlayingHighlight = isPlaying
        self.paragraphStarts = starts
        self.chapterPrefixLen = prefixLen
        
        tk2View?.highlightIndex = index
        tk2View?.secondaryIndices = secondary
        tk2View?.isPlayingHighlight = isPlaying
        tk2View?.paragraphStarts = starts
        tk2View?.chapterPrefixLen = prefixLen
        tk2View?.setNeedsDisplay()
    }
    
    func configureTK2Page(info: TK2PageInfo) {
        pendingPageInfo = info
        tk2View?.pageInfo = info
        tk2View?.setNeedsDisplay()
    }

    func redraw() {
        tk2View?.setNeedsDisplay()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

struct TextKitPaginator {
    static func createAttributedText(sentences: [String], fontSize: CGFloat, lineSpacing: CGFloat, chapterTitle: String?) -> NSAttributedString {
        let font = ReaderFontProvider.bodyFont(size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = fontSize * ReaderConstants.Text.paragraphSpacingFactor
        paragraphStyle.alignment = .justified
        paragraphStyle.firstLineHeadIndent = fontSize * 1.5
        
        let result = NSMutableAttributedString()
        if let title = chapterTitle, !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center; titleStyle.paragraphSpacing = fontSize * 2
            result.append(NSAttributedString(string: title + "\n", attributes: [.font: ReaderFontProvider.titleFont(size: fontSize + 6), .paragraphStyle: titleStyle, .foregroundColor: UserPreferences.shared.readingTheme.textColor]))
        }
        
        let body = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
        result.append(NSAttributedString(string: body, attributes: [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: UserPreferences.shared.readingTheme.textColor]))
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
    let bookUrl: String
    @Binding var cachedChapters: Set<Int>
    let onSelectChapter: (Int) -> Void
    let onRebuildChapterUrls: (() async -> Void)?
    @Environment(\.dismiss) var dismiss
    @State private var isReversed = false
    @State private var selectedGroupIndex: Int
    @State private var isRebuilding = false
    
    init(
        chapters: [BookChapter],
        currentIndex: Int,
        bookUrl: String,
        cachedChapters: Binding<Set<Int>> = .constant([]),
        onSelectChapter: @escaping (Int) -> Void,
        onRebuildChapterUrls: (() async -> Void)? = nil
    ) {
        self.chapters = chapters
        self.currentIndex = currentIndex
        self.bookUrl = bookUrl
        self._cachedChapters = cachedChapters
        self.onSelectChapter = onSelectChapter
        self.onRebuildChapterUrls = onRebuildChapterUrls
        self._selectedGroupIndex = State(initialValue: currentIndex / ReaderConstants.Text.chapterGroupSize)
    }
    
    var chapterGroups: [Int] {
        guard !chapters.isEmpty else { return [] }
        return Array(0...((chapters.count - 1) / ReaderConstants.Text.chapterGroupSize))
    }
    
    var displayedChapters: [(offset: Int, element: BookChapter)] {
        let startIndex = selectedGroupIndex * ReaderConstants.Text.chapterGroupSize
        let endIndex = min(startIndex + ReaderConstants.Text.chapterGroupSize, chapters.count)
        let slice = chapters.indices.contains(startIndex) ? Array(chapters[startIndex..<endIndex].enumerated()).map { (offset: $0.offset + startIndex, element: $0.element) } : []
        return isReversed ? Array(slice.reversed()) : slice
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if chapterGroups.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: ReaderConstants.List.groupSpacing) {
                            ForEach(chapterGroups, id: \.self) { index in
                                let start = index * ReaderConstants.Text.chapterGroupSize + 1
                                let end = min((index + 1) * ReaderConstants.Text.chapterGroupSize, chapters.count)
                                Button(action: { selectedGroupIndex = index }) {
                                    Text("\(start)-\(end)")
                                        .font(.caption)
                                        .padding(.horizontal, ReaderConstants.List.groupHorizontalPadding)
                                        .padding(.vertical, ReaderConstants.List.groupVerticalPadding)
                                        .background(selectedGroupIndex == index ? Color.blue : Color.gray.opacity(0.1))
                                        .foregroundColor(selectedGroupIndex == index ? .white : .primary)
                                        .cornerRadius(ReaderConstants.List.groupCornerRadius)
                                }
                                .glassyButtonStyle()
                            }
                        }
                        .padding()
                    }
                    Divider()
                }
                
                ScrollViewReader {
                    proxy in
                    List {
                        ForEach(displayedChapters, id: \.element.id) { item in
                            Button(action: {
                                onSelectChapter(item.offset)
                                dismiss()
                            }) {
                                HStack {
                                    Text(item.element.title)
                                        .foregroundColor(item.offset == currentIndex ? .blue : .primary)
                                        .fontWeight(item.offset == currentIndex ? .semibold : .regular)
                                    Spacer()
                                    if cachedChapters.contains(item.element.index) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                    if item.offset == currentIndex {
                                        Image(systemName: "book.fill").foregroundColor(.blue).font(.caption)
                                    }
                                }
                            }
                            .id(item.offset)
                            .listRowBackground(item.offset == currentIndex ? Color.blue.opacity(0.1) : Color.clear)
                            .glassyCard(cornerRadius: 12, padding: 6)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if cachedChapters.contains(item.element.index) {
                                    Button(role: .destructive) {
                                        LocalCacheManager.shared.clearChapterCache(bookUrl: bookUrl, index: item.element.index)
                                        cachedChapters.remove(item.element.index)
                                    } label: {
                                        Label("清除缓存", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("目录（共\(chapters.count)章）")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("关闭") { dismiss() }
                                .glassyToolbarButton()
                        }
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Button(action: {
                                withAnimation { isReversed.toggle() }
                            }) {
                                HStack(spacing: ReaderConstants.List.toolbarSpacing) {
                                    Image(systemName: isReversed ? "arrow.up" : "arrow.down")
                                    Text(isReversed ? "倒序" : "正序")
                                }.font(.caption)
                            }
                            .glassyToolbarButton()
                            Button(action: {
                                guard !isRebuilding else { return }
                                isRebuilding = true
                                Task {
                                    await onRebuildChapterUrls?()
                                    await MainActor.run { isRebuilding = false }
                                }
                            }) {
                                HStack(spacing: ReaderConstants.List.toolbarSpacing) {
                                    if isRebuilding {
                                        ProgressView().scaleEffect(0.7)
                                    }
                                    Text("重建URL")
                                }
                                .font(.caption)
                            }
                            .glassyToolbarButton()
                        }
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
    var chapterUrl: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * ReaderConstants.Text.chapterGroupSpacingFactor) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                if sentence.contains("__IMG__") {
                    let urlString = extractImageUrl(from: sentence)
                    MangaImageView(url: urlString, referer: chapterUrl)
                        .id(index)
                        .padding(.vertical, ReaderConstants.List.inlineImagePadding)
                } else {
                    Text(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, ReaderConstants.List.textVerticalPadding)
                        .padding(.horizontal, ReaderConstants.List.textHorizontalPadding)
                        .background(GeometryReader { proxy in Color.clear.preference(key: SentenceFramePreferenceKey.self, value: [index: proxy.frame(in: .named("scroll"))]) })
                        .background(RoundedRectangle(cornerRadius: ReaderConstants.List.textCornerRadius).fill(highlightColor(for: index)).animation(.easeInOut, value: highlightIndex))
                        .id(index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let highlightIndex = highlightIndex, let scrollProxy = scrollProxy {
                DispatchQueue.main.asyncAfter(deadline: .now() + ReaderConstants.List.scrollToHighlightDelay) { withAnimation { scrollProxy.scrollTo(highlightIndex, anchor: .center) } }
            }
        }
    }
    
    private func extractImageUrl(from text: String) -> String {
        // 查找 __IMG__ 标记后的内容，直到遇到空格或结尾
        guard let range = text.range(of: "__IMG__") else { return "" }
        let urlPart = text[range.upperBound...]
        // 提取连续的 URL 字符，遇到换行或空格停止
        let url = urlPart.prefix { !$0.isWhitespace }
        return String(url)
    }

    private func highlightColor(for index: Int) -> Color {
        if isPlayingHighlight {
            if index == highlightIndex { return Color.blue.opacity(ReaderConstants.Highlight.listPrimaryAlpha) }
            if secondaryIndices.contains(index) { return Color.green.opacity(0.18) }
            return .clear
        }
        return index == highlightIndex ? Color.orange.opacity(ReaderConstants.Highlight.listPrimaryAlpha) : .clear
    }
}

struct MangaImageView: View {
    let url: String
    let referer: String?
    @StateObject private var preferences = UserPreferences.shared
    private let logger = LogManager.shared
    
    var body: some View {
        let finalURL = resolveURL(url)
        RemoteImageView(url: finalURL, refererOverride: referer)
            .frame(maxWidth: .infinity)
            .onAppear {
                if preferences.isVerboseLoggingEnabled {
                    let logReferer = referer?.replacingOccurrences(of: "http://", with: "https://") ?? "无"
                }
            }
    }
    
    private func resolveURL(_ original: String) -> URL? {
        ImageGatewayService.shared.resolveImageURL(original, baseURLString: referer)
    }
}
