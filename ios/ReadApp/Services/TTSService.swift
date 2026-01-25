import Foundation

final class TTSService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchTTSList() async throws -> [HttpTTS] {
        if client.backend == .reader {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "v", value: "\(timestamp)")
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpointsReader.httpTtsList, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[HttpTTS]>.self, from: data)
            if apiResponse.isSuccess, let ttsList = apiResponse.data {
                return ttsList
            }
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取TTS引擎列表失败"])
        }
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.getAllTts, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<[HttpTTS]>.self, from: data)
        if apiResponse.isSuccess, let ttsList = apiResponse.data {
            return ttsList
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取TTS引擎列表失败"])
        }
    }

    func buildTTSAudioURL(ttsId: String, text: String, speechRate: Double) -> URL? {
        if client.backend == .reader {
            return nil
        }
        guard var components = URLComponents(string: "\(client.baseURL)/tts") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "id", value: ttsId),
            URLQueryItem(name: "speakText", value: text),
            URLQueryItem(name: "speechRate", value: "\(speechRate)")
        ]
        return components.url
    }

    func saveTTS(tts: HttpTTS) async throws {
        if client.backend == .reader {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "v", value: "\(timestamp)")
            ]
            let url = try client.buildURL(endpoint: ApiEndpointsReader.httpTtsSave, queryItems: queryItems)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(tts)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存TTS失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存TTS时发生未知错误"])
            }
            return
        }
        let url = try client.buildURL(endpoint: ApiEndpoints.addTts, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(tts)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存TTS失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存TTS时发生未知错误"])
        }
    }

    func deleteTTS(id: String) async throws {
        if client.backend == .reader {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "v", value: "\(timestamp)")
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpointsReader.httpTtsDelete, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除TTS失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除TTS时发生未知错误"])
            }
            return
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "id", value: id)
        ]
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.deleteTts, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除TTS失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除TTS时发生未知错误"])
        }
    }

    func saveTTSBatch(jsonContent: String) async throws {
        if client.backend == .reader {
            guard let data = jsonContent.data(using: .utf8) else {
                throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "导入内容为空"])
            }
            if let list = try? JSONDecoder().decode([HttpTTS].self, from: data) {
                for item in list {
                    try await saveTTS(tts: item)
                }
                return
            }
            if let single = try? JSONDecoder().decode(HttpTTS.self, from: data) {
                try await saveTTS(tts: single)
                return
            }
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "导入内容格式错误"])
        }
        let url = try client.buildURL(endpoint: ApiEndpoints.saveTtsBatch, queryItems: [URLQueryItem(name: "accessToken", value: client.accessToken)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonContent.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "批量保存TTS失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存TTS时发生未知错误"])
        }
    }

    func fetchDefaultTTS() async throws -> String {
        if client.backend == .reader {
            let list = try await fetchTTSList()
            return list.first?.id ?? ""
        }
        guard !client.accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken)
        ]
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.getDefaultTts, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取默认TTS失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if apiResponse.isSuccess, let defaultTTSId = apiResponse.data {
            return defaultTTSId
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取默认TTS时发生未知错误"])
        }
    }
}
