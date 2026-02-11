import SwiftUI

struct LiquidBackgroundView: View {
    let opacity: Double
    
    var body: some View {
        ZStack {
            // 玻璃材质层：静态材质，性能开销极低
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(opacity)
                .animation(.easeInOut(duration: 0.3), value: opacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LiquidGlassBackgroundModifier: ViewModifier {
    @AppStorage("isLiquidGlassEnabled") private var isEnabled = false
    @AppStorage("liquidGlassOpacity") private var opacity = 0.8

    func body(content: Content) -> some View {
        content.background {
            if isEnabled {
                LiquidBackgroundView(opacity: opacity)
            }
        }
    }
}

extension View {
    func liquidGlassBackground() -> some View {
        modifier(LiquidGlassBackgroundModifier())
    }
}
