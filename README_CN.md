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

## 快速开始
项目包含 iOS 与 Android 两个客户端，均依赖轻阅读后端 API（`/api/5`）。

### 后端准备
- 部署轻阅读后端：https://github.com/autobcb/read
- 在后端配置至少一个 TTS 引擎
- Reader 后端（可选）：https://github.com/hectorqin/reader

#### Read 后端配置
- 服务端地址需要包含 `/api/5`（示例：`http://127.0.0.1:8080/api/5`）

#### Reader 后端限制
由于 Reader 服务端没有提供以下接口，使用 `/reader3` 时这些功能不可用：
- TTS 管理与播放相关接口
- 修改密码
- 清理远端缓存

#### Reader 后端配置
- 服务端地址需要包含 `/reader3`（示例：`http://127.0.0.1:8080/reader3`）

### iOS
1. 打开 Xcode 项目：
   ```bash
   cd ios
   open ReadApp.xcodeproj
   ```
2. 选择设备并运行（真机更适合验证后台播放）。
3. 首次启动在设置页配置：
   - 服务端地址（示例：`http://127.0.0.1:8080/api/5`）
   - 访问令牌（accessToken）
   - TTS 引擎

### Android
1. 用 Android Studio 打开 `android/` 目录。
2. 首次同步依赖完成后直接运行（Debug）。
3. 首次启动在登录页填写：
   - 服务端地址（示例：`http://127.0.0.1:8080/api/5`）
   - 公网地址（可选，用于内外网回退）
   - 访问令牌（accessToken）

更多 Android 细节见 `android/README.md`。

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
- 修复分页裁切/重复行问题，并稳定跨章缓存分页。
