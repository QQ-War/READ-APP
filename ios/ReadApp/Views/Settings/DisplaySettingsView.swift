import SwiftUI

struct DisplaySettingsView: View {
    @StateObject private var preferences = UserPreferences.shared

    var body: some View {
        List {
            Section(header: GlassySectionHeader(title: "视觉效果"), footer: Text("开启液态玻璃效果后，应用背景将呈现动态流动的色彩与磨砂质感。")) {
                Toggle("液态玻璃背景", isOn: $preferences.isLiquidGlassEnabled)
                if preferences.isLiquidGlassEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        sliderRow(title: "浮动横向边距", value: $preferences.floatingTabBarHorizontalInset, range: 0...40, step: 1, unit: "pt")
                        sliderRow(title: "浮动纵向边距", value: $preferences.floatingTabBarVerticalInset, range: 0...40, step: 1, unit: "pt")
                        sliderRow(title: "浮动圆角", value: $preferences.floatingTabBarCornerRadius, range: 12...32, step: 1, unit: "pt")
                        sliderRow(title: "浮动阴影透明度", value: $preferences.floatingTabBarShadowOpacity, range: 0...0.35, step: 0.01, unit: "")
                        sliderRow(title: "浮动阴影模糊", value: $preferences.floatingTabBarShadowRadius, range: 0...28, step: 1, unit: "pt")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("显示与美化")
        .navigationBarTitleDisplayMode(.inline)
        .glassyListStyle()
    }

    private func sliderRow(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel(value.wrappedValue, unit: unit))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func valueLabel(_ value: CGFloat, unit: String) -> String {
        if unit.isEmpty {
            return String(format: "%.2f", value)
        }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))\(unit)"
        }
        return String(format: "%.1f%@", value, unit)
    }
}

#Preview {
    NavigationView {
        DisplaySettingsView()
    }
}
