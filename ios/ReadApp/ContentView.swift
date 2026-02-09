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
    }

    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        if preferences.isLiquidGlassEnabled {
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.2)
            appearance.shadowColor = UIColor.white.withAlphaComponent(0.12)
        } else {
            appearance.configureWithDefaultBackground()
        }
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        applyFloatingTabBarIfNeeded()
        updateSearchBarAppearance()
    }

    private func applyFloatingTabBarIfNeeded() {
        guard preferences.isLiquidGlassEnabled else { return }
        DispatchQueue.main.async {
            guard let tabBarController = UIApplication.shared.findTabBarController() else { return }
            let tabBar = tabBarController.tabBar
            let view = tabBarController.view
            let horizontalInset: CGFloat = 18
            let verticalInset: CGFloat = 10
            let safeBottom = view?.safeAreaInsets.bottom ?? 0
            var frame = tabBar.frame
            frame.size.width = (view?.bounds.width ?? frame.size.width) - horizontalInset * 2
            frame.origin.x = horizontalInset
            frame.origin.y = (view?.bounds.height ?? frame.maxY) - frame.height - max(verticalInset, safeBottom / 2)
            tabBar.frame = frame
            tabBar.isTranslucent = true
            tabBar.layer.cornerRadius = 24
            tabBar.layer.cornerCurve = .continuous
            tabBar.layer.masksToBounds = true
        }
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
