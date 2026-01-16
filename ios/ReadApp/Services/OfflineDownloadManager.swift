import Foundation

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

    private init() {}

    func startDownload(
        book: Book,
        chapters: [BookChapter],
        start: Int,
        end: Int,
        isManga: Bool
    ) -> String? {
        guard let bookUrl = book.bookUrl else { return nil }
        if let existing = jobs.first(where: { $0.bookUrl == bookUrl }) {
            if existing.status == .failed || existing.status == .paused {
                resume(jobId: existing.id)
            }
            return existing.id
        }

        let target = chapters.filter { $0.index >= (start - 1) && $0.index <= (end - 1) }
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
            }
        }

        while true {
            guard let job = await jobSnapshot(jobId: jobId) else { return }
            if job.status == .failed {
                return
            }
            if job.status == .paused {
                await waitWhilePaused(jobId: jobId)
                continue
            }

            let chapters = job.chapters
            guard job.currentChapterOffset < chapters.count else {
                await MainActor.run { [jobId] in
                    self.jobs.removeAll { $0.id == jobId }
                }
                return
            }

            for chapterPos in job.currentChapterOffset..<chapters.count {
                let chapter = chapters[chapterPos]
                if !(await shouldContinue(jobId: jobId)) { return }

                await MainActor.run {
                    self.updateJob(jobId) { job in
                        job.message = "Downloading: \(chapter.title) (\(chapterPos + 1)/\(chapters.count))"
                        job.currentChapterOffset = chapterPos
                    }
                }

                do {
                    let contentType = job.isManga ? 2 : 0
                    let rawContent = try await APIService.shared.fetchChapterContent(
                        bookUrl: job.bookUrl,
                        bookSourceUrl: job.bookSourceUrl,
                        index: chapter.index,
                        contentType: contentType
                    )

                    await MainActor.run {
                        self.updateJob(jobId) { job in
                            job.completedUnits += 1
                        }
                    }

                    if job.isManga {
                        let imageUrls = extractMangaImageUrls(from: rawContent)
                        if !imageUrls.isEmpty {
                            await MainActor.run {
                                self.updateJob(jobId) { job in
                                    job.totalUnits += imageUrls.count
                                }
                            }
                        }

                        let snapshot = await jobSnapshot(jobId: jobId)
                        let startImage = (snapshot?.currentChapterOffset == chapterPos) ? (snapshot?.currentImageOffset ?? 0) : 0
                        for imagePos in startImage..<imageUrls.count {
                            if !(await shouldContinue(jobId: jobId)) { return }
                            let rawUrl = imageUrls[imagePos]
                            await MainActor.run {
                                self.updateJob(jobId) { job in
                                    job.currentImageOffset = imagePos
                                    job.message = "Caching images: \(chapter.title) (\(imagePos + 1)/\(imageUrls.count))"
                                }
                            }

                            guard let resolved = MangaImageService.shared.resolveImageURL(rawUrl) else { continue }
                            let absolute = resolved.absoluteString
                            if LocalCacheManager.shared.isMangaImageCached(bookUrl: job.bookUrl, chapterIndex: chapter.index, imageURL: absolute) {
                                await MainActor.run {
                                    self.updateJob(jobId) { job in
                                        job.completedUnits += 1
                                    }
                                }
                                await mangaDownloadDelay()
                                continue
                            }

                            if let data = await MangaImageService.shared.fetchImageData(for: resolved, referer: chapter.url) {
                                LocalCacheManager.shared.saveMangaImage(
                                    bookUrl: job.bookUrl,
                                    chapterIndex: chapter.index,
                                    imageURL: absolute,
                                    data: data
                                )
                                await MainActor.run {
                                    self.updateJob(jobId) { job in
                                        job.completedUnits += 1
                                    }
                                }
                                await mangaDownloadDelay()
                            } else {
                                await markFailed(jobId: jobId, message: "Image download failed")
                                return
                            }
                        }
                    }

                    await MainActor.run {
                        self.updateJob(jobId) { job in
                            job.currentChapterOffset = chapterPos + 1
                            job.currentImageOffset = 0
                        }
                    }
                } catch {
                    await markFailed(jobId: jobId, message: error.localizedDescription)
                    return
                }
            }
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
