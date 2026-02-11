import SwiftUI
import UIKit

private enum LiquidGlassTokens {
    static let cardStrokeOpacity = 0.18
    static let floatingStrokeOpacity = 0.2
    static let toolbarStrokeOpacity = 0.18
    static let buttonStrokeOpacity = 0.2
    static let strokeWidth: CGFloat = 0.8
    static let cardShadowOpacity = 0.12
    static let floatingShadowOpacity = 0.16
    static let pressShadowOpacity = 0.12
    static let cardShadowRadius: CGFloat = 10
    static let floatingShadowRadius: CGFloat = 18
    static let pressShadowRadius: CGFloat = 8
    static let cardShadowYOffset: CGFloat = 6
    static let floatingShadowYOffset: CGFloat = 8
    static let pressShadowYOffset: CGFloat = 4
}

private struct GlassyListStyleModifier: ViewModifier {
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            if #available(iOS 16.0, *) {
                content.scrollContentBackground(.hidden)
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct GlassyCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(padding)
                .liquidGlassBackground()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(LiquidGlassTokens.cardStrokeOpacity), lineWidth: LiquidGlassTokens.strokeWidth)
                )
                .shadow(
                    color: Color.black.opacity(LiquidGlassTokens.cardShadowOpacity),
                    radius: LiquidGlassTokens.cardShadowRadius,
                    x: 0,
                    y: LiquidGlassTokens.cardShadowYOffset
                )
        } else {
            content
        }
    }
}

private struct GlassyFloatingBarModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(padding)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(LiquidGlassTokens.floatingStrokeOpacity), lineWidth: LiquidGlassTokens.strokeWidth)
                )
                .shadow(
                    color: Color.black.opacity(LiquidGlassTokens.floatingShadowOpacity),
                    radius: LiquidGlassTokens.floatingShadowRadius,
                    x: 0,
                    y: LiquidGlassTokens.floatingShadowYOffset
                )
        } else {
            content
        }
    }
}

private struct GlassyButtonStyleModifier: ViewModifier {
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false
    @AppStorage("liquidGlassOpacity") private var opacity = 0.8

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Color.clear.background(.ultraThinMaterial)
                        .opacity(opacity)
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(LiquidGlassTokens.buttonStrokeOpacity), lineWidth: LiquidGlassTokens.strokeWidth))
                .buttonStyle(GlassyPressableButtonStyle())
        } else {
            content
        }
    }
}

private struct GlassyToolbarButtonModifier: ViewModifier {
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false
    @AppStorage("liquidGlassOpacity") private var opacity = 0.8

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(6)
                .background(
                    Color.clear.background(.ultraThinMaterial)
                        .opacity(opacity)
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(LiquidGlassTokens.toolbarStrokeOpacity), lineWidth: LiquidGlassTokens.strokeWidth))
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.15), value: isEnabled)
                .buttonStyle(GlassyPressableButtonStyle())
        } else {
            content
        }
    }
}

private struct GlassyPressEffectModifier: ViewModifier {
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .scaleEffect(0.98)
                .shadow(
                    color: Color.black.opacity(LiquidGlassTokens.pressShadowOpacity),
                    radius: LiquidGlassTokens.pressShadowRadius,
                    x: 0,
                    y: LiquidGlassTokens.pressShadowYOffset
                )
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func ifAvailableHideTabBar() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func glassyListStyle() -> some View {
        self.modifier(GlassyListStyleModifier())
    }

    @ViewBuilder
    func glassyCard(cornerRadius: CGFloat = 16, padding: CGFloat = 8) -> some View {
        self.modifier(GlassyCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    @ViewBuilder
    func glassyFloatingBar(cornerRadius: CGFloat = 24, padding: CGFloat = 10) -> some View {
        self.modifier(GlassyFloatingBarModifier(cornerRadius: cornerRadius, padding: padding))
    }

    @ViewBuilder
    func glassyButtonStyle() -> some View {
        self.modifier(GlassyButtonStyleModifier())
    }

    @ViewBuilder
    func glassyToolbarButton() -> some View {
        self.modifier(GlassyToolbarButtonModifier())
    }

    @ViewBuilder
    func glassyPressEffect() -> some View {
        self.modifier(GlassyPressEffectModifier())
    }
}

struct GlassyPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.2 : 0.08), radius: configuration.isPressed ? 10 : 6, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.22 : 0.12), lineWidth: 0.8)
            )
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassySectionHeader: View {
    let title: String
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false

    var body: some View {
        Text(title)
            .font(.caption)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isEnabled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(isEnabled ? 0.18 : 0.0), lineWidth: 0.8))
            .foregroundColor(.secondary)
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
