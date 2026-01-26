import Foundation

final class BookUploadService: NSObject {
    static let shared = BookUploadService()

    private let sessionIdentifier = "com.readapp.bookupload"
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let queue = DispatchQueue(label: "com.readapp.bookupload")
    private var continuations: [Int: CheckedContinuation<(Data, HTTPURLResponse), Error>] = [:]
    private var responseData: [Int: Data] = [:]
    private var tempFiles: [Int: URL] = [:]
    private var backgroundCompletion: (() -> Void)?

    private override init() {
        super.init()
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        queue.async { [weak self] in
            self?.backgroundCompletion = handler
        }
    }

    func uploadBook(fileURL: URL, serverURL: URL) async throws -> (Data, HTTPURLResponse) {
        let boundary = "Boundary-\(UUID().uuidString)"
        let tempFile = try buildMultipartFile(fileURL: fileURL, boundary: boundary)

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let task = session.uploadTask(with: request, fromFile: tempFile)

        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.tempFiles[task.taskIdentifier] = tempFile
                self.continuations[task.taskIdentifier] = cont
                task.resume()
            }
        }
    }

    private func buildMultipartFile(fileURL: URL, boundary: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("upload-\(UUID().uuidString).tmp")

        FileManager.default.createFile(atPath: tempFile.path, contents: nil)
        let writer = try FileHandle(forWritingTo: tempFile)
        defer { try? writer.close() }

        let fileName = fileURL.lastPathComponent
        let header = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n" +
            "Content-Type: application/octet-stream\r\n\r\n"
        try writer.write(contentsOf: Data(header.utf8))

        let reader = try FileHandle(forReadingFrom: fileURL)
        defer { try? reader.close() }
        while autoreleasepool(invoking: {
            if let chunk = try? reader.read(upToCount: 1024 * 1024), let chunk, !chunk.isEmpty {
                try? writer.write(contentsOf: chunk)
                return true
            }
            return false
        }) { }

        let tail = "\r\n--\(boundary)--\r\n"
        try writer.write(contentsOf: Data(tail.utf8))
        return tempFile
    }
}

extension BookUploadService: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async {
            let existing = self.responseData[dataTask.taskIdentifier] ?? Data()
            var combined = existing
            combined.append(data)
            self.responseData[dataTask.taskIdentifier] = combined
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async {
            defer {
                if let temp = self.tempFiles.removeValue(forKey: task.taskIdentifier) {
                    try? FileManager.default.removeItem(at: temp)
                }
                self.responseData.removeValue(forKey: task.taskIdentifier)
            }

            if let error = error {
                self.continuations.removeValue(forKey: task.taskIdentifier)?.resume(throwing: error)
                return
            }

            guard let httpResponse = task.response as? HTTPURLResponse else {
                self.continuations.removeValue(forKey: task.taskIdentifier)?.resume(throwing: NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应类型"]))
                return
            }

            let data = self.responseData[task.taskIdentifier] ?? Data()
            self.continuations.removeValue(forKey: task.taskIdentifier)?.resume(returning: (data, httpResponse))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        queue.async {
            let handler = self.backgroundCompletion
            self.backgroundCompletion = nil
            DispatchQueue.main.async { handler?() }
        }
    }
}
