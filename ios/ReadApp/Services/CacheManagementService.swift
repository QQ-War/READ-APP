import Foundation

final class CacheManagementService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func clearAllRemoteCache() async throws {
        guard !client.accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken)
        ]
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.clearAllRemoteCache, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "清除远程缓存失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "清除远程缓存时发生未知错误"])
        }
    }
}
