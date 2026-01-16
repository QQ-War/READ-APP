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
    
    // Highlight state
    var highlightIndex: Int?
    var secondaryIndices: Set<Int> = []
    var isPlayingHighlight: Bool = false
    var paragraphStarts: [Int] = []
    var chapterPrefixLen: Int = 0
    
    private var tk2View: ReadContent2View?
    private var pendingPageInfo: TK2PageInfo?
    
    init(pageIndex: Int, renderStore: TextKit2RenderStore?, sentences: [String]? = nil, chapterUrl: String? = nil, chapterOffset: Int, onAddReplaceRule: ((String) -> Void)?, onTapLocation: ((ReaderTapLocation) -> Void)?) {
        self.pageIndex = pageIndex
        self.renderStore = renderStore
        self.sentences = sentences
        self.chapterUrl = chapterUrl
        self.chapterOffset = chapterOffset
        self.onAddReplaceRule = onAddReplaceRule
        self.onTapLocation = onTapLocation
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
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = fontSize * 0.5
        paragraphStyle.alignment = .justified
        paragraphStyle.firstLineHeadIndent = fontSize * 1.5
        
        let result = NSMutableAttributedString()
        if let title = chapterTitle, !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center; titleStyle.paragraphSpacing = fontSize * 2
            result.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: fontSize + 6), .paragraphStyle: titleStyle, .foregroundColor: UIColor.label]))
        }
        
        let body = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
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
    let bookUrl: String
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
        onSelectChapter: @escaping (Int) -> Void,
        onRebuildChapterUrls: (() async -> Void)? = nil
    ) {
        self.chapters = chapters
        self.currentIndex = currentIndex
        self.bookUrl = bookUrl
        self.onSelectChapter = onSelectChapter
        self.onRebuildChapterUrls = onRebuildChapterUrls
        self._selectedGroupIndex = State(initialValue: currentIndex / 50)
    }
    
    var chapterGroups: [Int] {
        guard !chapters.isEmpty else { return [] }
        return Array(0...((chapters.count - 1) / 50))
    }
    
    var displayedChapters: [(offset: Int, element: BookChapter)] {
        let startIndex = selectedGroupIndex * 50
        let endIndex = min(startIndex + 50, chapters.count)
        let slice = chapters.indices.contains(startIndex) ? Array(chapters[startIndex..<endIndex].enumerated()).map { (offset: $0.offset + startIndex, element: $0.element) } : []
        return isReversed ? Array(slice.reversed()) : slice
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if chapterGroups.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chapterGroups, id: \.self) { index in
                                let start = index * 50 + 1
                                let end = min((index + 1) * 50, chapters.count)
                                Button(action: { selectedGroupIndex = index }) {
                                    Text("\(start)-\(end)")
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedGroupIndex == index ? Color.blue : Color.gray.opacity(0.1))
                                        .foregroundColor(selectedGroupIndex == index ? .white : .primary)
                                        .cornerRadius(16)
                                }
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
                                    if LocalCacheManager.shared.isChapterCached(bookUrl: bookUrl, index: item.offset) {
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
                        }
                    }
                    .navigationTitle("目录（共\(chapters.count)章）")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                withAnimation { isReversed.toggle() }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isReversed ? "arrow.up" : "arrow.down")
                                    Text(isReversed ? "倒序" : "正序")
                                }.font(.caption)
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                guard !isRebuilding else { return }
                                isRebuilding = true
                                Task {
                                    await onRebuildChapterUrls?()
                                    await MainActor.run { isRebuilding = false }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if isRebuilding {
                                        ProgressView().scaleEffect(0.7)
                                    }
                                    Text("重建URL")
                                }
                                .font(.caption)
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("关闭") { dismiss() }
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
        VStack(alignment: .leading, spacing: fontSize * 0.8) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                if sentence.contains("__IMG__") {
                    let urlString = extractImageUrl(from: sentence)
                    MangaImageView(url: urlString, referer: chapterUrl)
                        .id(index)
                        .padding(.vertical, 4)
                } else {
                    Text(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(GeometryReader { proxy in Color.clear.preference(key: SentenceFramePreferenceKey.self, value: [index: proxy.frame(in: .named("scroll"))]) })
                        .background(RoundedRectangle(cornerRadius: 4).fill(highlightColor(for: index)).animation(.easeInOut, value: highlightIndex))
                        .id(index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let highlightIndex = highlightIndex, let scrollProxy = scrollProxy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { scrollProxy.scrollTo(highlightIndex, anchor: .center) } }
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
            if index == highlightIndex { return Color.blue.opacity(0.2) }
            if secondaryIndices.contains(index) { return Color.green.opacity(0.18) }
            return .clear
        }
        return index == highlightIndex ? Color.orange.opacity(0.2) : .clear
    }
}

struct MangaImageView: View {
    let url: String
    let referer: String?
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    private let logger = LogManager.shared
    
    var body: some View {
        let finalURL = resolveURL(url)
        RemoteImageView(url: finalURL, refererOverride: referer)
            .frame(maxWidth: .infinity)
            .onAppear {
                if preferences.isVerboseLoggingEnabled {
                    let logReferer = referer?.replacingOccurrences(of: "http://", with: "https://") ?? "无"
                    logger.log("准备加载图片: \(finalURL?.lastPathComponent ?? "无效"), 来源: \(logReferer)", category: "漫画调试")
                }
            }
    }
    
    private func resolveURL(_ original: String) -> URL? {
        if original.hasPrefix("http") {
            return URL(string: original)
        }
        let baseURL = ApiBackendResolver.stripApiBasePath(apiService.baseURL)
        let resolved = original.hasPrefix("/") ? (baseURL + original) : (baseURL + "/" + original)
        return URL(string: resolved)
    }
}
