import SwiftUI

struct DisplaySettingsView: View {
    @StateObject private var preferences = UserPreferences.shared

    var body: some View {
        List {
            Section(header: Text("视觉效果"), footer: Text("开启液态玻璃效果后，应用背景将呈现动态流动的色彩与磨砂质感。")) {
                Toggle("液态玻璃背景", isOn: $preferences.isLiquidGlassEnabled)
            }
        }
        .navigationTitle("显示与美化")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        DisplaySettingsView()
    }
}
