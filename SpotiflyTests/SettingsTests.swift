import Foundation
@testable import Spotifly
import Testing

@MainActor struct SettingsTests {
    let id = "1234567890123456789012"

    @Test func clientIDValidationHandlesLengthAndASCIIHex() {
        #expect(ClientIDValidation("  ") == .empty)
        #expect(ClientIDValidation("0123456789abcdef0123456789ABCDEF") == .valid)
        #expect(ClientIDValidation(" 0123456789abcdef0123456789ABCDEF\n") == .valid)
        #expect(ClientIDValidation("3f9a1c0e7b2d") == .invalid("Client ID 应为 32 位十六进制字符，当前只有 12 位。"))
        #expect(ClientIDValidation(String(repeating: "g", count: 32)) != .valid)
        #expect(ClientIDValidation(String(repeating: "ａ", count: 32)) != .valid)
        #expect(ClientIDValidation(String(repeating: "a", count: 33)) != .valid)
    }

    @Test func buildExpiryUsesNinetyDaysAndRoundsUp() throws {
        let build = try #require(SoloistBuild("1.3.10.19 · 2026-10-27"))
        #expect(build.version == "1.3.10.19")
        #expect(build.daysRemaining(at: build.date) == 90)
        #expect(build.daysRemaining(at: build.date.addingTimeInterval(89 * 86400 + 1)) == 1)
        #expect(build.daysRemaining(at: build.date.addingTimeInterval(90 * 86400)) == 0)
        #expect(build.daysRemaining(at: build.date.addingTimeInterval(91 * 86400)) == -1)
        #expect(SoloistBuild("unknown") == nil)
        #expect(SoloistBuild("1.0 · no date") == nil)
    }

    @Test func authStatesHaveDeliberatePrecedence() {
        let valid = String(repeating: "a", count: 32)
        func status(_ signedIn: Bool = false, busy: Bool = false, expired: Bool = false, error: String? = nil, client: String? = nil) -> SettingsStatus {
            .authorization(clientID: client ?? valid, signedIn: signedIn, authorizing: busy, expired: expired, name: "测试用户", error: error)
        }
        #expect(status().title == "未授权")
        #expect(status(true).title == "已授权 · 测试用户")
        #expect(status(true, busy: true, expired: true, error: "old").title == "正在浏览器中授权…")
        #expect(status(true, expired: true).title == "登录已过期")
        #expect(status(error: "端口被占用").message == "端口被占用")
        #expect(status(client: "123").title == "Client ID 格式不对")
    }

    @Test func playerAndPairingStatesCoverLifecycle() {
        func state(running: Bool = false, starting: Bool = false, stopping: Bool = false, key: Bool = true, expired: Bool = false, error: String? = nil) -> String {
            SettingsStatus.player(running: running, starting: starting, stopping: stopping, hasKey: key, expired: expired, error: error).title
        }
        #expect(state() == "已停止")
        #expect(state(running: true) == "运行中")
        #expect(state(starting: true) == "启动中…")
        #expect(state(starting: true, stopping: true) == "停止中…")
        #expect(state(key: false) == "未填写 API Key")
        #expect(state(expired: true, error: "退出") == "版本已过期")
        #expect(state(error: "连接中断") == "播放器出错")
        #expect(SettingsStatus.pairing(running: false, starting: false, stopping: false, loggedIn: false).title == "等待播放器")
        #expect(SettingsStatus.pairing(running: true, starting: true, stopping: false, loggedIn: false).title == "等待播放器")
        #expect(SettingsStatus.pairing(running: true, starting: false, stopping: false, loggedIn: false).title == "等待配对")
        #expect(SettingsStatus.pairing(running: true, starting: false, stopping: false, loggedIn: true).title == "已配对")
    }

