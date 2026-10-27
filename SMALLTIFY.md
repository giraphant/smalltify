# Smalltify 本地构建

这是 giraphant 的 Spotifly fork，供本人从源码构建使用。

- 上游：https://github.com/ralph/Spotifly
- 本人 fork：https://github.com/giraphant/smalltify
- 已抽查的基线：`6077b513205f5a602ec08df0ceb5dcb4f08bc66d`（1.4.0，2026-10-24）。
- 本地源码：`/Users/ramudai/Vibe/smalltify`
- 安装名称：`/Applications/Smalltify.app`；内部构建目标和可执行文件仍名为 Spotifly。
- 独立 Bundle ID：`io.github.giraphant.smalltify`，独立沙盒容器和 Keychain 服务名称。
- 使用自己的 Developer ID 签名，启用 App Sandbox、Hardened Runtime。

## 构建

需要 Xcode 27+、macOS 27+。执行 `make build`，产物为
`build/DerivedData/Build/Products/Release/Spotifly.app`。
`Makefile.local` 保存本机签名身份，不入 Git。不要运行上游 `release.sh`：它面向上游发布，不是本 fork 的安装流程。

构建不下载上游发行包、不执行 git pull、不自动解析新版本软件包。
当前依赖只有 Apple SDK 和仓库内的 libogg/libvorbis 源码，没有远端 Swift Package 依赖。
没有添加自动更新器，也不通过上游 Homebrew cask 管理本地安装。
将来的上游更新需要先审查 diff，再手动合入和重建；fork 或本地编译不能证明源码无恶意。

## 保留的风险

本次只调整本地构建和身份隔离，没有改变 Spotify 协议或申请权限：

- 上游仍把播放连接可复用凭据存入沙盒中的 `credentials.json`；OAuth 令牌在 Keychain。
- 仍申请较广的 Spotify 权限，并使用 Spotify 官方客户端的 Client ID 和内部接口。
- 本地源码审查不是完整审计，Apple 公证也不能代替源码审查。
- 首次启动需本人在 Spotify 官网授权；授权和实际音频播放需登录后再验证。

独立应用标识意味着不自动继承官方 Spotify 或上游 Spotifly 的登录数据。

## 本次安装验证（2026-10-27）

- Xcode 27.1 / arm64 / Release 构建成功；安装版本 1.4.0 (9)。
- 由 Ningxiang Sun 的 Developer ID 签名，明确移除 `get-task-allow` 调试权限。
- Apple 公证通过，票据已附加；安装后的 `codesign --verify --deep --strict` 和 `spctl --assess` 均通过。
- 从 `/Applications/Smalltify.app/Contents/MacOS/Spotifly` 启动并确认进程运行。
- 用当前 KeychainManager 源码、隔离服务名称和假凭据，在同样沙盒权限的签名测试程序中验证保存、读取、删除，全部通过。
- 随后用户完成登录：界面报告首页 HTTP 403 `Client/request not allowed`，用户确认搜索、歌单也失败。当前安装版本不能视为功能验收通过；播放尚未验证。

本机已用现有公证配置完成首次安装。`make build` 只负责编译和签名；每次改变二进制后，旧公证票据不再适用，需要重新公证才能得到同样的 Gatekeeper 验证结果。

## 当前阻塞：Spotify 数据接口拒绝请求

2026-10-27，用户登录后：首页返回 HTTP 403 `Client/request not allowed`，搜索、歌单也失败。当前 fork 未修改 Spotify Client ID、授权流程或 PartnerAPI 请求逻辑；它们沿用已审查的上游基线。

另一个项目维护者在 [Wavekeep v0.3.0 发布说明](https://github.com/PierrunoYT/Wavekeep/releases/tag/v0.3.0) 记录：2026-10-23 Pathfinder 返回同样的拒绝。结合本项目源码，初步判断为内部接口对该请求/客户端的访问限制，尚未通过受控请求实验确定具体触发条件。

后续可评估用本人注册的 Client ID + PKCE 接入官方 Web API，恢复其支持的搜索和文库能力。此方案需要新的授权与数据适配，并不能保证恢复内部首页推荐或所有播放功能。不要通过更换随机 Client ID、拷贝浏览器令牌或无限重试规避拒绝。
