import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var apiService: APIService
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
                NavigationLink(destination: ReadingSettingsView().environmentObject(apiService)) {
                    Label("阅读设置", systemImage: "book.pages")
                }
                
                NavigationLink(destination: TTSSettingsView().environmentObject(apiService)) {
                    Label("听书设置", systemImage: "speaker.wave.2")
                }
                
                NavigationLink(destination: ContentSettingsView()) {
                    Label("内容与净化", systemImage: "shield.checkered")
                }
            }

            Section(header: Text("系统")) {
                NavigationLink(destination: DebugSettingsView().environmentObject(apiService)) {
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
