import Foundation

struct ReaderTtsRequest: Encodable {
    let text: String
    let type: String = "httpTTS"
    let voice: String
    let pitch: String
    let rate: String
    let accessToken: String
    let base64: String = "1"
}
