import SwiftUI

@main
struct ReadAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var bookshelfStore = BookshelfStore()
    @StateObject private var sourceStore = SourceStore()
    @StateObject private var preferences = UserPreferences.shared

    init() {
        FontManager.shared.registerCachedFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookshelfStore)
                .environmentObject(sourceStore)
                .preferredColorScheme(colorScheme)
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch preferences.darkMode {
        case .on: return .dark
        case .off: return .light
        case .system: return nil
        }
    }
}

import AVFoundation
