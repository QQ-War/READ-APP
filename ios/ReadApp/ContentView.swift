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
                    .background {
                        if preferences.isLiquidGlassEnabled {
                            LiquidBackgroundView()
                        }
                    }
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("设置")
                    }
                }
                .background(
                    TabBarControllerAccessor { tabBarController in
                        updateTabBarAppearance(for: tabBarController)
                    }
                )
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
        .onChange(of: preferences.floatingTabBarHorizontalInset) { _ in
            updateTabBarAppearance()
        }
        .onChange(of: preferences.floatingTabBarVerticalInset) { _ in
            updateTabBarAppearance()
        }
        .onChange(of: preferences.floatingTabBarCornerRadius) { _ in
            updateTabBarAppearance()
        }
        .onChange(of: preferences.floatingTabBarShadowOpacity) { _ in
            updateTabBarAppearance()
        }
        .onChange(of: preferences.floatingTabBarShadowRadius) { _ in
            updateTabBarAppearance()
        }
    }

    private func updateTabBarAppearance(for tabBarController: UITabBarController? = nil) {
        let appearance = UITabBarAppearance()
        if preferences.isLiquidGlassEnabled {
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = nil
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
        } else {
            appearance.configureWithDefaultBackground()
        }
        if let tabBarController = tabBarController ?? UIApplication.shared.findTabBarController() {
            let tabBar = tabBarController.tabBar
            tabBar.standardAppearance = appearance
            if #available(iOS 15.0, *) {
                tabBar.scrollEdgeAppearance = appearance
            }
            if preferences.isLiquidGlassEnabled {
                applyFloatingTabBarIfNeeded(tabBarController: tabBarController)
            } else {
                resetTabBarToDefault(tabBarController: tabBarController)
            }
        } else {
            DispatchQueue.main.async {
                updateTabBarAppearance(for: UIApplication.shared.findTabBarController())
            }
        }
        updateSearchBarAppearance()
    }

    private func applyFloatingTabBarIfNeeded(tabBarController: UITabBarController) {
        guard preferences.isLiquidGlassEnabled else { return }
        let tabBar = tabBarController.tabBar
        let view = tabBarController.view
        let horizontalInset = preferences.floatingTabBarHorizontalInset
        let verticalInset = preferences.floatingTabBarVerticalInset
        let cornerRadius = preferences.floatingTabBarCornerRadius
        let shadowOpacity = preferences.floatingTabBarShadowOpacity
        let shadowRadius = preferences.floatingTabBarShadowRadius
        let safeBottom = view?.safeAreaInsets.bottom ?? 0
        var frame = tabBar.frame
        let viewWidth = view?.bounds.width ?? frame.size.width
        let viewHeight = view?.bounds.height ?? frame.maxY
        frame.size.width = viewWidth - horizontalInset * 2
        frame.origin.x = (viewWidth - frame.size.width) / 2
        frame.origin.y = viewHeight - safeBottom - frame.height - verticalInset
        tabBar.frame = frame
        tabBar.isTranslucent = true
        tabBar.layer.cornerRadius = cornerRadius
        tabBar.layer.cornerCurve = .continuous
        tabBar.layer.masksToBounds = false
        tabBar.clipsToBounds = false
        tabBar.backgroundImage = UIImage()
        tabBar.shadowImage = UIImage()

        tabBarController.additionalSafeAreaInsets.bottom = -verticalInset

        let backgroundTag = 901
        if let existing = tabBar.viewWithTag(backgroundTag) {
            existing.frame = tabBar.bounds
            if let blurView = existing.subviews.first as? UIVisualEffectView {
                blurView.frame = existing.bounds
            }
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
            return
        }

        let container = UIView(frame: tabBar.bounds)
        container.tag = backgroundTag
        container.isUserInteractionEnabled = false
        container.layer.cornerRadius = cornerRadius
        container.layer.cornerCurve = .continuous
        container.layer.shadowColor = UIColor.black.withAlphaComponent(shadowOpacity).cgColor
        container.layer.shadowOpacity = 1
        container.layer.shadowRadius = shadowRadius
        container.layer.shadowOffset = CGSize(width: 0, height: 10)
        container.layer.masksToBounds = false

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.frame = container.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.layer.cornerRadius = cornerRadius
        blurView.layer.cornerCurve = .continuous
        blurView.layer.masksToBounds = true
        blurView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.18)

        container.addSubview(blurView)
        tabBar.insertSubview(container, at: 0)
        tabBar.setNeedsLayout()
        tabBar.layoutIfNeeded()
    }

    private func resetTabBarToDefault(tabBarController: UITabBarController) {
        let tabBar = tabBarController.tabBar
        let container = tabBar.superview ?? tabBarController.view
        let bounds = container?.bounds ?? tabBarController.view?.bounds ?? .zero

        let backgroundTag = 901
        tabBar.viewWithTag(backgroundTag)?.removeFromSuperview()

        let size = tabBar.sizeThatFits(bounds.size)
        tabBar.frame = CGRect(x: 0, y: bounds.height - size.height, width: bounds.width, height: size.height)
        tabBar.isTranslucent = false
        tabBar.layer.cornerRadius = 0
        tabBar.layer.cornerCurve = .continuous
        tabBar.layer.masksToBounds = true
        tabBar.clipsToBounds = true
        tabBar.backgroundImage = nil
        tabBar.shadowImage = nil

        tabBarController.additionalSafeAreaInsets.bottom = 0
        tabBarController.view.setNeedsLayout()
        tabBarController.view.layoutIfNeeded()
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
