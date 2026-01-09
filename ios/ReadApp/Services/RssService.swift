import Foundation

final class RssService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchRssSources() async throws -> RssSourcesResponse {
        let endpoint = client.backend == .read ? ApiEndpoints.getRssSources : ApiEndpointsReader.getRssSources
        let queryItems = [URLQueryItem(name: "accessToken", value: client.accessToken)]

        let (data, response) = try await client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)
        guard response.statusCode == 200 else {
            throw NSError(domain: "RssService", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "加载订阅源失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<RssSourcesResponse>.self, from: data)
        if apiResponse.isSuccess, let payload = apiResponse.data {
            return payload
        }
        throw NSError(domain: "RssService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取订阅源失败"])
    }

    func toggleSource(id: String, isEnabled: Bool) async throws {
        let endpoint = client.backend == .read ? ApiEndpoints.stopRssSource : ApiEndpointsReader.stopRssSource
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "st", value: isEnabled ? "1" : "0")
        ]

        let (data, response) = try await client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)
        guard response.statusCode == 200 else {
            throw NSError(domain: "RssService", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "切换订阅源状态失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "RssService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "切换订阅源失败"])
        }
    }

    var supportsRemoteEditing: Bool {
        return client.backend == .read
    }

    func saveRemoteSource(_ source: RssSource, id: String? = nil) async throws {
        guard supportsRemoteEditing else {
            throw NSError(domain: "RssService", code: 400, userInfo: [NSLocalizedDescriptionKey: "当前后端不支持远程编辑"])
        }
        let endpoint = ApiEndpoints.editRssSources
        let url = try client.buildURL(endpoint: endpoint, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let payload = RssEditPayload(json: try encodeRssSource(source), id: id)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "RssService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存订阅源失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "RssService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存订阅源失败"])
        }
    }

    func deleteRemoteSource(id: String) async throws {
        guard supportsRemoteEditing else {
            throw NSError(domain: "RssService", code: 400, userInfo: [NSLocalizedDescriptionKey: "当前后端不支持远程编辑"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "id", value: id)
        ]
        let (data, response) = try await client.requestWithFailback(endpoint: ApiEndpoints.deleteRssSource, queryItems: queryItems)
        guard response.statusCode == 200 else {
            throw NSError(domain: "RssService", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除订阅源失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "RssService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除订阅源失败"])
        }
    }

    private func encodeRssSource(_ source: RssSource) throws -> String {
        let data = try JSONEncoder().encode(source)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "RssService", code: 500, userInfo: [NSLocalizedDescriptionKey: "订阅源内容无法编码"])
        }
        return json
    }
}

private struct RssEditPayload: Codable {
    let json: String
    let id: String?
}
