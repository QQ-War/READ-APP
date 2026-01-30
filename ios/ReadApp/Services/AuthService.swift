import Foundation
import UIKit

final class AuthService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func login(username: String, password: String) async throws -> String {
        let request: URLRequest
        switch client.backend {
        case .read:
            let deviceModel = await MainActor.run { UIDevice.current.model }
            let url = try client.buildURL(endpoint: ApiEndpoints.login)
            var newRequest = URLRequest(url: url)
            newRequest.httpMethod = "POST"
            newRequest.timeoutInterval = 15
            newRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            let apiVersion = APIService.apiVersion
            let bodyString = "username=\(username)&password=\(password)&model=\(deviceModel)&v=\(apiVersion)"
            newRequest.httpBody = bodyString.data(using: .utf8)
            request = newRequest
        case .reader:
            let url = try client.buildURL(endpoint: ApiEndpointsReader.login)
            var newRequest = URLRequest(url: url)
            newRequest.httpMethod = "POST"
            newRequest.timeoutInterval = 15
            newRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            struct LoginPayload: Codable {
                let username: String
                let password: String
                let isLogin: Bool
            }
            newRequest.httpBody = try JSONEncoder().encode(LoginPayload(username: username, password: password, isLogin: true))
            request = newRequest
        }

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
        if client.backend == .reader {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "当前服务端不支持修改密码"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "oldpassword", value: oldPassword),
            URLQueryItem(name: "password", value: newPassword)
        ]

        let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.changePassword, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "修改密码失败(状态码: \(httpResponse.statusCode))"])
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "修改密码时发生未知错误"])
        }
    }
}
