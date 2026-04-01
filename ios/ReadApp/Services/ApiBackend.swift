import Foundation

enum ApiBackend: String, CaseIterable, Identifiable {
    case read
    case reader

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .read:
            return "轻阅读"
        case .reader:
            return "阅读3"
        }
    }
}

struct ApiBackendResolver {
    static func detect(from serverURL: String) -> ApiBackend {
        let normalized = serverURL.lowercased()
        if normalized.contains("/reader3") {
            return .reader
        }
        if normalized.contains("/api/") {
            return .read
        }
        return .read
    }

    static func normalizeBaseURL(_ serverURL: String, backend: ApiBackend, apiVersion: Int) -> String {
        var trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        switch backend {
        case .reader:
            if trimmed.contains("/reader3") {
                return trimmed
            }
            return "\(trimmed)/reader3"
        case .read:
            if trimmed.contains("/api/") {
                return trimmed
            }
            return "\(trimmed)/api/\(apiVersion)"
        }
    }

    static func stripApiBasePath(_ baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if let range = trimmed.range(of: "/api/\\d+$", options: .regularExpression) {
            trimmed.removeSubrange(range)
        } else if trimmed.hasSuffix("/reader3") {
            trimmed.removeLast("/reader3".count)
        }
        return trimmed
    }
}
