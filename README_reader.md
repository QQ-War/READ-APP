# Reader 后端支持说明

## Reader API 重点（与 Read 后端差异）
- Reader 采用 `/reader3` 前缀、整合了对书源/章节/阅读的单一端点，客户端需要在基础 URL 上追加 `/reader3`（当前已在登录/设置页通过下拉切换）。
- `reader` 的 `/book/tts`、`/httpTTS/list` 等接口在下方 “TTS 接口” 一节中有更详细的说明。

## TTS 接口

### Reader 后端 (`/reader3`)
Reader 端 exposes 两个主力接口：`httpTTS/list` 用来拉取可用引擎，`book/tts` 用来按照引擎配置合成音频。请求必须附带 `accessToken` 和 `v`（毫秒级时间戳）防止缓存；`book/tts` 的 body 以 JSON 传递当前要朗读的段落、选中的引擎名以及音色参数。

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

成功响应会返回 `{"isSuccess":true,"errorMsg":"","data":"//Nkx..."}`，`data` 是 base64 编码的音频片段，可直接解码播放。

| 接口 | 描述 | 请求 | 返回 |
| --- | --- | --- | --- |
| `GET /reader3/httpTTS/list` | 列出 Reader 端当前可用的 `HttpTTS` 引擎（包含 `id`/`name`/`url` 等字段） | Query：`accessToken`、`v`（毫秒级时间戳） | `{"isSuccess":true,"data":[{id,name,url,...},...],...}` |
| `POST /reader3/book/tts` | 按照上一步选定的引擎生成 base64 音频；客户端只需负责解码播放 | Query：`accessToken`、`v`；Body：`ReaderBookTtsRequest`（`text`、`type` 固定 `httpTTS`、`voice`、`pitch`、`rate`、`accessToken`、`base64`） | `{"isSuccess":true,"data":"//Nkx...","errorMsg":"","totalSentence":null}` |

### Read 后端 (`/api/5`)
Read 端的 `TTsController` 负责 CRUD 和默认配置，`/tts`（GET）则直接返回二进制音频用来播放本地引擎。

| 接口 | 描述 | 请求 | 返回 |
| --- | --- | --- | --- |
| `GET /api/5/getalltts` | 获取当前用户在 Read 后端下保存的 `HttpTTS` 引擎列表 | Query：`accessToken` | `{"isSuccess":true,"data":[HttpTTS,...],...}` |
| `GET /api/5/getDefaultTTS` | 查询默认 TTS 引擎 ID | Query：`accessToken` | `{"isSuccess":true,"data":"<engine-id>",...}` |
| `POST /api/5/addtts` | 新增或更新一个 `HttpTTS` 记录 | Query：`accessToken`；Body：`HttpTTS` JSON（见下表） | `{"isSuccess":true,"data":"<engine-id>",...}` |
| `POST /api/5/deltts` | 删除指定引擎 | Query：`accessToken`、`id` | `{"isSuccess":true,"data":"","errorMsg":""}` |
| `POST /api/5/savettss` | 批量导入/更新 `HttpTTS`（旧称 `savettss` / `upjson`） | Query：`accessToken`；Body：`text/plain` 的 JSON 数组文本 | `{"isSuccess":true,"data":"","errorMsg":""}` |
| `GET /tts` | 播放指定引擎生成的音频 | Query：`accessToken`、`id`（`HttpTTS.id`）、`speakText`、`speechRate` | 二进制音频流（MP3/PCM），可直接交给 TTS 播放器 |

### HttpTTS 数据结构
`HttpTTS` 模型在 iOS/Android 均有定义，客户端无需关心所有字段，常用属性如下：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `String` | 唯一标识；新增时可以为空，会由后端分配 |
| `name` | `String` | 展示名称/引擎名，Reader 的 `book/tts` 需要将该值传给 `voice` |
| `url` | `String` | 用户自建引擎的地址（Read 端用于 `/tts` 请求） |
| `contentType` | `String?` | 指定音频内容类型 |
| `concurrentRate` | `String?` | 并发率控制 |
| `loginUrl`/`loginUi` | `String?` | 自定义引擎的登录页和 UI 配置 |
| `header` | `String?` | 自定义请求头 |
| `enabledCookieJar` | `Bool?` | 是否开启 CookieJar |
| `lastUpdateTime` | `Int64?` | 最后更新时间戳 |

