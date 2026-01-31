import Foundation
import UIKit

@MainActor
final class PackageDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = PackageDownloadManager()
    
    private var session: URLSession!
    
    struct TaskMetadata: Codable {
        let bookUrl: String
        let bookSourceUrl: String?
        let chapterIndex: Int
        let imageUrls: [String]
        let isManga: Bool
    }
    
    // 内存中的任务映射，用于快速访问
    private var downloadTasks: [Int: TaskMetadata] = [:]
    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    
    @Published var activeDownloads: Set<String> = [] // "bookUrl_chapterIndex"
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]
    private var pendingContinuations: [String: [CheckedContinuation<URL, Error>]] = [:]
    
    private let metadataFolder = FileManager.default.temporaryDirectory.appendingPathComponent("download_metadata")
    
    private override init() {
        super.init()
        try? FileManager.default.createDirectory(at: metadataFolder, withIntermediateDirectories: true)
        
        let config = URLSessionConfiguration.background(withIdentifier: "com.readapp.packagedownload.v1")
        config.sessionSendsLaunchEvents = true
        // 允许系统根据电量和网络自动调度
        config.isDiscretionary = false 
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // 恢复之前可能挂起的任务元数据
        recoverMetadata()
    }
    
    private func saveMetadata(_ metadata: TaskMetadata, for taskId: Int) {
        let fileURL = metadataFolder.appendingPathComponent("\(taskId).json")
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: fileURL)
        }
        downloadTasks[taskId] = metadata
    }
    
    private func removeMetadata(for taskId: Int) {
        let fileURL = metadataFolder.appendingPathComponent("\(taskId).json")
        try? FileManager.default.removeItem(at: fileURL)
        downloadTasks.removeValue(forKey: taskId)
    }
    
    private func recoverMetadata() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: metadataFolder, includingPropertiesForKeys: nil) else { return }
        for fileURL in contents where fileURL.pathExtension == "json" {
            if let taskId = Int(fileURL.deletingPathExtension().lastPathComponent),
               let data = try? Data(contentsOf: fileURL),
               let metadata = try? JSONDecoder().decode(TaskMetadata.self, from: data) {
                downloadTasks[taskId] = metadata
                activeDownloads.insert("\(metadata.bookUrl)_\(metadata.chapterIndex)")
            }
        }
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
        backgroundCompletionHandlers[identifier] = handler
    }
    
    func downloadPackage(bookUrl: String, bookSourceUrl: String?, chapterIndex: Int, isManga: Bool, imageUrls: [String] = []) async throws -> URL {
        let key = "\(bookUrl)_\(chapterIndex)"
        
        if activeDownloads.contains(key) {
            return try await withCheckedThrowingContinuation { continuation in
                var list = pendingContinuations[key] ?? []
                list.append(continuation)
                pendingContinuations[key] = list
            }
        }
        
        activeDownloads.insert(key)
        
        var queryItems = [
            URLQueryItem(name: "accessToken", value: UserPreferences.shared.accessToken),
            URLQueryItem(name: "url", value: bookUrl),
            URLQueryItem(name: "index", value: "\(chapterIndex)"),
            URLQueryItem(name: "type", value: isManga ? "2" : "0")
        ]
        if let bookSourceUrl = bookSourceUrl {
            queryItems.append(URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl))
        }
        
        let baseURL = APIService.shared.baseURL
        var components = URLComponents(string: "\(baseURL)/\(ApiEndpoints.getChapterPackage)")
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            activeDownloads.remove(key)
            throw NSError(domain: "PackageDownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let task = session.downloadTask(with: url)
        let taskId = task.taskIdentifier
        
        let metadata = TaskMetadata(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl, chapterIndex: chapterIndex, imageUrls: imageUrls, isManga: isManga)
        saveMetadata(metadata, for: taskId)
        
        return try await withCheckedThrowingContinuation { continuation in
            continuations[taskId] = continuation
            task.resume()
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier
        guard let metadata = downloadTasks[taskId] else { return }
        let key = "\(metadata.bookUrl)_\(metadata.chapterIndex)"
        
        let fileManager = FileManager.default
        let tempZipURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        
        do {
            if fileManager.fileExists(atPath: tempZipURL.path) {
                try fileManager.removeItem(at: tempZipURL)
            }
            try fileManager.moveItem(at: location, to: tempZipURL)
            
            // 如果提供了图片列表，直接在这里处理解压，这样即使 OfflineDownloadManager 不在运行也能保存成功
            if !metadata.imageUrls.isEmpty && metadata.isManga {
                Task {
                    // 这里引用了之前在 OfflineDownloadManager 里的逻辑，但我们让它在后台静默运行
                    await self.processExtractedImages(zipURL: tempZipURL, metadata: metadata)
                    try? fileManager.removeItem(at: tempZipURL)
                }
            }
            
            completeTask(taskId: taskId, result: .success(tempZipURL))
        } catch {
            completeTask(taskId: taskId, result: .failure(error))
        }
    }

    private func processExtractedImages(zipURL: URL, metadata: TaskMetadata) async {
        let fileManager = FileManager.default
        let extractDir = fileManager.temporaryDirectory.appendingPathComponent("bg_extract_\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: zipURL, to: extractDir)
            let contents = try fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { $0.lastPathComponent != ".DS_Store" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            for (i, imageUrl) in metadata.imageUrls.enumerated() {
                guard i < contents.count else { break }
                if let data = try? Data(contentsOf: contents[i]) {
                    LocalCacheManager.shared.saveMangaImage(bookUrl: metadata.bookUrl, chapterIndex: metadata.chapterIndex, imageURL: imageUrl, data: data)
                }
            }
            try? fileManager.removeItem(at: extractDir)
            LogManager.shared.log("后台任务自动解压完成: \(metadata.bookUrl) 章节 \(metadata.chapterIndex)", category: "下载")
        } catch {
            LogManager.shared.log("后台解压失败: \(error.localizedDescription)", category: "下载")
        }
    }

    private func completeTask(taskId: Int, result: Result<URL, Error>) {
        Task { @MainActor in
            guard let metadata = downloadTasks[taskId] else { return }
            let key = "\(metadata.bookUrl)_\(metadata.chapterIndex)"
            
            activeDownloads.remove(key)
            removeMetadata(for: taskId)
            
            if let continuation = continuations.removeValue(forKey: taskId) {
                switch result {
                case .success(let url): continuation.resume(returning: url)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            
            if let waiters = pendingContinuations.removeValue(forKey: key) {
                for waiter in waiters {
                    switch result {
                    case .success(let url): waiter.resume(returning: url)
                    case .failure(let error): waiter.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let taskId = task.taskIdentifier
            completeTask(taskId: taskId, result: .failure(error))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            guard let identifier = session.configuration.identifier,
                  let handler = backgroundCompletionHandlers.removeValue(forKey: identifier) else {
                return
            }
            handler()
        }
    }
}
