import SwiftUI
import UIKit

struct MangaNativeReader: UIViewRepresentable {
    let sentences: [String]
    let chapterUrl: String?
    @Binding var showUIControls: Bool
    @Binding var currentVisibleIndex: Int
    @Binding var pendingScrollIndex: Int?

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0 // 漫画允许更大缩放
        scrollView.delegate = context.coordinator
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = true
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.addSubview(stackView)
        context.coordinator.stackView = stackView
        context.coordinator.scrollView = scrollView
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scrollView.addGestureRecognizer(tapGesture)
        
        context.coordinator.loadImages(from: sentences, into: stackView)
        
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // 关键修复：结合 URL 和内容长度/哈希来判断是否需要重新加载
        let currentHash = sentences.joined().hashValue
        if context.coordinator.lastChapterUrl != chapterUrl || context.coordinator.lastContentHash != currentHash {
            context.coordinator.lastChapterUrl = chapterUrl
            context.coordinator.lastContentHash = currentHash
            context.coordinator.loadImages(from: sentences, into: context.coordinator.stackView!)
        }
        
        if let scrollIndex = pendingScrollIndex {
            context.coordinator.scrollToIndex(scrollIndex)
            DispatchQueue.main.async {
                self.pendingScrollIndex = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: MangaNativeReader
        var stackView: UIStackView?
        var scrollView: UIScrollView?
        var lastChapterUrl: String?
        var lastContentHash: Int? // 新增：内容哈希追踪
        
        init(_ parent: MangaNativeReader) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return stackView
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: scrollView)
            let screenHeight = scrollView?.bounds.height ?? 1000
            
            // 只有点击屏幕中间区域才唤起菜单，防止边缘翻页误触
            if location.y > screenHeight * 0.2 && location.y < screenHeight * 0.8 {
                withAnimation {
                    parent.showUIControls.toggle()
                }
            }
        }
        
        func loadImages(from sentences: [String], into stack: UIStackView) {
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            for sentence in sentences {
                if sentence.contains("__IMG__") {
                    let urlString = extractUrl(from: sentence)
                    let container = UIView()
                    container.backgroundColor = .clear
                    
                    let imageView = UIImageView()
                    imageView.contentMode = .scaleAspectFit
                    imageView.clipsToBounds = true
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(imageView)
                    
                    // 初始高度占位
                    let heightConstraint = imageView.heightAnchor.constraint(equalToConstant: 400)
                    heightConstraint.priority = .defaultHigh
                    
                    NSLayoutConstraint.activate([
                        imageView.topAnchor.constraint(equalTo: container.topAnchor),
                        imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                        imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                        imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                        heightConstraint
                    ])
                    
                    if let url = URL(string: urlString) {
                        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
                        URLSession.shared.dataTask(with: request) { [weak imageView, weak heightConstraint] data, _, _ in
                            guard let data = data, let image = UIImage(data: data),
                                  let iv = imageView, let hc = heightConstraint else { return }
                            DispatchQueue.main.async {
                                iv.image = image
                                let ratio = image.size.height / image.size.width
                                hc.isActive = false
                                iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: ratio).isActive = true
                                iv.layoutIfNeeded()
                            }
                        }.resume()
                    }
                    stack.addArrangedSubview(container)
                } else {
                    let label = UILabel()
                    label.text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    label.numberOfLines = 0
                    label.font = .systemFont(ofSize: 16)
                    label.textColor = .secondaryLabel
                    label.textAlignment = .center
                    let container = UIView()
                    container.addSubview(label)
                    label.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        label.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
                        label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
                        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                        label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
                    ])
                    stack.addArrangedSubview(container)
                }
            }
            scrollView?.setContentOffset(.zero, animated: false)
        }
        
        func scrollToIndex(_ index: Int) {
            guard let stack = stackView, index < stack.arrangedSubviews.count else { return }
            let targetView = stack.arrangedSubviews[index]
            scrollView?.setContentOffset(CGPoint(x: 0, y: targetView.frame.origin.y), animated: false)
        }
        
        private func extractUrl(from sentence: String) -> String {
            return sentence.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offset = scrollView.contentOffset.y
            guard let stack = stackView else { return }
            for (index, view) in stack.arrangedSubviews.enumerated() {
                if view.frame.origin.y > offset - 10 {
                    parent.currentVisibleIndex = index
                    break
                }
            }
        }
    }
}
