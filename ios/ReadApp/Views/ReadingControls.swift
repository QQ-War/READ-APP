import SwiftUI

// MARK: - Reading Controls
struct TTSControlBar: View {
    @ObservedObject var ttsManager: TTSManager
    @StateObject private var preferences = UserPreferences.shared
    let currentChapterIndex: Int
    let chaptersCount: Int

    let timerRemaining: Int
    let timerActive: Bool

    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onTogglePlayPause: () -> Void
    let onSetTimer: (Int) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // 第一行：播放进度与定时
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("段落进度").font(.caption2).foregroundColor(.secondary)
                    Text("\(ttsManager.currentSentenceIndex + 1) / \(ttsManager.totalSentences)")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                }

                Spacer()

                // 定时按钮
                Menu {
                    Button("取消定时") { onSetTimer(0) }
                    Divider()
                    Button("15 分钟") { onSetTimer(15) }
                    Button("30 分钟") { onSetTimer(30) }
                    Button("60 分钟") { onSetTimer(60) }
                    Button("90 分钟") { onSetTimer(90) }
                } label: {
                    Label(timerActive ? "\(timerRemaining)m" : "定时", systemImage: timerActive ? "timer" : "timer")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(timerActive ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                        .foregroundColor(timerActive ? .orange : .secondary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)

            // 第二行：语速调节
            HStack(spacing: 12) {
                Image(systemName: "speedometer").font(.caption).foregroundColor(.secondary)
                Slider(value: $preferences.speechRate, in: 50...300, step: 10)
                    .accentColor(.blue)
                Text("\(Int(preferences.speechRate))%")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 45)
            }
            .padding(.horizontal, 20)

            // 第三行：核心播放控制
            HStack(spacing: 0) {
                IconButton(icon: "chevron.left.2", label: "上章", action: onPreviousChapter, enabled: currentChapterIndex > 0)
                Spacer()
                IconButton(icon: "backward.fill", label: "上段", action: { ttsManager.previousSentence() }, enabled: ttsManager.currentSentenceIndex > 0)
                Spacer()

                Button(action: onTogglePlayPause) {
                    ZStack {
                        Circle().fill(Color.blue).frame(width: 56, height: 56)
                        Image(systemName: ttsManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2).foregroundColor(.white)
                    }
                }

                Spacer()
                IconButton(icon: "forward.fill", label: "下段", action: { ttsManager.nextSentence() }, enabled: ttsManager.currentSentenceIndex < ttsManager.totalSentences - 1)
                Spacer()
                IconButton(icon: "chevron.right.2", label: "下章", action: onNextChapter, enabled: currentChapterIndex < chaptersCount - 1)
            }
            .padding(.horizontal, 20)

            // 第四行：功能入口
            HStack {
                Button(action: onShowChapterList) {
                    Label("目录", systemImage: "list.bullet")
                }
                Spacer()
                Button(action: { ttsManager.stop() }) {
                    Label("停止播放", systemImage: "stop.circle")
                        .foregroundColor(.red)
                }
            }
            .font(.caption)
            .padding(.horizontal, 25)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

struct IconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var enabled: Bool = true

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.system(size: 10))
            }
            .frame(width: 44)
            .foregroundColor(enabled ? .primary : .gray.opacity(0.3))
        }
        .disabled(!enabled)
    }
}

struct NormalControlBar: View {
    let currentChapterIndex: Int
    let chaptersCount: Int
    let isMangaMode: Bool
    @Binding var isForceLandscape: Bool
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onShowChapterList: () -> Void
    let onToggleTTS: () -> Void
    let onShowFontSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：翻页与目录
            HStack(spacing: 20) {
                Button(action: onPreviousChapter) {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.title2)
                        Text("上一章").font(.caption2)
                    }
                }.disabled(currentChapterIndex <= 0)

                Button(action: onShowChapterList) {
                    VStack(spacing: 4) {
                        Image(systemName: "list.bullet").font(.title2)
                        Text("目录").font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 中间：功能扩展区（填充空白）
            HStack(spacing: 25) {
                if isMangaMode {
                    // 漫画模式特有按钮
                    Button(action: { withAnimation { isForceLandscape.toggle() } }) {
                        VStack(spacing: 4) {
                            Image(systemName: isForceLandscape ? "iphone.smartrotate.forward" : "iphone.landscape").font(.title2)
                            Text(isForceLandscape ? "竖屏" : "横屏").font(.caption2)
                        }
                    }
                    .foregroundColor(isForceLandscape ? .blue : .primary)
                } else {
                    Button(action: onToggleTTS) {
                        VStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 32)).foregroundColor(.blue)
                            Text("听书").font(.caption2).foregroundColor(.blue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // 右侧：选项与下一章
            HStack(spacing: 20) {
                Button(action: onShowFontSettings) {
                    VStack(spacing: 4) {
                        Image(systemName: isMangaMode ? "gearshape" : "slider.horizontal.3").font(.title2)
                        Text("选项").font(.caption2)
                    }
                }

                Button(action: onNextChapter) {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.title2)
                        Text("下一章").font(.caption2)
                    }
                }.disabled(currentChapterIndex >= chaptersCount - 1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: -2)
    }
}

struct ReaderOptionsSheet: View {
    @ObservedObject var preferences: UserPreferences
    let isMangaMode: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                if !isMangaMode {
                    Section(header: Text("显示设置")) {
                        Picker("阅读模式", selection: $preferences.readingMode) {
                            ForEach(ReadingMode.allCases) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("字体大小: \(String(format: "%.0f", preferences.fontSize))")
                                .font(.subheadline)
                            Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("行间距: \(String(format: "%.0f", preferences.lineSpacing))")
                                .font(.subheadline)
                            Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
                        }
                    }

                    Section(header: Text("页面布局")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("左右边距: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                                .font(.subheadline)
                            Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                        }
                    }
                }

                Section(header: Text("夜间模式")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("模式切换").font(.subheadline).foregroundColor(.secondary)
                        Picker("夜间模式", selection: $preferences.darkMode) {
                            ForEach(DarkModeConfig.allCases) { config in
                                Text(config.localizedName).tag(config)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }

                if isMangaMode {
                    Section(header: Text("高级设置")) {
                        Toggle("强制服务器代理", isOn: $preferences.forceMangaProxy)
                    }
                }
            }
            .navigationTitle("阅读选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
