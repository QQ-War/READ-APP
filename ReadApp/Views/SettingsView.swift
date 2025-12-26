import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    @Environment(\.dismiss) var dismiss

    @State private var showTTSSelection = false
    @State private var ttsSummary = ""
    @State private var showLogoutAlert = false
    @State private var showShareSheet = false
    @State private var logFileURL: URL?
    @State private var showClearLogsAlert = false
    @State private var showClearCacheAlert = false

    var body: some View {
        NavigationView {
            Form {
                userSection
                readingSection
                ttsSection
                replaceRuleSection
                bookshelfSection
                debugSection
                footerSection
            }
            .navigationTitle("??")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("??") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showTTSSelection) {
                TTSSelectionView()
                    .environmentObject(apiService)
            }
            .alert("????", isPresented: $showLogoutAlert) {
                Button("??", role: .cancel) { }
                Button("??", role: .destructive) {
                    handleLogout()
                }
            } message: {
                Text("?????????")
            }
            .alert("????", isPresented: $showClearLogsAlert) {
                Button("??", role: .cancel) { }
                Button("??", role: .destructive) {
                    LogManager.shared.clearLogs()
                }
            } message: {
                Text("???????????")
            }
            .alert("??????", isPresented: $showClearCacheAlert) {
                Button("??", role: .cancel) { }
                Button("??", role: .destructive) {
                    apiService.clearLocalCache()
                }
            } message: {
                Text("?????????????????")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = logFileURL {
                    ShareSheet(items: [url])
                }
            }
            .task {
                await loadTTSName()
            }
            .onChange(of: preferences.selectedTTSId) { _ in
                Task {
                    await loadTTSName()
                }
            }
            .onChange(of: preferences.narrationTTSId) { _ in
                Task {
                    await loadTTSName()
                }
            }
            .onChange(of: preferences.dialogueTTSId) { _ in
                Task {
                    await loadTTSName()
                }
            }
            .onChange(of: preferences.speakerTTSMapping) { _ in
                Task {
                    await loadTTSName()
                }
            }
        }
    }

    @ViewBuilder
    private var userSection: some View {
        Section(header: Text("????")) {
            HStack {
                Text("???")
                Spacer()
                Text(preferences.username)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("??????")
                    Spacer()
                    Text(preferences.serverURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if !preferences.publicServerURL.isEmpty {
                    HStack {
                        Text("?????")
                            .font(.caption)
                        Spacer()
                        Text(preferences.publicServerURL)
                            .font(.caption2)
                            .foregroundColor(.green)
                            .lineLimit(1)
                    }
                }
            }

            Button(action: { showLogoutAlert = true }) {
                HStack {
                    Spacer()
                    Text("????")
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var readingSection: some View {
        Section(header: Text("????")) {
            HStack {
                Text("????")
                Spacer()
                Text("\(Int(preferences.fontSize))")
            }
            Slider(value: $preferences.fontSize, in: 12...30, step: 1)

            HStack {
                Text("???")
                Spacer()
                Text("\(Int(preferences.lineSpacing))")
            }
            Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
        }
    }

    @ViewBuilder
    private var ttsSection: some View {
        Section(header: Text("????")) {
            Button(action: { showTTSSelection = true }) {
                HStack {
                    Text("TTS ??")
                        .foregroundColor(.primary)
                    Spacer()
                    if preferences.selectedTTSId.isEmpty && preferences.narrationTTSId.isEmpty {
                        Text("???")
                            .foregroundColor(.orange)
                    } else {
                        Text(ttsSummary.isEmpty ? "???" : ttsSummary)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("??")
                Spacer()
                Text(String(format: "%.0f", preferences.speechRate))
            }
            Slider(value: $preferences.speechRate, in: 5...50, step: 1)

            Text("???? 5-50 (?? 10-20)")
                .font(.caption)
                .foregroundColor(.secondary)

            Stepper(value: $preferences.ttsPreloadCount, in: 0...50) {
                HStack {
                    Text("????")
                    Spacer()
                    Text("\(preferences.ttsPreloadCount) ?")
                        .foregroundColor(.secondary)
                }
            }

            Text("?????????????????????????????????? 10-20 ??")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var replaceRuleSection: some View {
        Section(header: Text("????")) {
            NavigationLink(destination: ReplaceRuleListView()) {
                Text("??????")
            }
        }
    }

    @ViewBuilder
    private var bookshelfSection: some View {
        Section(header: Text("????")) {
            Toggle("??????", isOn: $preferences.bookshelfSortByRecent)
            Text("?????????????????????????")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        Section(header: Text("????")) {
            HStack {
                Text("????")
                Spacer()
                Text("\(LogManager.shared.getLogCount()) ?")
                    .foregroundColor(.secondary)
            }

            Button(action: exportLogs) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("????")
                    Spacer()
                }
                .foregroundColor(.blue)
            }

            Button(action: { showClearLogsAlert = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("????")
                    Spacer()
                }
                .foregroundColor(.red)
            }

            Button(action: { showClearCacheAlert = true }) {
                HStack {
                    Image(systemName: "trash.circle")
                    Text("??????")
                    Spacer()
                }
                .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("???????: http://192.168.1.100:8080")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("???? HttpTTS ??????")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                Spacer()
            }
        }
    }

    private func handleLogout() {
        preferences.logout()
        dismiss()
    }

    private func exportLogs() {
        if let url = LogManager.shared.exportLogs() {
            logFileURL = url
            showShareSheet = true
            LogManager.shared.log("??????: \(url.lastPathComponent)", category: "??")
        }
    }

    private func loadTTSName() async {
        let narratorId = preferences.narrationTTSId.isEmpty ? preferences.selectedTTSId : preferences.narrationTTSId
        let dialogueId = preferences.dialogueTTSId.isEmpty ? narratorId : preferences.dialogueTTSId

        guard !narratorId.isEmpty else {
            ttsSummary = ""
            return
        }

        do {
            let ttsList = try await apiService.fetchTTSList()

            func name(for id: String) -> String? {
                ttsList.first(where: { $0.id == id })?.name
            }

            var parts: [String] = []
            let narratorName = name(for: narratorId)
            if let narratorName {
                parts.append("??: \(narratorName)")
            }

            if let dialogueName = name(for: dialogueId), dialogueName != narratorName {
                parts.append("??: \(dialogueName)")
            }

            if !preferences.speakerTTSMapping.isEmpty {
                parts.append("??? \(preferences.speakerTTSMapping.count) ?")
            }

            ttsSummary = parts.joined(separator: " / ")
        } catch {
            print("?? TTS ????: \(error)")
        }
    }
}

// MARK: - ????
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
