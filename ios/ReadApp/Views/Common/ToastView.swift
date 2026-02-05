import SwiftUI

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(UserPreferences.shared.isLiquidGlassEnabled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.black.opacity(0.78)))
            )
            .frame(maxWidth: 320, alignment: .leading)
            .shadow(radius: 6)
            .padding(.horizontal, 16)
    }
}
