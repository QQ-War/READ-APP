import UIKit

final class ImagePreviewViewController: UIViewController, UIScrollViewDelegate {
    private let imageURL: URL
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    init(imageURL: URL) {
        self.imageURL = imageURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if UserPreferences.shared.isLiquidGlassEnabled {
            view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.2)
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            blur.frame = view.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(blur, at: 0)
        }

        scrollView.delegate = self
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = UserPreferences.shared.isLiquidGlassEnabled ? .clear : .black
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDismiss))
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        Task {
            if let image = await ImageCache.shared.image(for: imageURL) {
                await MainActor.run { [weak self] in
                    self?.setImage(image)
                }
            }
        }
    }

    private func setImage(_ image: UIImage) {
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size
        updateZoomScale()
        centerImage()
    }

    private func updateZoomScale() {
        guard let image = imageView.image else { return }
        let widthScale = view.bounds.width / image.size.width
        let heightScale = view.bounds.height / image.size.height
        let minScale = min(widthScale, heightScale)
        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
    }

    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateZoomScale()
        centerImage()
    }

    @objc private func handleDismiss() {
        dismiss(animated: true)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let location = gesture.location(in: imageView)
        let zoomRect = zoomRectForScale(scale: min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 2.5), center: location)
        scrollView.zoom(to: zoomRect, animated: true)
    }

    private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        return CGRect(origin: origin, size: size)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}