## RSS/订阅源

### Read 后端 (`/api/5`)
Read 后端的 `RssController` 负责同步远程订阅源、启用/禁用以及增删改。客户端在 `RssService` 中使用以下接口，并通过 `RemoteRssSourceManager`/`RssSourcesViewModel` 把远程数据与本地自定义源（支持导入 JSON 文件/字符串）合并展现。

| 接口 | 描述 | 请求 | 返回 |
| --- | --- | --- | --- |
| `GET /api/5/getRssSourcess` | 拉取当前用户的订阅源列表 | Query：`accessToken` | `{"isSuccess":true,"data":{"sources":[...],"can":true},...}` |
| `GET /api/5/stopRssSource` | 启用/禁用远程订阅源 | Query：`accessToken`、`id`、`st`（0/1） | `{"isSuccess":true,"data":"","errorMsg":""}` |
| `POST /api/5/editRssSources` | 保存/更新远程订阅源，需要对 `RssSource` 数据做 JSON 编码 | Query：`accessToken`；Body：`{"json":"<rss json>","id":"<源 id 可选>"}` | `{"isSuccess":true,"data":"<sourceUrl>",...}` |
| `GET /api/5/delRssSource` | 删除远程订阅源 | Query：`accessToken`、`id`（`sourceUrl`） | `{"isSuccess":true,"data":"","errorMsg":""}` |

`RssSourcesResponse` 目前返回 `sources`（数组）和 `can`（布尔）两个字段，`can` 控制 UI 是否允许增删改。`RssSource` 结构如下（客户端还有本地存储的 `customSources` 列表，支持导入/导出 JSON）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `sourceUrl` | `String` | 唯一标识，也作为 `id` |
| `sourceName` | `String?` | 名称 |
| `sourceIcon` | `String?` | 图标地址 |
| `sourceGroup` | `String?` | 归类字段（可用于分组） |
| `loginUrl`/`loginUi` | `String?` | 登录相关配置 |
| `variableComment` | `String?` | 说明字段 |
| `enabled` | `Bool` | 当前启用状态 |

### Reader 后端 (`/reader3`)
Reader 端的 `RssSourceController` 在客户端已通过 `RssService` 的 `fetchRssSources`/`toggleSource` 接口接入，未来可引入 `saveRssSource`/`deleteRssSource` 以完成 UI 上的增删改。

| 接口 | 描述 | 请求 | 返回 |
| --- | --- | --- | --- |
| `GET /reader3/getRssSources` | 拉取 Reader 后端的订阅源（结构与 Read 类似） | Query：`accessToken` | `{"isSuccess":true,"data":{"sources":...,"can":true},...}` |
| `GET /reader3/stopRssSource` | 启用/禁用 Reader 端订阅源 | Query：`accessToken`、`id`、`st` | `{"isSuccess":true,"data":"","errorMsg":""}` |
| `POST /reader3/saveRssSource` | 预留的编辑接口，暂未在 UI 中触发 | Query：`accessToken`；Body：`RssSource` JSON | `{"isSuccess":true,...}` |
| `POST /reader3/deleteRssSource` | 预留的删除接口 | Query：`accessToken`、`id` | `{"isSuccess":true,"data":"","errorMsg":""}` |

客户端同时维护一份 `customSources`，可以通过 `RssSourcesViewModel.importCustomSources` 从本地/网络抓取 JSON，补全网络源之外的自定义列表。启用状态的切换会先请求 `toggleSource`，再同步本地缓存以避免界面闪烁。

## Read/Reader API 现状
为了让开发更清晰地感知客户端与两套后端的呼应，下面按 controller/路由归纳了当前 ReadApp 支持的主要接口与仍在排期的点：

