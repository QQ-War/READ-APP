import Foundation
import UIKit
import CryptoKit

final class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let cacheDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        cacheDirectory = (base ?? FileManager.default.temporaryDirectory).appendingPathComponent("readapp-image-cache")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let diskURL = cachedFileURL(for: url)
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: key)
            return image
        }

        // 统一使用 MangaImageService 获取数据，它内部已处理 Referer、UA、代理及 /pdfImage 逻辑
        await MangaImageService.shared.acquireDownloadPermit()
        defer { MangaImageService.shared.releaseDownloadPermit() }
        guard let data = await MangaImageService.shared.fetchImageData(for: url, referer: nil),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key)
        try? data.write(to: diskURL, options: [.atomic])
        return image
    }

    private func cachedFileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(name)
    }
}
