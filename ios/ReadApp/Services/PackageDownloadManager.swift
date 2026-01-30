import Foundation
import UIKit

@MainActor
final class PackageDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = PackageDownloadManager()
    
    private var session: URLSession!
    private var downloadTasks: [Int: (bookUrl: String, chapterIndex: Int)] = [:]
    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    
    @Published var activeDownloads: Set<String> = [] // "bookUrl_chapterIndex"
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]
    private var pendingContinuations: [String: [CheckedContinuation<URL, Error>]] = [:]
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.readapp.packagedownload.v1")
        config.sessionSendsLaunchEvents = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
        backgroundCompletionHandlers[identifier] = handler
    }
    
    func downloadPackage(bookUrl: String, bookSourceUrl: String?, chapterIndex: Int, isManga: Bool) async throws -> URL {
        let key = "\(bookUrl)_\(chapterIndex)"
        
        // 1. 复用逻辑：如果已经有任务在跑，把 continuation 加入队列等待
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
        downloadTasks[taskId] = (bookUrl, chapterIndex)
        
        return try await withCheckedThrowingContinuation { continuation in
            continuations[taskId] = continuation
            task.resume()
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier
        guard let info = downloadTasks[taskId] else { return }
        let key = "\(info.bookUrl)_\(info.chapterIndex)"
        
        // Move file to a permanent location
        let fileManager = FileManager.default
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        
        var finalResult: Result<URL, Error>
        do {
            if fileManager.fileExists(atPath: tempURL.path) {
                try fileManager.removeItem(at: tempURL)
            }
            try fileManager.moveItem(at: location, to: tempURL)
            finalResult = .success(tempURL)
        } catch {
            finalResult = .failure(error)
        }
            
        Task { @MainActor in
            activeDownloads.remove(key)
            
            // 恢复主 continuation
            if let continuation = continuations.removeValue(forKey: taskId) {
                switch finalResult {
                case .success(let url): continuation.resume(returning: url)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            
            // 恢复所有等待中的挂起者
            if let waiters = pendingContinuations.removeValue(forKey: key) {
                for waiter in waiters {
                    switch finalResult {
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
            Task { @MainActor in
                if let info = downloadTasks[taskId] {
                    activeDownloads.remove("\(info.bookUrl)_\(info.chapterIndex)")
                }
                if let continuation = continuations.removeValue(forKey: taskId) {
                    continuation.resume(throwing: error)
                }
            }
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