### Read 后端 (`/api/5`)
- **Auth + 用户**：`login`, `getUserInfo`, `changePassword` 都通过 `AuthRepository`/`ReadRepository` 实现。
- **书架/图书/章节**：`BookshelfController`, `BookController`, `ReadController` 提供书架、章节列表/内容、搜索、书源设置、阅读进度等接口，客户端在 `ReadRepository`/`ChapterContentRepository` 中均有调用。
- **书源**：`SourceController` 的 `getBookSources`、`saveBookSource`、`toggleBookSource`、`delbookSource` 等完整写入 `SourceRepository`，也支撑了设置页的书源管理。
- **RSS/订阅源**：`RssController` 的 `getRssSourcess/editRssSources/stopRssSource/delRssSource` 通过 `RemoteRssSourceManager` + `RssViewModel` + `RssSourcesScreen` 提供 CRUD、启用/禁用。
- **替换/净化规则**：`ReplaceRuleController` 的 `getReplaceRules`、`saveRule(s)`、`delete` 走 `ReadRepository` + 相关 UI。
- **TTS**：`TTsController` 的 `/getalltts`, `/addtts`, `/deltts`, `/savettss` 继续支持 Read 端，目前 Android/iOS 均在此基础上接入 TTS 引擎列表、播放控制。
- **未覆盖**：
  1. `BookGroupController` 的分组/排序 API 尚未在客户端 UI 露出。
  2. `BookMarkController` 的书签 CRUD（`addbookmark/getbookmark/delbookmark`）还没有同步机制。
  3. `GroundController` 的背景/主题上传与分页背景未在 App 端使用。
  4. `WebSocket`（`/ws`, `/rssdebug`）与 `ItemController` 等调试接口仍无客户端实现。

### Reader 后端 (`/reader3`)
- **书籍/章节/搜索**：`BookController` 提供 `getBookshelf/getChapterList/getBookContent/saveBookProgress/searchBook` 等基础阅读接口，已经在 `RemoteDataSourceFactory` + `ReadRepository` 里接入。
- **书源**：`BookSourceController` 拥有导入/导出、文件读写、设为默认等丰富接口；当前客户端仅使用 `getBookSources`/`setBookSource`，其余高级路由可考虑后续同步。
- **RSS**：`RssSourceController` 的 `getRssSources/saveRssSource/deleteRssSource` 可继续扩展为 Reader 的订阅源页，目前仍未绑定。
- **替换规则**：`ReplaceRuleController` 的 `getReplaceRules`, `saveReplaceRule`, `deleteReplaceRule` 已通过 `ReadRepository` 覆盖，兼容 Reader。
- **TTS**：`httpTTS/list` + `book/tts` 已接入 Reader 模式，让播放逻辑兼容双端。
- **用户/管理**：`UserController`（`login`, `logout`, `getUserInfo`, `save/getUserConfig`）在 ReadApp 中使用得较少，管理类（`addUser/resetPassword/deleteUsers`）尚未触达。
- **WebDAV/备份**：`WebdavController` 提供文件列表、上传/下载、备份/恢复等接口，客户端尚无对接。
- **Bookmarks**：`BookmarkController`（`getBookmarks`, `saveBookmark(s)`, `deleteBookmark(s)`）目前在客户端未实现。
- **其他未消费**：`searchBookMulti`/`exploreBook` 的增强搜索、`importBookPreview`、`bookSourceDebugSSE/cacheBookSSE`、`exportBook`, `getWebdavFile` 等辅助接口均可列为后续扩展。

## 接口差距/后续考虑
- `BookGroupController`, `BookMarkController`, `GroundController`（Read 系）仍是提效重点，建议在书架或详情页加入口。
- Reader 端的 `RssSourceController`、`WebdavController`、`BookmarkController`、`bookSourceDebugSSE` 等也值得在多平台保持同步，尤其 `Webdav`/`Backup` 能支持数据迁移。
- 如需深度覆盖，可以把上述模块拆分成独立的页/权限（例如 RSS 管理、书源组、书签面板、WebDAV 任务监控），按 priority 迭代。