    @Test func supportedLinksBuildMarketRequests() throws {
        for kind in ["track", "album", "playlist", "episode"] {
            let link = try #require(SpotifyLink("https://open.spotify.com/intl-zh/\(kind)/\(id)?si=shared"))
            #expect(link.uri == "spotify:\(kind):\(id)")
            let url = try link.url
            #expect(url.path == "/v1/\(kind)s/\(id)")
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "market", value: "from_token")) == true)
        }
        for input in ["https://example.com/album/\(id)", "https://open.spotify.com.evil.test/album/\(id)", "http://open.spotify.com/album/\(id)", "spotify:artist:\(id)", "spotify:track:short"] {
            #expect(SpotifyLink(input) == nil)
        }
    }

    @Test func previewsPreserveReturnedMarketIdentityAndEpisodeShow() throws {
        let link = try #require(SpotifyLink("spotify:track:\(id)"))
        let marketURI = "spotify:track:abcdefghijklmnopqrstuv"
        let data = try JSONSerialization.data(withJSONObject: ["uri": marketURI, "type": "track", "name": "歌曲",
                                                               "linked_from": ["uri": link.uri], "artists": [["name": "歌手"]]])
        let preview = try link.preview(data)
        #expect(preview.item.uri == marketURI)
        #expect(preview.line == "歌曲 · 歌曲 · 歌手")
        let episode = try #require(SpotifyLink("spotify:episode:\(id)"))
        let episodeData = try JSONSerialization.data(withJSONObject: ["uri": episode.uri, "name": "海边来信", "type": "episode", "show": ["name": "潮汐播客"]])
        #expect(try episode.preview(episodeData).line == "播客单集 · 海边来信 · 潮汐播客")
        #expect(throws: SmalltifyError.self) { try episode.preview(data) }
    }

    @Test func staleMetadataCannotReplaceEditedInput() async throws {
        let recognition = LinkRecognition()
        recognition.update("spotify:album:\(id)")
        let gate = SettingsResponseGate()
        let task = Task {
            await recognition.load(fetch: { _ in await gate.response() }, report: { _ in Issue.record("Unexpected error") })
        }
        await gate.waitUntilRequested()
        recognition.update("https://example.com/invalid")
        let response = try JSONSerialization.data(withJSONObject: ["uri": "spotify:album:\(id)", "name": "旧专辑", "type": "album"])
        await gate.finish(response)
        await task.value
        #expect(recognition.isInvalid)
        #expect(recognition.preview == nil)
        #expect(!recognition.loading)
    }

    @Test func cancelledDuplicateLoadCannotHideNewerProgress() async throws {
        let recognition = LinkRecognition()
        recognition.update("spotify:album:\(id)")
        let oldGate = SettingsResponseGate()
        let newGate = SettingsResponseGate()
        let oldTask = Task { await recognition.load(fetch: { _ in await oldGate.response() }, report: { _ in }) }
        await oldGate.waitUntilRequested()
        let newTask = Task { await recognition.load(fetch: { _ in await newGate.response() }, report: { _ in }) }
        await newGate.waitUntilRequested()
        oldTask.cancel()
        await oldGate.finish(Data())
        await oldTask.value
        #expect(recognition.loading)
        let data = try JSONSerialization.data(withJSONObject: ["uri": "spotify:album:\(id)", "name": "新请求", "type": "album"])
        await newGate.finish(data)
        await newTask.value
        #expect(!recognition.loading)
        #expect(recognition.preview?.item.name == "新请求")
    }

    @Test func metadataFailureIsInlineAndCanRetry() async throws {
        let recognition = LinkRecognition()
        recognition.update("spotify:album:\(id)")
        var reported = false
        await recognition.load(fetch: { _ in throw SmalltifyError("网络连接中断。") }, report: { _ in reported = true })
        #expect(reported)
        #expect(recognition.error == "网络连接中断。")
        let data = try JSONSerialization.data(withJSONObject: ["uri": "spotify:album:\(id)", "name": "潮汐电台", "type": "album"])
        await recognition.load(fetch: { _ in data }, report: { _ in Issue.record("Unexpected error") })
        #expect(recognition.preview?.item.name == "潮汐电台")
        #expect(recognition.error == nil)
    }

    @Test func shortcutsRejectNonPlaylistsAndRetainOrderWhenRenamed() throws {
        let suite = "SettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = PlaylistShortcuts(defaults: defaults)
        try shortcuts.save(name: "每周新发现", link: "spotify:playlist:\(id)")
        try shortcuts.save(name: "新歌雷达", link: "spotify:playlist:abcdefghijklmnopqrstuv")
        try shortcuts.save(name: " 新名称 ", link: "https://open.spotify.com/playlist/\(id)?si=updated")
        #expect(shortcuts.playlists.map(\.name) == ["新名称", "新歌雷达"])
        #expect(throws: SmalltifyError.self) { try shortcuts.save(name: "专辑", link: "spotify:album:\(id)") }
        #expect(PlaylistShortcuts(defaults: defaults).playlists == shortcuts.playlists)
    }
}

private actor SettingsResponseGate {
    private var responseContinuation: CheckedContinuation<Data, Never>?
    private var requestedContinuation: CheckedContinuation<Void, Never>?

    func response() async -> Data {
        await withCheckedContinuation { continuation in
            responseContinuation = continuation
            requestedContinuation?.resume()
            requestedContinuation = nil
        }
    }

    func waitUntilRequested() async {
        if responseContinuation != nil { return }
        await withCheckedContinuation { requestedContinuation = $0 }
    }

    func finish(_ data: Data) {
        responseContinuation?.resume(returning: data)
        responseContinuation = nil
    }
}
