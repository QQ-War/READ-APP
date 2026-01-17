import Foundation
import CryptoKit

class LocalCacheManager {
    static let shared = LocalCacheManager()
    private let fileManager = FileManager.default
    
    private var baseDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BookCache")
    }
    
    private init() {
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }
    
    // 生成书籍唯一的文件夹名（使用 MD5 哈希 URL）
    private func bookDir(for bookUrl: String) -> URL {
        let hashString = md5Hex(bookUrl)
        return baseDir.appendingPathComponent(hashString)
    }

    private func md5Hex(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = Insecure.MD5.hash(data: inputData)
        return hashed.map { String(format: "%02hhx", $0) }.joined()
    }
    
    // MARK: - 章节正文缓存
    
    func saveChapter(bookUrl: String, index: Int, content: String) {
        let dir = bookDir(for: bookUrl)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(index).raw")
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }
    
    func loadChapter(bookUrl: String, index: Int) -> String? {
        let file = bookDir(for: bookUrl).appendingPathComponent("\(index).raw")
        return try? String(contentsOf: file, encoding: .utf8)
    }
    
    func isChapterCached(bookUrl: String, index: Int) -> Bool {
        let file = bookDir(for: bookUrl).appendingPathComponent("\(index).raw")
        return fileManager.fileExists(atPath: file.path)
    }

    // MARK: - 漫画图片缓存

    private func mangaImageDir(bookUrl: String, chapterIndex: Int) -> URL {
        bookDir(for: bookUrl)
            .appendingPathComponent("manga")
            .appendingPathComponent("\(chapterIndex)")
    }

    private func mangaImageFileURL(bookUrl: String, chapterIndex: Int, imageURL: String) -> URL {
        let ext = URL(string: imageURL)?.pathExtension.isEmpty == false
            ? (URL(string: imageURL)?.pathExtension ?? "img")
            : "img"
        let fileName = md5Hex(imageURL) + "." + ext
        return mangaImageDir(bookUrl: bookUrl, chapterIndex: chapterIndex).appendingPathComponent(fileName)
    }

    func saveMangaImage(bookUrl: String, chapterIndex: Int, imageURL: String, data: Data) {
        let dir = mangaImageDir(bookUrl: bookUrl, chapterIndex: chapterIndex)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = mangaImageFileURL(bookUrl: bookUrl, chapterIndex: chapterIndex, imageURL: imageURL)
        try? data.write(to: file)
    }

    func loadMangaImage(bookUrl: String, chapterIndex: Int, imageURL: String) -> Data? {
        let file = mangaImageFileURL(bookUrl: bookUrl, chapterIndex: chapterIndex, imageURL: imageURL)
        return try? Data(contentsOf: file)
    }

    func isMangaImageCached(bookUrl: String, chapterIndex: Int, imageURL: String) -> Bool {
        let file = mangaImageFileURL(bookUrl: bookUrl, chapterIndex: chapterIndex, imageURL: imageURL)
        return fileManager.fileExists(atPath: file.path)
    }
    
    // MARK: - 章节列表（目录）缓存
    
    func saveChapterList(bookUrl: String, chapters: [BookChapter]) {
        let dir = bookDir(for: bookUrl)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("toc.json")
        if let data = try? JSONEncoder().encode(chapters) {
            try? data.write(to: file)
        }
    }
    
    func loadChapterList(bookUrl: String) -> [BookChapter]? {
        let file = bookDir(for: bookUrl).appendingPathComponent("toc.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([BookChapter].self, from: data)
    }
    
    // MARK: - 缓存管理
    
    func clearCache(for bookUrl: String) {
        let dir = bookDir(for: bookUrl)
        try? fileManager.removeItem(at: dir)
    }
    
    func getCachedChapterCount(for bookUrl: String) -> Int {
        let dir = bookDir(for: bookUrl)
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return 0
        }
        // 过滤出所有以 .raw 结尾的文件，这些代表已缓存的章节
        return contents.filter { $0.pathExtension == "raw" }.count
    }
    
    func getCacheSize(for bookUrl: String) -> Int64 {
        let dir = bookDir(for: bookUrl)
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            totalSize += Int64(resourceValues?.fileSize ?? 0)
        }
        return totalSize
    }
    
    func getAllCachedBookIds() -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil)) ?? []
        return contents.map { $0.lastPathComponent }
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
