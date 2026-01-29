import UIKit

final class ReaderProgressCoordinator {
    struct UIContext {
        let isMangaMode: Bool
        let readingMode: ReadingMode
        let currentCache: ChapterCache
        let currentPageIndex: Int
        let readingTheme: ReadingTheme?
        let progressLabel: UILabel
        let rootView: UIView
        let verticalVC: VerticalTextViewController?
        let mangaVC: MangaReaderViewController?
    }

    static func updateProgressUI(context: UIContext) {
        if context.isMangaMode {
            if let m = context.mangaVC {
                let s = m.scrollView
                let offset = s.contentOffset.y + s.contentInset.top
                let maxOffset = s.contentSize.height - s.bounds.height + s.contentInset.top
                if maxOffset > 0 {
                    m.progressLabel.text = ReaderProgressFormatter.percentProgressText(offset: offset, maxOffset: maxOffset)
                } else {
                    m.progressLabel.text = "0%"
                }
                m.progressLabel.isHidden = false
            }
            return
        }

        context.rootView.bringSubviewToFront(context.progressLabel)
        if let theme = context.readingTheme {
            context.progressLabel.textColor = theme.textColor
        } else {
            context.progressLabel.textColor = .white
        }

        if context.readingMode == .horizontal || context.readingMode == .newHorizontal {
            let pagesCount = context.currentCache.pages.count
            if pagesCount == 0 {
                context.progressLabel.text = ""
                context.progressLabel.isHidden = true
                return
            }
            context.progressLabel.text = ReaderProgressFormatter.chapterProgressText(current: context.currentPageIndex + 1, total: pagesCount) ?? ""
            context.progressLabel.isHidden = false
        } else if context.readingMode == .vertical {
            if let v = context.verticalVC {
                let offset = v.scrollView.contentOffset.y + v.scrollView.contentInset.top
                let maxOffset = v.scrollView.contentSize.height - v.scrollView.bounds.height + v.scrollView.contentInset.top
                if maxOffset > 0 {
                    context.progressLabel.text = ReaderProgressFormatter.percentProgressText(offset: offset, maxOffset: maxOffset)
                } else {
                    context.progressLabel.text = "0%"
                }
            }
            context.progressLabel.isHidden = false
        } else {
            context.progressLabel.text = ""
            context.progressLabel.isHidden = true
        }
    }

    static func calculateProgress(
        isMangaMode: Bool,
        readingMode: ReadingMode,
        currentCache: ChapterCache,
        currentPageIndex: Int,
        verticalVC: VerticalTextViewController?,
        mangaVC: MangaReaderViewController?
    ) -> Double {
        if readingMode == .vertical {
            if isMangaMode {
                return Double(mangaVC?.currentVisibleIndex ?? 0)
            }
            let count = max(1, currentCache.contentSentences.count)
            let idx = verticalVC?.lastReportedIndex ?? 0
            return Double(idx) / Double(count)
        }
        if !currentCache.pages.isEmpty {
            return Double(currentPageIndex) / Double(currentCache.pages.count)
        }
        return 0.0
    }

    static func saveProgress(
        book: Book,
        chapters: [BookChapter],
        currentChapterIndex: Int,
        isMangaMode: Bool,
        readingMode: ReadingMode,
        currentCache: ChapterCache,
        currentPageIndex: Int,
        verticalVC: VerticalTextViewController?,
        mangaVC: MangaReaderViewController?
    ) async {
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let pos = calculateProgress(
            isMangaMode: isMangaMode,
            readingMode: readingMode,
            currentCache: currentCache,
            currentPageIndex: currentPageIndex,
            verticalVC: verticalVC,
            mangaVC: mangaVC
        )
        UserDefaults.standard.set(currentChapterIndex, forKey: "lastChapter_\(book.bookUrl ?? "")")
        try? await APIService.shared.saveBookProgress(bookUrl: book.bookUrl ?? "", index: currentChapterIndex, pos: pos, title: title)
    }
}
