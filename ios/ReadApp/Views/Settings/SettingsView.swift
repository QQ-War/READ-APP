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
            }

            Section(header: Text("通用设置")) {
                NavigationLink(destination: ReadingSettingsView()) {
                    Label("阅读设置", systemImage: "book.pages")
                }
                
                NavigationLink(destination: CacheManagementView()) {
                    Label("缓存与下载管理", systemImage: "archivebox")
                }

                NavigationLink(destination: TTSSettingsView()) {
                    Label("听书设置", systemImage: "speaker.wave.2")
                }
                
                NavigationLink(destination: ContentSettingsView()) {
                    Label("内容与净化", systemImage: "shield.checkered")
                }
                NavigationLink(destination: RssSourcesView()) {
                    Label("订阅源管理", systemImage: "newspaper.fill")
                }
            }

            Section(header: Text("系统")) {
                NavigationLink(destination: DebugSettingsView()) {
                    Label("调试与日志", systemImage: "hammer")
                }
            }
            
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
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
    }
}


// MARK: - 分享视图
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
