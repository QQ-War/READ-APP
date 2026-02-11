import SwiftUI

struct DisplaySettingsView: View {
    @StateObject private var preferences = UserPreferences.shared

    var body: some View {
        List {
            Section(header: GlassySectionHeader(title: "视觉效果"), footer: Text("开启液态玻璃效果后，应用背景将呈现动态流动的色彩与磨砂质感。")) {
                Toggle("液态玻璃背景", isOn: $preferences.isLiquidGlassEnabled)
                
                if preferences.isLiquidGlassEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("玻璃透明度")
                            Spacer()
                            Text("\(Int(preferences.liquidGlassOpacity * 100))%")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $preferences.liquidGlassOpacity, in: 0.1...1.0, step: 0.05)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("显示与美化")
        .navigationBarTitleDisplayMode(.inline)
        .glassyListStyle()
    }
}

#Preview {
    NavigationView {
        DisplaySettingsView()
    }
}
