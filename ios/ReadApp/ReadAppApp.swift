import SwiftUI

@main
struct ReadAppApp: App {
    @StateObject private var apiService = APIService.shared
    @StateObject private var preferences = UserPreferences.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(apiService)
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

