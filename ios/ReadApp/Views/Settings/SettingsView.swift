import SwiftUI

struct SettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section {
                NavigationLink(destination: AccountSettingsView()) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(preferences.username)
                                .font(.headline)
                            Text("账号与服务器设置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 4)
                .glassyCard(cornerRadius: 16, padding: 6)
            }
            .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)

            Section(header: Text("通用设置")) {
                ForEach(preferences.settingsOrder, id: \.self) { key in
                    if let item = SettingItem(rawValue: key) {
                        destinationLink(for: item)
                            .onDrag {
                                NSItemProvider(object: key as NSString)
                            }
                            .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
                    }
                }
                .onMove(perform: move)
            }

            Section(header: Text("系统")) {
                NavigationLink(destination: DebugSettingsView()) {
                    Label("调试与日志", systemImage: "hammer")
                }
            }
            .listRowBackground(preferences.isLiquidGlassEnabled ? Color.clear : nil)
            
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("ReadApp iOS")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("版本 1.0.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }
        .glassyListStyle()
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
                    .glassyToolbarButton()
            }
        }
    }

    @ViewBuilder
    private func destinationLink(for item: SettingItem) -> some View {
        switch item {
        case .display:
            NavigationLink(destination: DisplaySettingsView()) {
                Label(item.title, systemImage: item.systemImage)
            }
        case .reading:
            NavigationLink(destination: ReadingSettingsView()) {
                Label(item.title, systemImage: item.systemImage)
            }
        case .cache:
            NavigationLink(destination: CacheManagementView()) {
                Label(item.title, systemImage: item.systemImage)
            }
        case .tts:
            NavigationLink(destination: TTSSettingsView()) {
                Label(item.title, systemImage: item.systemImage)
            }
        case .content:
            NavigationLink(destination: ContentSettingsView()) {
                Label(item.title, systemImage: item.systemImage)
            }
        case .rss:
            NavigationLink(destination: RssSourcesView()) {
                Label(item.title, systemImage: item.systemImage)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        preferences.settingsOrder.move(fromOffsets: source, toOffset: destination)
    }
}
