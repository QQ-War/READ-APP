import Foundation

final class BookSourceService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchBookSources() async throws -> [BookSource] {
        switch client.backend {
        case .read:
            let pageInfo = try await fetchBookSourcePageInfo()
            if pageInfo.page <= 0 || pageInfo.md5.isEmpty {
                return []
            }

            var allSources: [BookSource] = []
            for page in 1...pageInfo.page {
                let (data, httpResponse) = try await client.requestWithFailback(
                    endpoint: ApiEndpoints.getBookSources,
                    queryItems: [
                        URLQueryItem(name: "accessToken", value: client.accessToken),
                        URLQueryItem(name: "md5", value: pageInfo.md5),
                        URLQueryItem(name: "page", value: "\(page)")
                    ]
                )
                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源失败"])
                }
                let apiResponse = try JSONDecoder().decode(APIResponse<[BookSource]>.self, from: data)
                if apiResponse.isSuccess, let sources = apiResponse.data {
                    allSources.append(contentsOf: sources)
                } else {
                    throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析书源失败"])
                }
            }
            return allSources
        case .reader:
            let (data, httpResponse) = try await client.requestWithFailback(
                endpoint: ApiEndpointsReader.getBookSources,
                queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)]
            )
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[BookSource]>.self, from: data)
            if apiResponse.isSuccess, let sources = apiResponse.data {
                return sources
            }
            return []
        }
    }

    func saveBookSource(jsonContent: String) async throws {
        let isReader = client.backend == .reader
        let isArray = jsonContent.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
        let endpoint: String
        if isReader {
            endpoint = isArray ? ApiEndpointsReader.saveBookSources : ApiEndpointsReader.saveBookSource
        } else {
            endpoint = ApiEndpoints.saveBookSource
        }
        let url = try client.buildURL(endpoint: endpoint, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let contentType = isReader ? "application/json; charset=utf-8" : "text/plain; charset=utf-8"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonContent.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存书源失败"])
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存书源时发生未知错误"])
        }
    }

    func deleteBookSource(id: String) async throws {
        switch client.backend {
        case .read:
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "id", value: id)
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.deleteBookSource, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除书源失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除书源时发生未知错误"])
            }
        case .reader:
            let url = try client.buildURL(endpoint: ApiEndpointsReader.deleteBookSource, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let payload = ["bookSourceUrl": id]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "删除书源失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除书源时发生未知错误"])
            }
        }
    }

    func toggleBookSource(id: String, isEnabled: Bool) async throws {
        switch client.backend {
        case .read:
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "st", value: isEnabled ? "1" : "0")
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.toggleBookSource, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "切换书源状态失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "切换书源状态时发生未知错误"])
            }
        case .reader:
            var bookSourceJson = try await fetchBookSourceJson(bookSourceUrl: id)
            bookSourceJson["enabled"] = isEnabled
            let data = try JSONSerialization.data(withJSONObject: bookSourceJson, options: [])
            let url = try client.buildURL(endpoint: ApiEndpointsReader.saveBookSource, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "切换书源状态失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: responseData)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "切换书源状态时发生未知错误"])
            }
        }
    }

    func getBookSourceDetail(id: String) async throws -> String {
        switch client.backend {
        case .read:
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "id", value: id)
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.getBookSourceDetail, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源详情失败"])
            }

            struct BookSourceDetailResponse: Codable {
                let json: String?
            }

            let apiResponse = try JSONDecoder().decode(APIResponse<BookSourceDetailResponse>.self, from: data)
            if apiResponse.isSuccess, let detail = apiResponse.data, let json = detail.json {
                return json
            } else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取书源详情内容失败"])
            }
        case .reader:
            let detail = try await fetchBookSourceJson(bookSourceUrl: id)
            let data = try JSONSerialization.data(withJSONObject: detail, options: [])
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func fetchBookSourcePageInfo() async throws -> BookSourcePageInfo {
        let (data, httpResponse) = try await client.requestWithFailback(
            endpoint: ApiEndpoints.getBookSourcesPage,
            queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)]
        )
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源页信息失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<BookSourcePageInfo>.self, from: data)
        if apiResponse.isSuccess, let info = apiResponse.data {
            return info
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析书源页信息失败"])
        }
    }

    private func fetchBookSourceJson(bookSourceUrl: String) async throws -> [String: Any] {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl)
        ]
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpointsReader.getBookSource, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源详情失败"])
        }
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let responseDict = jsonObject as? [String: Any] else {
            return [:]
        }
        let isSuccess = responseDict["isSuccess"] as? Bool ?? false
        if !isSuccess {
            let errorMsg = responseDict["errorMsg"] as? String
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "获取书源详情失败"])
        }
        return responseDict["data"] as? [String: Any] ?? [:]
    }
}
