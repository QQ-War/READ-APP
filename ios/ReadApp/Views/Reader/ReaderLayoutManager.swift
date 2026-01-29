import Foundation

final class ReaderLayoutManager {
    func buildCache(
        isMangaMode: Bool,
        rawContent: String,
        title: String,
        chapterUrl: String?,
        layoutSpec: ReaderLayoutSpec,
        builder: ReaderChapterBuilder,
        reuseStore: TextKit2RenderStore?,
        anchorOffset: Int
    ) -> ChapterCache {
        if isMangaMode {
            return builder.buildMangaCache(rawContent: rawContent, chapterUrl: chapterUrl)
        }
        return builder.buildTextCache(
            rawContent: rawContent,
            title: title,
            layoutSpec: layoutSpec,
            reuseStore: reuseStore,
            chapterUrl: chapterUrl,
            anchorOffset: anchorOffset
        )
    }
}
