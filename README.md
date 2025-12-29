# ReadApp

ReadApp is a lightweight iOS/Android reading app with source management and TTS.  
ReadApp 是一个轻量的 iOS/Android 阅读应用，支持书源管理与 TTS。

## Structure | 项目结构
- `ios/`: iOS app (Xcode project) | iOS 应用（Xcode 项目）
- `android/`: Android app (Jetpack Compose) | Android 应用（Jetpack Compose）
- `design/`: design assets | 设计资源

## Features | 功能
- Multi-source reading and source management | 多书源阅读与书源管理
- Reading progress sync | 阅读进度同步
- HTTP-based TTS playback | 基于 HTTP 的 TTS 播放
- Reading settings (font size, spacing, margins) | 阅读设置（字号、行距、页边距）
- Chapter list and quick navigation | 目录与快速跳转
- iOS/Android reading modes | iOS/Android 阅读模式

## Build | 构建
- iOS: open `ios/ReadApp.xcodeproj` in Xcode | iOS：用 Xcode 打开 `ios/ReadApp.xcodeproj`
- Android: open `android/` in Android Studio | Android：用 Android Studio 打开 `android/`

## Android signing (debug) | Android 签名（Debug）
- Debug keystore: `android/keystore/readapp-debug.p12` | Debug keystore：`android/keystore/readapp-debug.p12`
- alias: `readappdebug` | alias：`readappdebug`
- store/key password: `readapp` | store/key 密码：`readapp`
- GitHub Actions builds Debug/Unsigned APKs | GitHub Actions 会构建 Debug/Unsigned APK

## Recent Fixes (iOS) | 近期修复（iOS）
- Fixed page flip to previous chapter incorrectly landing on chapter start. | 修复翻到上一章时落到章节开头的问题。
- Fixed TTS start position sometimes beginning mid-page after pagination changes. | 修复分页后 TTS 起读位置偶尔从页面中间开始的问题。
- Fixed TTS resume behavior: if page changes while paused, restart from the new page. | 修复 TTS 暂停期间翻页后继续播放不从新页开始的问题。
