import SwiftUI
import UIKit

struct TabBarControllerAccessor: UIViewControllerRepresentable {
    let onUpdate: (UITabBarController) -> Void

    func makeUIViewController(context: Context) -> AccessorViewController {
        AccessorViewController(onUpdate: onUpdate)
    }

    func updateUIViewController(_ uiViewController: AccessorViewController, context: Context) {
        uiViewController.onUpdate = onUpdate
    }

    final class AccessorViewController: UIViewController {
        var onUpdate: (UITabBarController) -> Void

        init(onUpdate: @escaping (UITabBarController) -> Void) {
            self.onUpdate = onUpdate
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if let tabBarController = tabBarController {
                onUpdate(tabBarController)
            }
        }
    }
}
