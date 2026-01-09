import Foundation

struct RssSourcesResponse: Codable {
    let sources: [RssSource]
    let can: Bool
}

struct RssSource: Identifiable, Codable {
    var id: String { sourceUrl }

    let sourceUrl: String
    let sourceName: String?
    let sourceIcon: String?
    let sourceGroup: String?
    let loginUrl: String?
    let loginUi: String?
    let variableComment: String?
    var enabled: Bool
}
