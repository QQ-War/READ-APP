# ReadApp

ReadApp is a lightweight iOS/Android reading app with source management and TTS.

Chinese README: `README_CN.md`

## Structure
- `ios/`: iOS app (Xcode project)
- `android/`: Android app (Jetpack Compose)
- `design/`: design assets

## Features
- Multi-source reading and source management
- Reading progress sync
- HTTP-based TTS playback
- Reading settings (font size, spacing, margins)
- Chapter list and quick navigation
- iOS/Android reading modes

## TTS-View Sync Rules (iOS)
- TTS starts from the first visible text on the current page; it does not jump back to previous pages for split paragraphs.
- While TTS is playing, the view follows TTS in both horizontal and vertical modes (foreground/background resume supported).
- During manual page/scroll interactions and the cooldown window afterward, TTS auto-follow is suppressed to avoid jitter.
- After the cooldown, if TTS is not within the current page, TTS restarts from the current page start; if it is within the page, playback continues without restart.
- The cooldown duration is configurable in TTS Settings (“TTS follow cooldown”).

## PDF Images & Inline Layout (iOS)
- PDF images use direct `/pdfImage` requests to avoid response parsing errors caused by complex headers.
- Inline images are rendered via TextKit 2 `NSTextAttachment`, keeping TTS offsets and paging behavior stable.

## Build
- iOS: open `ios/ReadApp.xcodeproj` in Xcode
- Android: open `android/` in Android Studio

## Quick Start
This project includes both iOS and Android clients. Both rely on the Read backend API (`/api/5`).

### Backend
- Deploy the Read backend: https://github.com/autobcb/read
- Configure at least one TTS engine
- Reader backend (optional): https://github.com/hectorqin/reader

#### Read backend setup
- Server base URL should include `/api/5` (example: `http://127.0.0.1:8080/api/5`)

#### Reader backend limitations
The Reader backend does not provide the following APIs, so these features are not available when using `/reader3`:
- TTS management and playback APIs
- Change password
- Clear remote cache

#### Reader backend setup
- Server base URL should include `/reader3` (example: `http://127.0.0.1:8080/reader3`)

### iOS
1. Open the Xcode project:
   ```bash
   cd ios
   open ReadApp.xcodeproj
   ```
2. Select a device and run (a real device is better for background audio tests).
3. On first launch, configure in Settings:
   - Server base URL (example: `http://127.0.0.1:8080/api/5`)
   - Access token
   - TTS engine

### Android
1. Open `android/` in Android Studio.
2. Sync dependencies, then run (Debug).
3. On first launch, configure on the Login screen:
   - Server base URL (example: `http://127.0.0.1:8080/api/5`)
   - Public base URL (optional, for LAN/WAN fallback)
   - Access token

More Android details: `android/README.md`.

## Branches
- `main`: Primary branch (TK2 refactor, active development)
- `TK1`: Snapshot of the previous main before TK2 refactor

## Android signing (debug)
- Debug keystore: `android/keystore/readapp-debug.p12`
- alias: `readappdebug`
- store/key password: `readapp`
- GitHub Actions builds Debug/Unsigned APKs

## Recent Fixes (iOS)
- Fixed page flip to previous chapter incorrectly landing on chapter start.
- Fixed TTS start position sometimes beginning mid-page after pagination changes.
- Fixed TTS resume behavior: if page changes while paused, restart from the new page.
- Fixed pagination clipping/duplicate lines and stabilized cross-chapter cache paging.
