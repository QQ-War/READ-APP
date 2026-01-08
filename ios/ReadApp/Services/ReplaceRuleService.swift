import Foundation

final class ReplaceRuleService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchReplaceRules() async throws -> [ReplaceRule] {
        let pageInfo = try await fetchReplaceRulePageInfo()
        if pageInfo.page <= 0 || pageInfo.md5.isEmpty {
            return []
        }

        var allRules: [ReplaceRule] = []
        for page in 1...pageInfo.page {
            let (data, httpResponse) = try await client.requestWithFailback(
                endpoint: "getReplaceRulesNew",
                queryItems: [
                    URLQueryItem(name: "accessToken", value: client.accessToken),
                    URLQueryItem(name: "md5", value: pageInfo.md5),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取净化规则失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[ReplaceRule]>.self, from: data)
            if apiResponse.isSuccess, let rules = apiResponse.data {
                allRules.append(contentsOf: rules)
            } else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析净化规则失败"])
            }
        }
        return allRules
    }

    func saveReplaceRule(rule: ReplaceRule) async throws {
        let url = try client.buildURL(endpoint: "addReplaceRule", queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(rule)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存规则失败"])
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存规则时发生未知错误"])
        }
    }

    func deleteReplaceRule(id: String) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "id", value: id)
        ]
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: "delReplaceRule", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除规则失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除规则时发生未知错误"])
        }
    }

    func toggleReplaceRule(id: String, isEnabled: Bool) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "st", value: isEnabled ? "1" : "0")
        ]
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: "stopReplaceRules", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "切换规则状态失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "切换规则状态时发生未知错误"])
        }
    }

    func saveReplaceRules(jsonContent: String) async throws {
        let url = try client.buildURL(endpoint: "saverules", queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonContent.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存规则失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存规则时发生未知错误"])
        }
    }

    private func fetchReplaceRulePageInfo() async throws -> ReplaceRulePageInfo {
        let (data, httpResponse) = try await client.requestWithFailback(
            endpoint: "getReplaceRulesPage",
            queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)]
        )
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取净化规则页信息失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<ReplaceRulePageInfo>.self, from: data)
        if apiResponse.isSuccess, let info = apiResponse.data {
            return info
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析净化规则页信息失败"])
        }
    }
}
