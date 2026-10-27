# Smalltify 本地构建

这是 giraphant 的 Spotifly fork，供本人从源码构建使用。

- 上游：https://github.com/ralph/Spotifly
- 本人 fork：https://github.com/giraphant/smalltify
- 已抽查的基线：`6077b513205f5a602ec08df0ceb5dcb4f08bc66d`（1.4.0，2026-10-24）。
- 本地源码：`/Users/ramudai/Vibe/smalltify`
- 当前试用版：`/Applications/Smalltify Soloist.app`；旧版 `/Applications/Smalltify.app` 保留。内部构建目标和可执行文件仍名为 Spotifly。两者共享 Bundle ID，不要同时运行。
- 独立 Bundle ID：`io.github.giraphant.smalltify`，独立沙盒容器和 Keychain 服务名称。
- 自己的 Developer ID 签名，保留 App Sandbox、Hardened Runtime。

## 现在的接入方式

2026-10-27 起，应用入口切换到 `Spotifly/Smalltify/` 下的原生 SwiftUI 界面：

- 本人注册的 Client ID + PKCE → 官方 Web API，用于搜索歌曲/专辑/歌单、喜欢的歌曲、收藏专辑、我的歌单及分页。
- 官方 Spotify Soloist → 本机播放、Connect 配对、播放/暂停/切歌/进度/音量/随机、加入队列和硬盘缓存。
- 可以粘贴 `https://open.spotify.com/...` 或 `spotify:...` 播放歌曲、专辑、歌单、episode。
- 上游 Pathfinder/spclient 数据服务、Keymaster 首方 Client ID 和 SwiftLibrespot 播放器仍留在源码中供参考，但新应用入口不实例化它们，也不读取或迁移旧登录。
- 这是可验证的第一版接入，不等同于上游全部功能迁移：没有原首页推荐、歌单编辑、艺术家页、歌词、迷你播放器和完整队列浏览。

### 本人需要完成的设置

