import Foundation
import UIKit

final class AuthService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func login(username: String, password: String) async throws -> String {
        let deviceModel = await MainActor.run { UIDevice.current.model }
        let queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "model", value: deviceModel)
        ]
        let url = try client.buildURL(endpoint: "login", queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应类型"])
            }
            if httpResponse.statusCode != 200 {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "服务器错误(状态码: \(httpResponse.statusCode))"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<LoginResponse>.self, from: data)
            if apiResponse.isSuccess, let loginData = apiResponse.data {
                return loginData.accessToken
            } else {
                throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "登录失败"])
            }
        } catch let error as NSError {
            if error.domain == NSURLErrorDomain {
                throw NSError(domain: "APIService", code: error.code, userInfo: [NSLocalizedDescriptionKey: "网络连接失败: \(error.localizedDescription)"])
            }
            throw error
        }
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "oldpassword", value: oldPassword),
            URLQueryItem(name: "password", value: newPassword)
        ]

        let (data, httpResponse) = try await client.requestWithFailback(endpoint: "changepass", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "修改密码失败(状态码: \(httpResponse.statusCode))"])
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "修改密码时发生未知错误"])
        }
    }
}
