# Reader 后端支持说明

## Reader API 重点（与 Read 后端差异）
- Reader 采用 `/reader3` 前缀、整合了对书源/章节/阅读的单一端点，客户端需要在基础 URL 上追加 `/reader3`（当前已在登录/设置页通过下拉切换）。
- `reader` 的 `/book/tts` 是在 ReadApp 中唯一可用的 TTS 接口；它只接受 POST JSON，返回 base64 音频。示例请求：

```http
POST https://<host>/reader3/book/tts?accessToken=XXX&v=TIMESTAMP
Content-Type: application/json

{
  "text": "需要合成的段落",
  "type": "httpTTS",
  "voice": "nevermore-local晓晓2自然",
  "pitch": "1",
  "rate": "1",
  "accessToken": "XXX",
  "base64": "1"
}
```

成功响应会返回 `{"isSuccess":true,"errorMsg":"","data":"//Nkx..."}`，`data` 是 base64 字符串，可转成 PCM/MP3 在客户端播放。

## 当前未覆盖的 Read/Reader 接口（待新增 UI/逻辑）
以下内容在现有代码中还没有绑定到任何仓库或视图：

1. **RSS/订阅源管理**（`RssController`）。
   - `read` 提供 `/rss` 系列接口（`/getRssSourcess`, `/editRssSources`, `/topRssSource` 等），`reader` 也包含 RSS 配置。
   - 目前 App 只在 `SourceScreen` 里展示书源列表，没有 RSS 订阅入口。建议新增“订阅源”视图/Tab，支持列出、启用/禁用、排序 RSS 源，并通过 `reader3/rss` 或 `/api/5/rss` 接口完成 CRUD。

2. **书源分组与排序**（`BookGroupController`、`SourceController` 的排位接口）仅在服务端存在，客户端没有对应编辑界面。

3. **书签管理**（`BookMarkController`）。`read` 提供 `/addbookmark`, `/getbookmark`, `/delbookmark` 等接口，当前客户端没有读取/写入书签的 UI，也没有同步机制，同步后续进度可复用现有 `BookDetail`/`ReadingScreen` 状态。

4. **背景/主题资源**（`GroundController`）。`read` 允许上传/切换背景图片、获取分页背景等，UI 里尚未使用可视化界面。

5. **WebSocket/实时推送** (`/ws`, `/rssdebug`) 目前完全无客户端支持。

## 建议的下一步
1. 按 `RssController` 设计一个“订阅源”页面：
   - 展示 RSS 源列表（`/reader3/rss` 或 `/api/5/rss`），可启用/停用/排序。
   - 支持添加/编辑 RSS 源（JSON 内容 + 归属标签）并立即同步。
2. 扩展 `BookSource` 分组控制：加载 `/api/5/bookgroup`，让用户拖拽调整分组/排序。
3. 书签视图可复用现有 `BookDetail` + `SourceSwitchDialog`，通过 `/addbookmark` 等接口保存位置。
4. 如果需要对 Reader 端做更细粒度体验提示，可以把这份文档追加到主 README 里，并补充 `reader` 后端具体的端点列表。
