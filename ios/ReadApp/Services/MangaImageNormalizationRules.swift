import Foundation

struct MangaImageHostRewrite {
    let fromSuffix: String
    let toSuffix: String
}

enum MangaImageNormalizationRules {
    static let hostRewrites: [MangaImageHostRewrite] = [
        MangaImageHostRewrite(fromSuffix: "bzmh.net", toSuffix: "bzcdn.net")
    ]

    static let preferSignedHosts: [String] = [
        "kkmh.com"
    ]
}
