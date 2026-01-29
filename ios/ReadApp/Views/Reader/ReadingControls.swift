import SwiftUI
import UniformTypeIdentifiers

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
    let onShowFontSettings: () -> Void

    var body: some View {
        VStack(spacing: ReaderConstants.Controls.barSpacing) {
            // 第一行：播放进度与定时
            HStack {
                VStack(alignment: .leading, spacing: ReaderConstants.Controls.rowLabelSpacing) {
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
                        .padding(.horizontal, ReaderConstants.Controls.timerButtonHorizontalPadding)
                        .padding(.vertical, ReaderConstants.Controls.timerButtonVerticalPadding)
                        .background(timerActive ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                        .foregroundColor(timerActive ? .orange : .secondary)
                        .cornerRadius(ReaderConstants.Controls.timerButtonCornerRadius)
                }
            }
            .padding(.horizontal, ReaderConstants.Controls.horizontalPadding)

            // 第二行：语速调节
            HStack(spacing: ReaderConstants.Controls.rowSpacing) {
                Image(systemName: "speedometer").font(.caption).foregroundColor(.secondary)
                Slider(value: $preferences.speechRate, in: 50...300, step: 10)
                    .accentColor(.blue)
                Text("\(Int(preferences.speechRate))%")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 45)
            }
            .padding(.horizontal, ReaderConstants.Controls.horizontalPadding)

            // 第三行：核心播放控制
            HStack(spacing: 0) {
                IconButton(icon: "chevron.left.2", label: "上章", action: onPreviousChapter, enabled: currentChapterIndex > 0)
                Spacer()
                IconButton(icon: "backward.fill", label: "上段", action: { ttsManager.previousSentence() }, enabled: ttsManager.currentSentenceIndex > 0)
                Spacer()

                Button(action: onTogglePlayPause) {
                    ZStack {
                        Circle().fill(Color.blue).frame(width: ReaderConstants.Controls.ttsMainButtonSize, height: ReaderConstants.Controls.ttsMainButtonSize)
                        Image(systemName: ttsManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2).foregroundColor(.white)
                    }
                }

                Spacer()
                IconButton(icon: "forward.fill", label: "下段", action: { ttsManager.nextSentence() }, enabled: ttsManager.currentSentenceIndex < ttsManager.totalSentences - 1)
                Spacer()
                IconButton(icon: "chevron.right.2", label: "下章", action: onNextChapter, enabled: currentChapterIndex < chaptersCount - 1)
            }
            .padding(.horizontal, ReaderConstants.Controls.horizontalPadding)

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
                Spacer()
                Button(action: onShowFontSettings) {
                    Label("选项", systemImage: "slider.horizontal.3")
                }
            }
            .font(.caption)
            .padding(.horizontal, ReaderConstants.Controls.secondaryHorizontalPadding)
            .padding(.bottom, ReaderConstants.Controls.ttsRowVerticalPadding)
        }
        .padding(.vertical, ReaderConstants.Controls.barSpacing)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(ReaderConstants.Controls.controlShadowOpacity), radius: ReaderConstants.Controls.controlShadowRadius, y: ReaderConstants.Controls.controlShadowYOffset)
    }
}

struct IconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var enabled: Bool = true

    var body: some View {
        Button(action: action) {
            VStack(spacing: ReaderConstants.Controls.rowLabelSpacing) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.system(size: ReaderConstants.Controls.iconLabelSize))
            }
            .frame(width: ReaderConstants.Controls.iconButtonWidth)
            .foregroundColor(enabled ? .primary : .gray.opacity(0.3))
        }
        .disabled(!enabled)
    }
}

