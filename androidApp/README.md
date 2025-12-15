# ReadApp Android

这是一个基于 Jetpack Compose 的轻阅读第三方 Android 客户端移植版本，复用与 iOS 端一致的后端 API（/api/5）。目前提供登录、服务器地址配置、书架浏览、章节阅读与 HTTP TTS 朗读，并保留与 iOS 相同的公网/局域网双地址回退策略。

## 已实现
- 账号密码登录（支持公网备选地址自动回退）
- 服务器地址与访问令牌的 DataStore 本地持久化
- 书架列表展示、手动刷新
- 章节目录加载与章节正文阅读
- HTTP TTS 朗读当前章节（可选引擎、语速与预载章节数）
- TTS 播放使用 MediaSession 前台服务，支持后台播放与锁屏媒体控制
- 听书体验：支持段落分段朗读、段落高亮、章节名朗读、段落级进度条与跳转、预载章节提示色块
- 沉浸模式与段落列表阅读视图，可配合耳机拔出自动暂停
- 段落末尾预载提示与即将跳转下一章的高亮标记，章节 nearing 结束时自动预取下一章并平滑衔接朗读
- 动态段落背景与渐变高亮，沉浸模式下仍保留段落焦点动画与预载提示
- 书架工具：搜索、最近阅读排序、正序/倒序切换与缓存清理入口
- Compose Material 3 轻量化 UI 主题
- 阅读偏好：字体大小、行间距调节与“最近阅读排序”开关（DataStore 持久化）

## 与 iOS 版的差异（尚未移植）
- 书架工具：尚缺服务端缓存清理/同步诊断，已支持搜索、正序/倒序切换与最近阅读排序。
- 阅读与听书体验：仍缺少 iOS 的段落级沉浸动画特效与更多自定义主题，但已补齐预载提示、章节末尾高亮跳转与动态段落背景。
- 系统整合：已支持耳机拔出自动暂停、音频焦点恢复自动续播与 MediaSession 控制，但缺少蓝牙耳机自定义按键映射等深度整合。
- 调试与缓存管理：iOS 提供日志导出/清空、本地章节缓存清除等工具；安卓端暂无日志导出或缓存清理界面。

## 目录结构
- `app/src/main/java/com/readapp/android/model`：数据模型，与 iOS 端字段保持一致
- `app/src/main/java/com/readapp/android/data`：Retrofit API 定义、回退仓库、DataStore 封装
- `app/src/main/java/com/readapp/android/ui`：主界面、导航、ViewModel
- `app/src/main/java/com/readapp/android/ui/screens`：登录与书架界面
- `app/src/main/java/com/readapp/android/ui/theme`：Compose 主题定义

## 运行
1. 使用 Android Studio Hedgehog 或更高版本打开 `androidApp` 目录。
2. 在 `app/build.gradle.kts` 中已启用 Compose 与所需依赖，首次同步会自动下载。
3. 运行前在登录页填写服务器地址（默认 `http://127.0.0.1:8080/api/5`），如有公网地址可同时填写，保存后登录即可刷新书架。
