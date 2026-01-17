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
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: key)
            try? data.write(to: diskURL, options: [.atomic])
            return image
        } catch {
            return nil
        }
    }

    private func cachedFileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(name)
    }
}