// MARK: - 优化的章节导航按钮
struct ChapterNavButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    let isDisabled: Bool
    let isLandscape: Bool

    var body: some View {
        Button(action: action) {
            Group {
                if isLandscape {
                    // 横屏：全宽填充，比例布局
                    HStack(spacing: ReaderConstants.Controls.rowSpacing) {
                        Image(systemName: icon).font(.system(size: 18, weight: .bold))
                        Text(title).font(.headline).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity) // 强制填满父容器分配的空间
                } else {
                    // 竖屏：保持固定宽度
                    VStack(spacing: ReaderConstants.Controls.rowLabelSpacing + 2) {
                        Image(systemName: icon).font(.title2.weight(.bold))
                        Text(title).font(.system(size: ReaderConstants.Controls.iconLabelSize + 1, weight: .bold))
                    }
                    .frame(width: ReaderConstants.Controls.chapterButtonWidthPortrait)
                }
            }
            .frame(height: isLandscape ? ReaderConstants.Controls.chapterButtonHeightLandscape : ReaderConstants.Controls.chapterButtonHeightPortrait)
            .background(Color.primary.opacity(isDisabled ? 0.03 : 0.1))
            .cornerRadius(isLandscape ? ReaderConstants.Controls.chapterButtonCornerLandscape : ReaderConstants.Controls.chapterButtonCornerPortrait)
        }
        .foregroundColor(isDisabled ? .secondary.opacity(0.3) : .primary)
        .disabled(isDisabled)
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
        HStack(spacing: isForceLandscape ? 12 : 0) {
            // 左侧：上一章 (显式扩展以实现比例布局)
            ChapterNavButton(
                icon: "chevron.left",
                title: "上一章",
                action: onPreviousChapter,
                isDisabled: currentChapterIndex <= 0,
                isLandscape: isForceLandscape
            )
            .frame(maxWidth: isForceLandscape ? .infinity : nil)
            
            if !isForceLandscape { Spacer(minLength: 0) }

            // 中间：核心功能区 (横屏时固定宽度)
            HStack(spacing: isForceLandscape ? 25 : 10) {
                Button(action: onShowChapterList) {
                    VStack(spacing: ReaderConstants.Controls.rowLabelSpacing) {
                        Image(systemName: "list.bullet").font(.title3)
                        Text("目录").font(.system(size: ReaderConstants.Controls.iconLabelSize))
                    }
                    .frame(width: ReaderConstants.Controls.iconButtonWidth, height: ReaderConstants.Controls.iconButtonWidth)
                }
                .foregroundColor(.primary)

                if isMangaMode {
                    Button(action: { withAnimation { isForceLandscape.toggle() } }) {
                        VStack(spacing: ReaderConstants.Controls.rowLabelSpacing) {
                            Image(systemName: isForceLandscape ? "iphone.smartrotate.forward" : "iphone.landscape").font(.title3)
                            Text(isForceLandscape ? "竖屏" : "横屏").font(.system(size: ReaderConstants.Controls.iconLabelSize))
                        }
                        .frame(width: ReaderConstants.Controls.iconButtonWidth, height: ReaderConstants.Controls.iconButtonWidth)
                    }
                    .foregroundColor(isForceLandscape ? .blue : .primary)
                } else {
                    Button(action: onToggleTTS) {
                        VStack(spacing: ReaderConstants.Controls.rowLabelSpacing - 2) {
                            Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 28))
                            Text("听书").font(.system(size: ReaderConstants.Controls.iconLabelSize))
                        }
                        .frame(width: ReaderConstants.Controls.iconButtonWidth, height: ReaderConstants.Controls.iconButtonWidth)
                    }
                    .foregroundColor(.blue)
                }

                Button(action: onShowFontSettings) {
                    VStack(spacing: ReaderConstants.Controls.rowLabelSpacing) {
                        Image(systemName: isMangaMode ? "gearshape" : "slider.horizontal.3").font(.title3)
                        Text("选项").font(.system(size: ReaderConstants.Controls.iconLabelSize))
                    }
                    .frame(width: ReaderConstants.Controls.iconButtonWidth, height: ReaderConstants.Controls.iconButtonWidth)
                }
                .foregroundColor(.primary)
            }
            .frame(width: isForceLandscape ? 180 : nil) 

            if !isForceLandscape { Spacer(minLength: 0) }

            // 右侧：下一章 (显式扩展以实现比例布局)
            ChapterNavButton(
                icon: "chevron.right",
                title: "下一章",
                action: onNextChapter,
                isDisabled: currentChapterIndex >= chaptersCount - 1,
                isLandscape: isForceLandscape
            )
            .frame(maxWidth: isForceLandscape ? .infinity : nil)
        }
        .padding(.horizontal, isForceLandscape ? ReaderConstants.Controls.controlBarHorizontalPaddingLandscape : ReaderConstants.Controls.controlBarHorizontalPaddingPortrait)
        .padding(.vertical, ReaderConstants.Controls.controlVerticalPadding)
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(ReaderConstants.Controls.controlShadowOpacity), radius: ReaderConstants.Controls.controlShadowRadius, y: ReaderConstants.Controls.controlShadowYOffset)
    }
}

