import SwiftUI

final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var task: Task<Void, Never>?

    func load(urlString: String?) {
        task?.cancel()
        image = nil
        guard let urlString, let url = URL(string: urlString) else { return }
        task = Task {
            let fetched = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.image = fetched }
        }
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let urlString: String?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @StateObject private var loader = CachedImageLoader()

    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .onAppear { loader.load(urlString: urlString) }
        .onChange(of: urlString) { _ in
            loader.load(urlString: urlString)
        }
    }
}
