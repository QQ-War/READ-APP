import Foundation
import UIKit
import CoreText
import UniformTypeIdentifiers

struct ReaderFontOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let fileName: String?
    let isSystem: Bool
}

final class FontManager {
    static let shared = FontManager()

    private let fontsDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        fontsDirectory = (base ?? FileManager.default.temporaryDirectory).appendingPathComponent("ReadAppFonts")
        try? FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
    }

    func registerCachedFonts() {
        let files = (try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            _ = registerFontFile(url)
        }
    }

    func availableFonts() -> [ReaderFontOption] {
        var options: [ReaderFontOption] = [
            ReaderFontOption(id: "", displayName: "系统默认", fileName: nil, isSystem: true)
        ]
        let files = (try? FileManager.default.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            for name in fontNames(from: url) {
                let display = UIFont(name: name, size: 14)?.familyName ?? name
                options.append(ReaderFontOption(id: name, displayName: display, fileName: url.lastPathComponent, isSystem: false))
            }
        }
        return options
    }

    func importFont(from url: URL) -> ReaderFontOption? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard let ext = url.pathExtension.lowercased() as String?,
              ["ttf", "otf"].contains(ext) else { return nil }
        let target = fontsDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: url, to: target)
            guard registerFontFile(target) else { return nil }
            guard let name = fontNames(from: target).first else { return nil }
            let display = UIFont(name: name, size: 14)?.familyName ?? name
            return ReaderFontOption(id: name, displayName: display, fileName: target.lastPathComponent, isSystem: false)
        } catch {
            return nil
        }
    }

    private func registerFontFile(_ url: URL) -> Bool {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private func fontNames(from url: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return [] }
        return descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
    }
}
