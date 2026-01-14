import Combine
import SwiftUI

// 段落缩进：2个全角空格
let paragraphIndentLength = 2

final class ReaderSettingsStore: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()
    private let preferences: UserPreferences
    private var cancellable: AnyCancellable?

    init(preferences: UserPreferences) {
        self.preferences = preferences
        self.cancellable = preferences.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var fontSize: CGFloat {
        get { preferences.fontSize }
        set { preferences.fontSize = newValue }
    }

    var lineSpacing: CGFloat {
        get { preferences.lineSpacing }
        set { preferences.lineSpacing = newValue }
    }

    var readingMode: ReadingMode {
        get { preferences.readingMode }
        set { preferences.readingMode = newValue }
    }

    var pageHorizontalMargin: CGFloat {
        get { preferences.pageHorizontalMargin }
        set { preferences.pageHorizontalMargin = newValue }
    }

    var pageInterSpacing: CGFloat {
        get { preferences.pageInterSpacing }
        set { preferences.pageInterSpacing = newValue }
    }

    var pageTurningMode: PageTurningMode {
        get { preferences.pageTurningMode }
        set { preferences.pageTurningMode = newValue }
    }

    var darkMode: DarkModeConfig {
        get { preferences.darkMode }
        set { preferences.darkMode = newValue }
    }

    var lockPageOnTTS: Bool {
        get { preferences.lockPageOnTTS }
        set { preferences.lockPageOnTTS = newValue }
    }

    var manualMangaUrls: Set<String> {
        get { preferences.manualMangaUrls }
        set { preferences.manualMangaUrls = newValue }
    }

    var isInfiniteScrollEnabled: Bool {
        get { preferences.isInfiniteScrollEnabled }
        set { preferences.isInfiniteScrollEnabled = newValue }
    }

    var verticalThreshold: CGFloat {
        get { preferences.verticalThreshold }
        set { preferences.verticalThreshold = newValue }
    }

    var verticalDampingFactor: CGFloat {
        get { preferences.verticalDampingFactor }
        set { preferences.verticalDampingFactor = newValue }
    }

    var mangaMaxZoom: CGFloat {
        get { preferences.mangaMaxZoom }
        set { preferences.mangaMaxZoom = newValue }
    }

    var infiniteScrollSwitchThreshold: CGFloat {
        get { preferences.infiniteScrollSwitchThreshold }
        set { preferences.infiniteScrollSwitchThreshold = newValue }
    }

    var ttsFollowCooldown: TimeInterval {
        get { preferences.ttsFollowCooldown }
        set { preferences.ttsFollowCooldown = newValue }
    }

    var forceMangaProxy: Bool {
        get { preferences.forceMangaProxy }
        set { preferences.forceMangaProxy = newValue }
    }
}
