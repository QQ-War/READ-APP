import SwiftUI
import UIKit

// MARK: - Zoomable ScrollView for Manga
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let hostedView = UIHostingController(rootView: content)
        hostedView.view.translatesAutoresizingMaskIntoConstraints = false
        hostedView.view.backgroundColor = .clear
        scrollView.addSubview(hostedView.view)

        NSLayoutConstraint.activate([
            hostedView.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            hostedView.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return scrollView.subviews.first
        }
    }
}

// MARK: - 支持 Header 的高性能图片加载组件
struct RemoteImageView: View {
    let url: URL?
    let refererOverride: String? // 新增：强制来源页覆盖
    @State private var image: UIImage? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @StateObject private var preferences = UserPreferences.shared
    private let logger = LogManager.shared

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(minHeight: 200) // 基础高度占位，防止容器塌陷
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text(errorMessage ?? "图片加载失败")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let url = url {
                        Text(url.absoluteString).font(.system(size: 8)).lineLimit(1).foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 200) // 失败也要保持高度
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .onAppear(perform: loadImage)
        .onChange(of: url) { _ in loadImage() }
    }

    private func loadImage() {
        guard let url = url else {
            errorMessage = "URL 无效"
            return
        }
        
        if image != nil || isLoading { return }
        isLoading = true
        errorMessage = nil

        // 如果开启了强制代理，则直接跳过直接请求，进入代理逻辑
        if preferences.forceMangaProxy, let proxyURL = buildProxyURL(for: url) {
            fetchImage(from: proxyURL, useProxy: true)
        } else {
            fetchImage(from: url, useProxy: false)
        }
    }

        private func fetchImage(from targetURL: URL, useProxy: Bool) {
            var request = URLRequest(url: targetURL)
            request.timeoutInterval = 15
            request.httpShouldHandleCookies = true
            request.cachePolicy = .returnCacheDataElseLoad
            
            // 1:1 模拟真实移动端浏览器请求头
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("image/webp,image/avif,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("image", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
            
            // 核心修正：Referer 精准策略
            var finalReferer = "https://m.kuaikanmanhua.com/" // 基础兜底
            
            if var customReferer = refererOverride, !customReferer.isEmpty {
                // 协议对齐
                if customReferer.hasPrefix("http://") {
                    customReferer = customReferer.replacingOccurrences(of: "http://", with: "https://")
                }
                // 补全斜杠
                if !customReferer.hasSuffix("/") {
                    customReferer += "/"
                }
                finalReferer = customReferer
            } else if let host = targetURL.host {
                // 自动推断兜底
                finalReferer = "https://\(host)/"
            }
            
            request.setValue(finalReferer, forHTTPHeaderField: "Referer")
    
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    
                    if statusCode == 200, let data = data, !data.isEmpty, let loadedImage = UIImage(data: data) {
                        self.image = loadedImage
                        self.isLoading = false
                        return
                    }
    
                    // 错误处理与重试逻辑
                    if !useProxy {
                        if (statusCode == 403 || statusCode == 401) {
                            // 如果因为 Referer 被拒，尝试最简主站 Referer 重试
                            var retryRequest = request
                            retryRequest.setValue("https://m.kuaikanmanhua.com/", forHTTPHeaderField: "Referer")
                            URLSession.shared.dataTask(with: retryRequest) { data, response, _ in
                                DispatchQueue.main.async {
                                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                                    if code == 200, let data = data, !data.isEmpty, let loadedImage = UIImage(data: data) {
                                        self.image = loadedImage
                                        self.isLoading = false
                                    } else if let proxyURL = buildProxyURL(for: targetURL) {
                                        self.fetchImage(from: proxyURL, useProxy: true)
                                    } else {
                                        self.isLoading = false
                                        self.errorMessage = "加载失败"
                                    }
                                }
                            }.resume()
                        } else if let proxyURL = buildProxyURL(for: targetURL) {
                            self.fetchImage(from: proxyURL, useProxy: true)
                        } else {
                            self.isLoading = false
                            self.errorMessage = "加载失败"
                        }
                    } else {
                        self.isLoading = false
                        self.errorMessage = "加载失败"
                    }
                }
            }.resume()
        }    
    private func buildProxyURL(for original: URL) -> URL? {
        let baseURL = APIService.shared.baseURL
        var components = URLComponents(string: "\(baseURL)/proxypng")
        components?.queryItems = [
            URLQueryItem(name: "url", value: original.absoluteString),
            URLQueryItem(name: "accessToken", value: UserPreferences.shared.accessToken)
        ]
        return components?.url
    }
}
