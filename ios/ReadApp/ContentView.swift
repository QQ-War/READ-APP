import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var preferences = UserPreferences.shared
    @EnvironmentObject var bookshelfStore: BookshelfStore
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var toastTask: Task<Void, Never>?
    @State private var toastDetail: SelectableMessage?
    
    var body: some View {
        ZStack {
            if !preferences.isLoggedIn {
                LoginView()
            } else {
                TabView {
                    NavigationView {
                        BookListView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "book.fill")
                        Text("书架")
                    }
                    
                    NavigationView {
                        SourceListView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "list.bullet")
                        Text("书源")
                    }

                    NavigationView {
                        SettingsView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("设置")
                    }
                }
            }

            if showToast, let message = toastMessage {
                VStack {
                    ToastView(message: message)
                        .onTapGesture {
                            toastDetail = SelectableMessage(title: "错误", message: message)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 12)
                .animation(.easeInOut(duration: 0.2), value: showToast)
            }
        }
        .sheet(item: $toastDetail) { detail in
            SelectableMessageSheet(title: detail.title, message: detail.message) {
                toastDetail = nil
            }
        }
        .onChange(of: bookshelfStore.errorMessage) { newValue in
            guard let message = newValue, !message.isEmpty else { return }
            toastTask?.cancel()
            toastMessage = message
            showToast = true
            bookshelfStore.errorMessage = nil
            toastTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showToast = false
            }
        }
        .onAppear { updateTabBarAppearance() }
        .onChange(of: preferences.isLiquidGlassEnabled) { _ in
            updateTabBarAppearance()
        }
        .onChange(of: preferences.liquidGlassOpacity) { _ in
            updateTabBarAppearance()
        }
    }

    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        if preferences.isLiquidGlassEnabled {
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
        } else {
            appearance.configureWithDefaultBackground()
        }
        
        // 全局配置
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        
        // 强制刷新当前实例
        DispatchQueue.main.async {
            if let tabBarController = UIApplication.shared.findTabBarController() {
                let tabBar = tabBarController.tabBar
                
                // 处理 901 视图（悬浮玻璃层）
                if preferences.isLiquidGlassEnabled {
                    applyFloatingTabBar(to: tabBar)
                } else {
                    tabBar.viewWithTag(901)?.removeFromSuperview()
                    // 恢复系统默认层级
                    tabBar.isTranslucent = true
                    tabBar.layer.cornerRadius = 0
                    tabBar.layer.shadowOpacity = 0
                }
                
                // 强制应用 Appearance 以清除或恢复背景
                tabBar.standardAppearance = appearance
                if #available(iOS 15.0, *) {
                    tabBar.scrollEdgeAppearance = appearance
                }
                tabBar.setNeedsLayout()
                tabBar.layoutIfNeeded()
            }
        }
        updateSearchBarAppearance()
    }

    private func applyFloatingTabBar(to tabBar: UITabBar) {
        let backgroundTag = 901
        let blurTag = 902
        tabBar.isTranslucent = true
        tabBar.layer.cornerRadius = 24
        tabBar.layer.cornerCurve = .continuous
        tabBar.layer.masksToBounds = false
        tabBar.clipsToBounds = false

        let horizontalInset: CGFloat = 16
        let bottomPadding: CGFloat = 12 // 底部悬浮距离
        let topExtend: CGFloat = 2 // 向上微调，确保盖住图标
        
        let backgroundFrame = CGRect(
            x: horizontalInset,
            y: -topExtend,
            width: tabBar.bounds.width - horizontalInset * 2,
            height: tabBar.bounds.height - bottomPadding + topExtend
        )
        
        let container: UIView
        if let existing = tabBar.viewWithTag(backgroundTag) {
            container = existing
            container.frame = backgroundFrame
        } else {
            container = UIView(frame: backgroundFrame)
            container.tag = backgroundTag
            container.isUserInteractionEnabled = false
            container.layer.cornerRadius = 24
            container.layer.cornerCurve = .continuous
            container.layer.shadowColor = UIColor.black.withAlphaComponent(0.18).cgColor
            container.layer.shadowOpacity = 1
            container.layer.shadowRadius = 18
            container.layer.shadowOffset = CGSize(width: 0, height: 10)
            container.layer.masksToBounds = false
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            tabBar.insertSubview(container, at: 0)
        }

        // 复用模糊层，避免频繁销毁重建导致额外开销
        let blurView: UIVisualEffectView
        if let existing = container.viewWithTag(blurTag) as? UIVisualEffectView {
            blurView = existing
            blurView.frame = container.bounds
        } else {
            let created = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            created.tag = blurTag
            created.frame = container.bounds
            created.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            created.layer.cornerRadius = 24
            created.layer.cornerCurve = .continuous
            created.layer.masksToBounds = true
            container.addSubview(created)
            blurView = created
        }
        
        // 关键：将不透明度滑块应用到背景颜色和整体透明度上
        let opacity = CGFloat(preferences.liquidGlassOpacity)
        blurView.backgroundColor = UIColor.systemBackground.withAlphaComponent(max(0.05, opacity * 0.4))
        blurView.alpha = opacity
    }

    private func updateSearchBarAppearance() {
        let searchBar = UISearchBar.appearance()
        if preferences.isLiquidGlassEnabled {
            searchBar.backgroundImage = UIImage()
            searchBar.backgroundColor = UIColor.clear
            searchBar.barTintColor = UIColor.systemBackground.withAlphaComponent(0.2)
            if #available(iOS 13.0, *) {
                let field = searchBar.searchTextField
                field.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.2)
                field.layer.cornerRadius = 10
                field.clipsToBounds = true
            }
        } else {
            searchBar.backgroundImage = nil
            searchBar.backgroundColor = nil
            searchBar.barTintColor = nil
            if #available(iOS 13.0, *) {
                let field = searchBar.searchTextField
                field.backgroundColor = nil
                field.layer.cornerRadius = 0
                field.clipsToBounds = false
            }
        }
    }
}