struct ReaderOptionsSheet: View {
    @ObservedObject var preferences: UserPreferences
    let isMangaMode: Bool
    @Environment(\.dismiss) var dismiss
    @State private var fontOptions: [ReaderFontOption] = FontManager.shared.availableFonts()
    @State private var showFontImporter = false

    private var verticalSettingsVisible: Bool {
        preferences.readingMode == .vertical || isMangaMode
    }

    private var shouldShowSlider: Bool {
        isMangaMode || !preferences.isInfiniteScrollEnabled
    }

    var body: some View {
        NavigationView {
            Form {
                if !isMangaMode {
                    Section(header: Text("显示设置")) {
                        Picker("阅读模式", selection: $preferences.readingMode) {
                            ForEach(ReadingMode.allCases.filter { $0 != .newHorizontal }) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, ReaderConstants.UI.formSectionPaddingVertical)

                        if preferences.readingMode == .horizontal || preferences.readingMode == .newHorizontal {
                            Picker("翻页方式", selection: $preferences.pageTurningMode) {
                                ForEach(PageTurningMode.allCases) { mode in
                                    Text(mode.localizedName).tag(mode)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: ReaderConstants.UI.formRowSpacing) {
                            Text("字体")
                                .font(.subheadline)
                            Picker("字体", selection: $preferences.readingFontName) {
                                ForEach(fontOptions, id: \.id) { font in
                                    Text(font.displayName).tag(font.id)
                                }
                            }
                            .pickerStyle(.menu)
                            Button("导入字体") { showFontImporter = true }
                                .font(.caption)
                        }

                        VStack(alignment: .leading, spacing: ReaderConstants.UI.formRowSpacing) {
                            Text("字体大小: \(String(format: "%.0f", preferences.fontSize))")
                                .font(.subheadline)
                            Slider(value: $preferences.fontSize, in: 12...30, step: 1)
                        }

                        VStack(alignment: .leading, spacing: ReaderConstants.UI.formRowSpacing) {
                            Text("行间距: \(String(format: "%.0f", preferences.lineSpacing))")
                                .font(.subheadline)
                            Slider(value: $preferences.lineSpacing, in: 4...20, step: 2)
                        }
                    }

                    Section(header: Text("页面布局")) {
                        VStack(alignment: .leading, spacing: ReaderConstants.UI.formRowSpacing) {
                            Text("左右边距: \(String(format: "%.0f", preferences.pageHorizontalMargin))")
                                .font(.subheadline)
                            Slider(value: $preferences.pageHorizontalMargin, in: 0...50, step: 1)
                        }
                    }
                }
                
                if verticalSettingsVisible {
                    Section(header: Text("上下滚动")) {
                        if !isMangaMode {
                            Toggle("开启无限流", isOn: $preferences.isInfiniteScrollEnabled)
                        }

                        if shouldShowSlider {
                            VStack(alignment: .leading, spacing: ReaderConstants.UI.formRowSpacing) {
                                HStack {
                                    Text("切章触发拉伸距离")
                                    Spacer()
                                    Text("\(Int(preferences.verticalThreshold)) pt")
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $preferences.verticalThreshold, in: 50...500, step: 10)
                            }
                            .padding(.vertical, ReaderConstants.UI.formSectionPaddingVertical)
                        }
                    }
                }

                Section(header: Text("夜间模式")) {
                    VStack(alignment: .leading, spacing: ReaderConstants.UI.formHeaderSpacing) {
                        Text("模式切换").font(.subheadline).foregroundColor(.secondary)
                        Picker("夜间模式", selection: $preferences.darkMode) {
                            ForEach(DarkModeConfig.allCases) { config in
                                Text(config.localizedName).tag(config)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, ReaderConstants.UI.formSectionPaddingVertical)
                }

                Section(header: Text("主题")) {
                    Picker("阅读主题", selection: $preferences.readingTheme) {
                        ForEach(ReadingTheme.allCases) { theme in
                            Text(theme.localizedName).tag(theme)
                        }
                    }
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
        .onAppear { fontOptions = FontManager.shared.availableFonts() }
        .fileImporter(isPresented: $showFontImporter, allowedContentTypes: [.font]) { result in
            switch result {
            case .success(let url):
                if let option = FontManager.shared.importFont(from: url) {
                    fontOptions = FontManager.shared.availableFonts()
                    preferences.readingFontName = option.id
                }
            case .failure:
                break
            }
        }
    }
}
