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
        let inputData = Data(bookUrl.utf8)
        let hashed = Insecure.MD5.hash(data: inputData)
        let hashString = hashed.map { String(format: "%02hhx", $0) }.joined()
        return baseDir.appendingPathComponent(hashString)
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
    
    func getCachedChapterCount(for bookUrl: String, totalChapters: Int) -> Int {
        var count = 0
        for i in 0..<totalChapters {
            if isChapterCached(bookUrl: bookUrl, index: i) {
                count += 1
            }
        }
        return count
    }
}
