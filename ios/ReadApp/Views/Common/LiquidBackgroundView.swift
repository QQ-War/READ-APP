import SwiftUI

struct LiquidBackgroundView: View {
    @State private var startAnimation: Bool = false
    
    var body: some View {
        ZStack {
            // 底层基础颜色
            Color(uiColor: .systemBackground)
            
            // 动态流动的色彩球
            GeometryReader { proxy in
                let size = proxy.size
                
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: size.width * 0.7)
                        .offset(x: startAnimation ? size.width * 0.3 : -size.width * 0.1,
                                y: startAnimation ? size.height * 0.1 : size.height * 0.4)
                    
                    Circle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: size.width * 0.8)
                        .offset(x: startAnimation ? -size.width * 0.2 : size.width * 0.2,
                                y: startAnimation ? size.height * 0.5 : -size.height * 0.1)
                    
                    Circle()
                        .fill(Color.cyan.opacity(0.2))
                        .frame(width: size.width * 0.6)
                        .offset(x: startAnimation ? size.width * 0.1 : -size.width * 0.3,
                                y: startAnimation ? -size.height * 0.2 : size.height * 0.2)
                }
                .blur(radius: 60)
            }
            
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
