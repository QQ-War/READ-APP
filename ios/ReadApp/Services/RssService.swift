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
}
