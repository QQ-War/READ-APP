import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { containerGeometry in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(GeometryReader { contentGeometry in
                        Color.clear.onAppear {
                            contentWidth = contentGeometry.size.width
                            containerWidth = containerGeometry.size.width
                            startAnimation()
                        }
                    })
                    .offset(x: offset)
            }
        }
        .frame(height: 20)
        .clipped()
        .onChange(of: text) { _ in
            resetAndRestart()
        }
    }
    
    private func startAnimation() {
        guard contentWidth > containerWidth else { return }
        
        let duration = Double(contentWidth / 40)
        
        withAnimation(Animation.linear(duration: duration).delay(1).repeatForever(autoreverses: false)) {
            offset = -contentWidth
        }
    }
    
    private func resetAndRestart() {
        offset = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startAnimation()
        }
    }
}
