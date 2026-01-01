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

## Build
- iOS: open `ios/ReadApp.xcodeproj` in Xcode
- Android: open `android/` in Android Studio

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
