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
        Task {
            let data = await MangaImageService.shared.fetchImageData(for: url, referer: refererOverride)
            await MainActor.run {
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    self.isLoading = false
                } else {
                    self.isLoading = false
                    self.errorMessage = "加载失败"
                }
            }
        }
    }
}
