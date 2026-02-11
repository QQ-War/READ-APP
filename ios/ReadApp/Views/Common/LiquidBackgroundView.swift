import SwiftUI

struct LiquidBackgroundView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        ZStack {
            // 玻璃材质层：静态材质，性能开销极低
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(preferences.liquidGlassOpacity)
                .animation(.easeInOut(duration: 0.3), value: preferences.liquidGlassOpacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder
    func liquidGlassBackground() -> some View {
        self.background {
            if UserPreferences.shared.isLiquidGlassEnabled {
                LiquidBackgroundView()
            }
        }
    }
}