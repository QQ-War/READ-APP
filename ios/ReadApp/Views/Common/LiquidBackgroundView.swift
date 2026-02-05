import SwiftUI

struct LiquidBackgroundView: View {
    @State private var startAnimation: Bool = false
    
    var body: some View {
        ZStack {
            // 底层基础颜色
            Color(uiColor: .systemBackground)
            
            // 动态流动的色彩球
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 400)
                    .offset(x: startAnimation ? 100 : -100,
                            y: startAnimation ? 50 : 200)
                
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 450)
                    .offset(x: startAnimation ? -150 : 150,
                            y: startAnimation ? 300 : -50)
                
                Circle()
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: 350)
                    .offset(x: startAnimation ? 80 : -180,
                            y: startAnimation ? -100 : 100)
            }
            .blur(radius: 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 玻璃层
            Rectangle()
                .fill(.ultraThinMaterial)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 15).repeatForever(autoreverses: true)) {
                startAnimation.toggle()
            }
        }
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

#Preview {
    Text("Hello Glass")
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .liquidGlassBackground()
}
