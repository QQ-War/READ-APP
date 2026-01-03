import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func ifAvailableHideTabBar() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self.modifier(HideTabBarModifier())
        }
    }
}

struct HideTabBarModifier: ViewModifier {
    @State private var isHidden = true

    func body(content: Content) -> some View {
        content
            .background(TabBarAccessor { tabBarController in
                tabBarController.tabBar.isHidden = isHidden
            })
            .onAppear { isHidden = true }
            .onDisappear { isHidden = false }
    }
}

struct TabBarAccessor: UIViewControllerRepresentable {
    let callback: (UITabBarController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            if let tabBarController = uiViewController.tabBarController {
                callback(tabBarController)
            }
        }
    }
}
