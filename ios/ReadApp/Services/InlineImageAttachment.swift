import UIKit

final class InlineImageAttachment: NSTextAttachment {
    static let didLoadNotification = Notification.Name("InlineImageAttachmentDidLoad")
    private(set) var imageURL: URL
    var onImageLoaded: (() -> Void)?
    private var isLoading = false

    init(imageURL: URL, maxWidth: CGFloat) {
        self.imageURL = imageURL
        super.init(data: nil, ofType: nil)
        let width = max(80, maxWidth)
        let height = max(80, width * 0.75)
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        image = InlineImageAttachment.placeholderImage(size: bounds.size)
        loadIfNeeded()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func loadIfNeeded() {
        guard !isLoading else { return }
        isLoading = true
        Task { [imageURL] in
            if let img = await ImageCache.shared.image(for: imageURL) {
                let resized = InlineImageAttachment.scale(image: img, to: bounds.size)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.image = resized
                    self.onImageLoaded?()
                    NotificationCenter.default.post(name: InlineImageAttachment.didLoadNotification, object: self)
                }
            }
        }
    }

    private static func placeholderImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemGray5.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func scale(image: UIImage, to size: CGSize) -> UIImage {
        let aspect = min(size.width / image.size.width, size.height / image.size.height)
        let targetSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let origin = CGPoint(x: (size.width - targetSize.width) / 2, y: (size.height - targetSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: targetSize))
        }
    }
}