1. 在 [Developer Dashboard](https://developer.spotify.com/dashboard) 的应用设置中添加 Redirect URI：`http://127.0.0.1/login`，**不带端口**。Spotify 官方允许 loopback URI 在授权请求中动态添加端口。
2. 在 Smalltify「设置与连接」填写该应用的 **Client ID**，点击「登录 Spotify 文库」，在浏览器授权。**不需要 Client Secret**。当前只申请 `user-library-read playlist-read-private playlist-read-collaborative`。
3. 在 Dashboard 单独生成 **Soloist API Key**（Premium），在 Smalltify 本地安全输入框填写，选择缓存上限（默认 2 GB），保存并启动。
4. 首次在官方 Spotify 的设备列表选择 **Smalltify**。文库与播放器使用同一 Spotify 账号。配对后 Soloist 保留会话，可关闭官方客户端。
5. 验证搜索、自有歌单、音频输出、重启后恢复配对及重复播放缓存。没有真实账号验收前，不宣称播放和无损已经通过。

Soloist 能播放歌单 URI，但不提供文库浏览 API。官方 Web API 的 `/playlists/{id}/items` 当前仅允许读取自己拥有或参与协作的歌单内容；其他歌单可能返回 403。直接播放链接是另一条入口，不保证解除浏览限制。

Soloist 宣布支持无损，但当前 CLI 没有音质参数，WebSocket 也没有当前流的码率/格式字段。本版不显示虚假的“当前无损”标记；实际选到的音质仍待配对后验证。硬盘缓存由 Soloist 管理，不提供离线下载或音频文件导出。

## 构建与二进制固定

需要 Xcode 27+、macOS 27+、Apple Silicon。`make build` 编译、校验本地 Soloist、复制到本机 app、签名，产物：
`build/DerivedData/Build/Products/Release/Spotifly.app`。

`Makefile.local` 保存本机签名身份，不入 Git。不要运行上游 `release.sh`。
构建不下载发行包、不执行 git pull、不自动更新依赖或 Soloist。新界面只使用 Apple SDK。
上游 vendored libogg/libvorbis 源码仍编译但不用于当前播放路径；无远端 Swift Package 依赖。

Soloist 必须由使用者从 [官方页面](https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates) 下载到本机。当前固定：

- 文件：`build/soloist/soloist`（整个 build 目录被 Git 忽略）
- 下载来源：`https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz`
- 版本：`1.3.10.19`，build `1793080877` / `20261027` / `g19412df6ea`
- 可执行文件 SHA-256：`3317fccefe7ea2379f9caad6d0c9daddecf69f82736d874c68fd4f464d5aab94`
- Spotify 原签名：`com.spotify.soloist`，Team ID `2FNC3A47ZF`

从官方解压出的 `soloist`、`THIRD_PARTY_LICENSES.txt` 放入 `build/soloist/`。构建脚本和运行时均检查摘要，校验原始 Spotify 签名；不会重签官方可执行文件。官方的 latest 下载将来变化时，摘要检查会失败，需要手动审查更新并同时更新脚本及运行时固定值。

**此含 Soloist 的 app 仅用于本人本机安装，不发布到 GitHub Release 或 Homebrew。** 官方不允许直接再分发 Soloist 二进制；源码仓库不包含该文件。构建约 90 天到期，退出码 10 会提示更新。没有后台自动更新器。

## 凭据与本地控制边界

- Web API 令牌和 Soloist API Key 使用新 Keychain 服务 `io.github.giraphant.smalltify.official.v1`，不记录到日志或 Git。
- Web API 只向 `https://api.spotify.com/v1/` 发送 bearer；分页 URL 校验精确主机、协议、端口，不允许跨域 HTTP 重定向。刷新合并并发请求，401 仅重试一次，429 遵守 Retry-After。
- Soloist 的官方 CLI **要求把 key 放在进程参数中**。本版从 Keychain 读取后通过 `Process.arguments` 传入，不经过 shell；这并不能防止同一用户有权限的进程查看参数。不要把进程命令行粘贴到公开日志。
- Soloist 会自行持久化配对会话，其格式由 Spotify 管理，不能承诺其全部放在 Keychain。数据目录权限为 0700：沙盒容器内 `Data/Library/Application Support/Smalltify/Soloist`；缓存在 `Data/Library/Caches/Smalltify/Soloist`。
- 只监听 `127.0.0.1`、使用系统分配随机端口，读取本次进程写入的端口文件；退出 Smalltify 时停止子进程。官方 WebSocket **没有认证或 Origin 校验**，loopback 和随机端口降低暴露面，但不是对其他本机进程或恶意网页的完整防护。
- 保留应用沙盒。实测官方 crash reporter 在沙盒内的 Mach 握手被拒绝，但 Soloist 主进程、本机控制连接及正常退出工作；真实账号的音频输出尚待验证。
- fork、本地构建、摘要和签名验证不能证明所有源码/官方二进制无恶意；固定版本避免未经审查地自动跟随变化。

## 验证记录

- 旧版 1.4.0 (9)：源码构建、签名、公证通过，但用户实测首页、搜索和歌单 HTTP 403 `Client/request not allowed`。该版本没有通过功能验收。
- 本次 1.4.0 (10)：Release/arm64 构建通过；新增 19 个测试用例通过。应用约 32 MB，包含本人从官方来源下载且保持 Spotify 签名的 Soloist。
- 用户明确同意上传此构件至 Apple 后，公证 Accepted（submission `e1988704-5256-46a9-97bf-1db39649b612`）；安装后的深度签名校验、stapler validate、Gatekeeper 检查均通过，无 get-task-allow。
- macOS 应用保护拒绝覆盖旧 `/Applications/Smalltify.app`，因此新建安装 `/Applications/Smalltify Soloist.app`，并核对其版本为 build 10、实际运行路径和可见窗口。旧版未被覆盖；额外回滚副本位于 `build/rollback-1.4.0-9/Smalltify.app`。
- 无账户时的窗口启动通过；系统未允许窗口截图，未做截图视觉验收。真实账号的 Web API 授权、配对、播放、缓存复用与实际音质仍等待本人操作验证。
- 使用假 key 和独立沙盒测试包，直接编译当前 `SoloistController`/`SoloistSnapshot` 源码，验证固定摘要/官方签名、启动、随机 loopback 端口发现、WebSocket `auth_state`、命令发送、正常退出。没有读取本人真实账号凭据，也不把未配对视为播放成功。
- 测试覆盖自有 Client ID/PKCE、只读 scopes、分页地址约束、Spotify 链接解析、官方新旧歌单 item 字段、市场 ID、播放状态插值/暂停/清空、并发 token 刷新、401 重试次数和 429 冷却。HTTP 测试只用内存传输和持久化替身。

`make build` 只编译和签名。更改应用后旧公证票据不再适用，需重新公证才能得到相同 Gatekeeper 验证结果。升级安装保留旧 app 回滚副本，直到真实使用验收完成。

## 官方依据

- [Web API redirect URI](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)
- [Web API OpenAPI schema](https://developer.spotify.com/reference/web-api/open-api-schema.yaml)
- [Soloist CLI](https://developer.spotify.com/documentation/soloist/reference/command-line)
- [Soloist WebSocket](https://developer.spotify.com/documentation/soloist/reference/websocket-api)
- [Soloist 介绍与无损能力](https://developer.spotify.com/blog/2026-08-13-introducing-spotify-soloist)
