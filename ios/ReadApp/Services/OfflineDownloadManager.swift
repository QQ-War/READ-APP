import Foundation
import ZIPFoundation
import UIKit

enum OfflineDownloadStatus: String {
    case downloading
    case paused
    case failed
}

struct OfflineDownloadJob: Identifiable {
    let id: String
    let bookUrl: String
    let bookName: String
    let bookSourceUrl: String?
    let isManga: Bool
    let chapters: [BookChapter]
    let startIndex: Int
    let endIndex: Int
    var status: OfflineDownloadStatus
    var totalUnits: Int
    var completedUnits: Int
    var message: String
    var lastError: String?
    var currentChapterOffset: Int
    var currentImageOffset: Int
}

@MainActor
final class OfflineDownloadManager: ObservableObject {
    static let shared = OfflineDownloadManager()

    @Published private(set) var jobs: [OfflineDownloadJob] = []
    private var taskHandles: [String: Task<Void, Never>] = [:]
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OfflineDownload") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    func startDownload(
        book: Book,
        chapters: [BookChapter],
        start: Int,
        end: Int,
        isManga: Bool
    ) -> String? {
        guard let bookUrl = book.bookUrl else { return nil }
        
        // 开启后台任务支持
        beginBackgroundTask()
        
        if let existing = jobs.first(where: { $0.bookUrl == bookUrl }) {
            if existing.status == .failed || existing.status == .paused {
                resume(jobId: existing.id)
            }
            return existing.id
        }

        let startIdx = max(0, start - 1)
        let endIdx = min(chapters.count - 1, end - 1)
        guard startIdx <= endIdx else { return nil }
        let target = Array(chapters[startIdx...endIdx])
        guard !target.isEmpty else { return nil }

        let jobId = UUID().uuidString
        let job = OfflineDownloadJob(
            id: jobId,
            bookUrl: bookUrl,
            bookName: book.name ?? "Unknown",
            bookSourceUrl: book.origin,
            isManga: isManga,
            chapters: target,
            startIndex: start,
            endIndex: end,
            status: .downloading,
            totalUnits: target.count,
            completedUnits: 0,
            message: "Preparing download...",
            lastError: nil,
            currentChapterOffset: 0,
            currentImageOffset: 0
        )
        jobs.append(job)
        startTask(jobId: jobId)
        return jobId
    }

    func pause(jobId: String) {
        updateJob(jobId) { job in
            if job.status == .downloading {
                job.status = .paused
                job.message = "Paused"
            }
        }
    }

    func resume(jobId: String) {
        updateJob(jobId) { job in
            if job.status == .paused || job.status == .failed {
                job.status = .downloading
                job.lastError = nil
                job.message = "Resuming..."
            }
        }
        startTask(jobId: jobId)
    }

    func cancel(jobId: String) {
        taskHandles[jobId]?.cancel()
        taskHandles[jobId] = nil
        jobs.removeAll { $0.id == jobId }
        
        // 检查是否还有剩余任务，如果没有则关闭后台任务标识
        if taskHandles.isEmpty {
            endBackgroundTask()
        }
    }

    func job(for bookUrl: String) -> OfflineDownloadJob? {
        jobs.first(where: { $0.bookUrl == bookUrl })
    }

    func activeOrFailedJobs() -> [OfflineDownloadJob] {
        jobs.filter { $0.status == .downloading || $0.status == .paused || $0.status == .failed }
    }

    private func startTask(jobId: String) {
        if taskHandles[jobId] != nil { return }
        taskHandles[jobId] = Task { [weak self] in
            await self?.run(jobId: jobId)
        }
    }

    nonisolated private func run(jobId: String) async {
        defer {
            Task { @MainActor in
                self.taskHandles[jobId] = nil
                // 如果没有正在运行的任务了，结束后台任务
                if self.taskHandles.isEmpty {
                    self.endBackgroundTask()
                }
            }
        }

        while true {
            guard let job = await jobSnapshot(jobId: jobId) else { return }
            if job.status == .failed { return }
            if job.status == .paused {
                await waitWhilePaused(jobId: jobId)
                continue
            }

            let chapters = job.chapters
            let currentOffset = job.currentChapterOffset
            guard currentOffset < chapters.count else {
                await MainActor.run { [jobId] in
                    self.jobs.removeAll { $0.id == jobId }
                }
                return
            }

            // 批量准备窗口大小（同时准备元数据的章节数）
            let batchSize = 5 
            let endOffset = min(currentOffset + batchSize, chapters.count)
            let batchChapters = Array(chapters[currentOffset..<endOffset])

            await withTaskGroup(of: Void.self) { group in
                for (index, chapter) in batchChapters.enumerated() {
                    let absolutePos = currentOffset + index
                    group.addTask {
                        do {
                            if !(await self.shouldContinue(jobId: jobId)) { return }
                            
                            // 1. 获取章节元数据（图片列表）
                            let contentType = job.isManga ? 2 : 0
                            let rawContent = try await APIService.shared.fetchChapterContent(
                                bookUrl: job.bookUrl,
                                bookSourceUrl: job.bookSourceUrl,
                                index: chapter.index,
                                contentType: contentType
                            )
                            LocalCacheManager.shared.saveChapter(bookUrl: job.bookUrl, index: chapter.index, content: rawContent)
                            
                            if job.isManga {
                                let imageUrls = extractMangaImageUrls(from: rawContent)
                                await MainActor.run {
                                    self.updateJob(jobId) { job in
                                        job.message = "Enqueuing: \(chapter.title)"
                                    }
                                }
                                
                                // 2. 提交给系统后台下载
                                // 即使此处不 await，系统也会继续下载。但我们 await 是为了保持进度条更新的顺序。
                                _ = try await PackageDownloadManager.shared.downloadPackage(
                                    bookUrl: job.bookUrl,
                                    bookSourceUrl: job.bookSourceUrl,
                                    chapterIndex: chapter.index,
                                    isManga: true,
                                    imageUrls: imageUrls
                                )
                                
                                await MainActor.run {
                                    self.updateJob(jobId) { job in
                                        job.completedUnits += 1
                                        // 只有当这一批都入队了，我们才推进主进度
                                        if absolutePos >= job.currentChapterOffset {
                                            job.currentChapterOffset = absolutePos + 1
                                        }
                                    }
                                }
                            } else {
                                await MainActor.run {
                                    self.updateJob(jobId) { job in
                                        job.completedUnits += 1
                                        if absolutePos >= job.currentChapterOffset {
                                            job.currentChapterOffset = absolutePos + 1
                                        }
                                    }
                                }
                            }
                        } catch {
                            LogManager.shared.log("章节 \(chapter.title) 准备失败: \(error.localizedDescription)", category: "下载")
                        }
                    }
                }
            }
            
            // 稍作停顿，避免请求过快
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func unzipAndSaveImages(zipURL: URL, bookUrl: String, chapterIndex: Int, imageUrls: [String]) async throws {
        // 重要：由于 iOS 不支持通过命令行解压，必须引入 ZIPFoundation。
        // 请确保在工程中添加了 https://github.com/weichsel/ZIPFoundation
        // 并在文件顶部或此处 import ZIPFoundation。
        
        // 我们通过反射或动态检查来模拟调用，或者直接写逻辑。
        // 这里提供完整实现，用户只需要确保库已链接。
        
        let fileManager = FileManager.default
        let extractDir = fileManager.temporaryDirectory.appendingPathComponent("extract_\(UUID().uuidString)")
        
        do {
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
            
            try fileManager.unzipItem(at: zipURL, to: extractDir)
            
            // 如果 unzipItem 被注释了，下面的逻辑会因为找不到文件而跳过。
            // 建议用户在此处补全代码。
            
            // 获取解压后的所有文件并排序，以确保与 imageUrls 顺序一致
            let contents = try fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { $0.lastPathComponent != ".DS_Store" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            if contents.isEmpty {
                // 如果解压失败或目录为空，我们抛出异常以便外层捕捉
                throw NSError(domain: "OfflineDownloadManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "解压失败或压缩包内无有效图片。请确保 ZIPFoundation 已集成并调用了 unzipItem。"])
            }

            for (i, imageUrl) in imageUrls.enumerated() {
                guard i < contents.count else { break }
                let sourceFile = contents[i]
                
                if let data = try? Data(contentsOf: sourceFile) {
                    LocalCacheManager.shared.saveMangaImage(
                        bookUrl: bookUrl,
                        chapterIndex: chapterIndex,
                        imageURL: imageUrl,
                        data: data
                    )
                }
            }
            
            // 清理
            try? fileManager.removeItem(at: extractDir)
            
        } catch {
            print("Extraction & Save error: \(error)")
            throw error
        }
    }

    private func jobSnapshot(jobId: String) async -> OfflineDownloadJob? {
        await MainActor.run {
            self.jobs.first { $0.id == jobId }
        }
    }

    nonisolated private func shouldContinue(jobId: String) async -> Bool {
        if Task.isCancelled { return false }
        while true {
            guard let job = await jobSnapshot(jobId: jobId) else { return false }
            if job.status == .paused {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            if job.status == .failed {
                return false
            }
            return true
        }
    }

    nonisolated private func waitWhilePaused(jobId: String) async {
        while true {
            guard let job = await jobSnapshot(jobId: jobId) else { return }
            if job.status == .paused {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            return
        }
    }

    private func markFailed(jobId: String, message: String) async {
        await MainActor.run {
            self.updateJob(jobId) { job in
                job.status = .failed
                job.lastError = message
                job.message = "Failed: \(message)"
            }
        }
    }

    private func updateJob(_ jobId: String, mutate: (inout OfflineDownloadJob) -> Void) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        var job = jobs[idx]
        mutate(&job)
        jobs[idx] = job
    }
}

private func extractMangaImageUrls(from rawContent: String) -> [String] {
    return MangaImageExtractor.extractImageUrls(from: rawContent)
}

private func mangaDownloadDelay() async {
    let baseDelay = 200_000_000
    let jitter = Int.random(in: 0...200_000_000)
    try? await Task.sleep(nanoseconds: UInt64(baseDelay + jitter))
}
