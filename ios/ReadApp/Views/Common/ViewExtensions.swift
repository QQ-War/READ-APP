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
    
    @ViewBuilder
    func glassyListStyle() -> some View {
        if UserPreferences.shared.isLiquidGlassEnabled {
            if #available(iOS 16.0, *) {
                self.scrollContentBackground(.hidden)
                    .liquidGlassBackground()
            } else {
                self.liquidGlassBackground()
            }
        } else {
            self
        }
    }
}

struct HideTabBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                setTabBarHidden(true)
            }
            .onDisappear {
                setTabBarHidden(false)
            }
    }
    
    private func setTabBarHidden(_ hidden: Bool) {
        // 在 iOS 15 中，由于 SwiftUI 导航的复杂性，DispatchQueue.main.async 确保在布局更新后执行
        DispatchQueue.main.async {
            if let tabBarController = UIApplication.shared.findTabBarController() {
                // 使用动画平滑切换，避免突兀，同时确保状态被正确应用
                UIView.animate(withDuration: 0.2) {
                    tabBarController.tabBar.isHidden = hidden
                    // 修正底部安全区域偏移
                    tabBarController.view.setNeedsLayout()
                    tabBarController.view.layoutIfNeeded()
                }
            }
        }
    }
}

// MARK: - UIKit 助手扩展

extension UIApplication {
    func findTabBarController() -> UITabBarController? {
        // 获取当前活跃的窗口场景
        let scenes = connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first(where: { $0.isKeyWindow })
        
        return window?.rootViewController?.findTabBarController()
    }
}

extension UIViewController {
    func findTabBarController() -> UITabBarController? {
        // 递归查找 UITabBarController
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }
        
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.findTabBarController()
        }
        
        for child in children {
            if let found = child.findTabBarController() {
                return found
            }
        }
        
        return nil
    }
}