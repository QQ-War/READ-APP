# ReadApp

ReadApp 是轻阅读后端（https://github.com/autobcb/read）的 iOS/Android 客户端实现，聚焦“听书 + 段落级阅读”的体验。

## 目录结构
- `ios/`：iOS 客户端（Xcode 项目源码）
- `android/`：Android 客户端（Jetpack Compose）
- `design/`：设计稿与说明

## 主要能力
- 账号登录、服务端地址配置（支持公网与内网回退）
- 书架与章节浏览、阅读进度同步
- HTTP TTS 听书（段落级播放、自动跳段）
- 预加载与缓存策略（提升段落切换流畅度）
- 后台播放与系统媒体控制

## 入口说明
- iOS：`ios/`，使用 Xcode 打开 `ReadApp.xcodeproj`
- Android：`android/`，使用 Android Studio 打开该目录

更多细节见：
- `快速开始.md`
- `android/README.md`
