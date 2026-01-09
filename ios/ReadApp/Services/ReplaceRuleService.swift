import Foundation

final class ReplaceRuleService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchReplaceRules() async throws -> [ReplaceRule] {
        switch client.backend {
        case .read:
            let pageInfo = try await fetchReplaceRulePageInfo()
            if pageInfo.page <= 0 || pageInfo.md5.isEmpty {
                return []
            }

            var allRules: [ReplaceRule] = []
            for page in 1...pageInfo.page {
                let (data, httpResponse) = try await client.requestWithFailback(
                    endpoint: ApiEndpoints.getReplaceRules,
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
        case .reader:
            let (data, httpResponse) = try await client.requestWithFailback(
                endpoint: ApiEndpointsReader.getReplaceRules,
                queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)]
            )
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取净化规则失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[ReplaceRule]>.self, from: data)
            if apiResponse.isSuccess, let rules = apiResponse.data {
                return rules
            }
            return []
        }
    }

    func saveReplaceRule(rule: ReplaceRule) async throws {
        let endpoint = client.backend == .reader ? ApiEndpointsReader.saveReplaceRule : ApiEndpoints.addReplaceRule
        let url = try client.buildURL(endpoint: endpoint, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])

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

    func deleteReplaceRule(rule: ReplaceRule) async throws {
        switch client.backend {
        case .read:
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "id", value: rule.id ?? "")
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.deleteReplaceRule, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除规则失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除规则时发生未知错误"])
            }
        case .reader:
            let url = try client.buildURL(endpoint: ApiEndpointsReader.deleteReplaceRule, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(rule)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "删除规则失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除规则时发生未知错误"])
            }
        }
    }

    func toggleReplaceRule(rule: ReplaceRule, isEnabled: Bool) async throws {
        switch client.backend {
        case .read:
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "id", value: rule.id ?? ""),
                URLQueryItem(name: "st", value: isEnabled ? "1" : "0")
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.toggleReplaceRule, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "切换规则状态失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "切换规则状态时发生未知错误"])
            }
        case .reader:
            let updatedRule = ReplaceRule(
                id: rule.id,
                name: rule.name,
                groupname: rule.groupname,
                pattern: rule.pattern,
                replacement: rule.replacement,
                scope: rule.scope,
                scopeTitle: rule.scopeTitle,
                scopeContent: rule.scopeContent,
                excludeScope: rule.excludeScope,
                isEnabled: isEnabled,
                isRegex: rule.isRegex,
                timeoutMillisecond: rule.timeoutMillisecond,
                ruleorder: rule.ruleorder
            )
            try await saveReplaceRule(rule: updatedRule)
        }
    }

    func saveReplaceRules(jsonContent: String) async throws {
        let endpoint = client.backend == .reader ? ApiEndpointsReader.saveReplaceRules : ApiEndpoints.saveReplaceRules
        let url = try client.buildURL(endpoint: endpoint, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let contentType = client.backend == .reader ? "application/json; charset=utf-8" : "text/plain; charset=utf-8"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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
            endpoint: ApiEndpoints.getReplaceRulesPage,
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
