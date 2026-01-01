# ReadApp

ReadApp 是一个轻量的 iOS/Android 阅读应用，支持书源管理与 TTS。

English README: `README.md`

## 项目结构
- `ios/`: iOS 应用（Xcode 项目）
- `android/`: Android 应用（Jetpack Compose）
- `design/`: 设计资源

## 功能
- 多书源阅读与书源管理
- 阅读进度同步
- 基于 HTTP 的 TTS 播放
- 阅读设置（字号、行距、页边距）
- 目录与快速跳转
- iOS/Android 阅读模式

## 构建
- iOS：用 Xcode 打开 `ios/ReadApp.xcodeproj`
- Android：用 Android Studio 打开 `android/`

## 分支说明
- `main`：主分支（TK2 重构版，主要开发）
- `TK1`：旧主分支快照（TK2 重构前的版本）

## Android 签名（Debug）
- Debug keystore：`android/keystore/readapp-debug.p12`
- alias：`readappdebug`
- store/key 密码：`readapp`
- GitHub Actions 会构建 Debug/Unsigned APK

## 近期修复（iOS）
- 修复翻到上一章时落到章节开头的问题。
- 修复分页后 TTS 起读位置偶尔从页面中间开始的问题。
- 修复 TTS 暂停期间翻页后继续播放不从新页开始的问题。
