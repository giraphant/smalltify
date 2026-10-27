import AppKit
import Foundation
import Observation

/// The signed-in account as `/me` describes it, for the sidebar's footer.
nonisolated struct AccountProfile: Sendable, Equatable {
    let id: String
    let displayName: String
    let imageURL: URL?
}

/// What a track was played from, so playback can carry on through the rest of it.
nonisolated struct PlaybackContext: Hashable, Sendable {
    /// An album, a playlist, or the user's collection (`spotify:user:<id>:collection`).
    let uri: String
    /// The track played and the ones after it in the list as shown, at most 100. Spotify can
    /// start an album or playlist at a track, but not the collection; there playback follows
    /// this list instead. Filled by `play(_:startingAt:in:)`.
    var upcoming: [String] = []

    /// The playable uris from `index` on, at most 100: what Spotify accepts in one play request.
    static func upcoming(_ tracks: [CatalogItem], from index: Int) -> [String] {
        guard tracks.indices.contains(index) else { return [] }
        return Array(tracks[index...].lazy.map(\.uri).filter { CatalogItem.validURI($0) }.prefix(100))
    }
}

/// The connection as the sidebar's status capsule and the player bar's device chip show it.
nonisolated struct ConnectionStatus: Equatable, Sendable {
    enum Tone: Sendable { case ok, busy, warn, error }
    let text: String
    let tone: Tone
}

/// The app's state for as long as it runs: the account, the player, and the window's navigation.
/// Pages load their own data through `pages`; this model holds what every page shares.
@MainActor @Observable final class SmalltifyModel {
    let player = SoloistController()
    let playlistShortcuts: PlaylistShortcuts
    let api: OfficialWebAPI
    let artistCatalog: ArtistCatalogLoader
    let connect: SpotifyConnectController
    let navigator: Navigator
    let notices = Notices()
    @ObservationIgnored let pages = PageStore()
    var clientID: String
    var signedIn: Bool
    var authorizing = false
    /// Why the last sign-in failed, for the settings page; cleared when the next one starts.
    private(set) var signInError: String?
    /// Spotify refused the grant: the settings page offers 重新授权 until a sign-in succeeds.
    private(set) var authExpired = false
    var hasPlayerKey: Bool
    var cacheMB: Int
    /// Signed in with fewer scopes than the current features need.
    var needsScopeUpgrade: Bool
    private(set) var profile: AccountProfile?
    var inspectorPresented = false
    /// Debug fixture mode: never starts Soloist, never reads or writes the Keychain, never
    /// opens a real sign-in. Set only by `DebugFixtures`.
    @ObservationIgnored var isFixture = false
    private var playbackObservation: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchArtistURI: String?
    private var started = false
    private var authTask: Task<Void, Never>?

    init(restoreCredentials: Bool = true, api suppliedAPI: OfficialWebAPI? = nil,
         shortcuts: PlaylistShortcuts = PlaylistShortcuts()) {
        let grant = restoreCredentials ? OfficialGrant.load() : nil
        let api = suppliedAPI ?? OfficialWebAPI(grant: grant)
        self.api = api
        playlistShortcuts = shortcuts
        artistCatalog = ArtistCatalogLoader(api: api)
        connect = SpotifyConnectController(api: api, authorized: grant?.connectEnabled == true)
        signedIn = grant != nil
        needsScopeUpgrade = grant?.needsScopeUpgrade == true
        clientID = grant?.clientID ?? UserDefaults.standard.string(forKey: "smalltify.clientID") ?? ""
        hasPlayerKey = restoreCredentials && SmalltifySecrets.load("soloist-key") != nil
        let savedCache = UserDefaults.standard.integer(forKey: "smalltify.cacheMB")
        cacheMB = savedCache >= 100 ? min(102_400, savedCache) : 2048
        navigator = Navigator(start: .home)
        player.connect = connect
        connect.local = player
    }

    func start() async {
        guard !started else { return }
        started = true
        observePlaybackForPrefetch()
        connect.start()
        if signedIn {
            loadProfile()
            if needsScopeUpgrade { offerScopeUpgrade() }
        }
        if hasPlayerKey, !isFixture { await player.start(cacheMB: cacheMB) }
    }

    isolated deinit {
        playbackObservation?.cancel()
        prefetchTask?.cancel()
    }

    // MARK: - Status

    var connectionStatus: ConnectionStatus {
        if !signedIn { return ConnectionStatus(text: "未连接 Spotify", tone: .warn) }
        if !hasPlayerKey { return ConnectionStatus(text: "播放器未设置", tone: .warn) }
        if player.starting || (player.running && !player.connected) {
            return ConnectionStatus(text: "播放器启动中…", tone: .busy)
        }
        if !player.running {
            return ConnectionStatus(text: player.error == nil ? "播放器已停止" : "播放器出错", tone: player.error == nil ? .warn : .error)
        }
        if !player.snapshot.loggedIn { return ConnectionStatus(text: "等待配对", tone: .warn) }
        if connect.transferring { return ConnectionStatus(text: "正在切换设备…", tone: .busy) }
        if connect.usesRemote, let device = connect.playback?.device {
            return ConnectionStatus(text: "远程 · \(device.name)", tone: .busy)
        }
        return ConnectionStatus(text: "播放器就绪 · 这台 Mac", tone: .ok)
    }

    /// The device playback is on, as the player bar's device chip names it.
    var deviceLabel: String {
        if connect.usesRemote, let device = connect.playback?.device { return device.name }
        return "这台 Mac"
    }

    var isRemote: Bool { connect.usesRemote }

    // MARK: - Errors

    /// Shows a failure in the banner, with the action that fixes it where there is one.
    func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        let reason = (error as? SmalltifyError)?.reason ?? .other
        switch reason {
        case .authExpired:
            authExpired = true
            notices.show(.init(message: "登录已过期，文库和设备暂时无法读取。", actions: [
                .init(title: "重新授权") { [weak self] in self?.signIn() },
            ]))
        case .signedOut:
            break // Pages show their own "连接你的 Spotify 账号" state.
        case let .rateLimited(seconds):
            notices.show(.init(message: "请求太频繁，Spotify 暂时限流。约 \(seconds) 秒后再试。", tone: .warning))
        case .forbidden, .other:
            break // Pages show load failures in place; the banner is for what blocks the whole window.
        }
    }

    private func offerScopeUpgrade() {
        notices.show(.init(message: "首页、关注和收藏需要新的权限，请重新授权一次。", tone: .warning, actions: [
            .init(title: "重新授权") { [weak self] in self?.signIn() },
        ]))
    }

    // MARK: - Navigation and pages

    func refreshCurrentPage() {
        pages.refresh(route: navigator.current.key)
    }

    /// A paged list for a page, stored under `key` and loaded through this model's API.
    func pagedLoader(_ key: String, url: URL, searchType: String? = nil) -> PagedLoader {
        pages.loader(key) {
            PagedLoader(api: api, url: url, searchType: searchType) { [weak self] in self?.report($0) }
        }
    }

    /// An artist's releases of one group (`album,single`, `album`, `single`, `appears_on`), through
    /// the catalog cache that playback prefetches into, so an artist playing opens instantly.
    func artistAlbumsLoader(_ artist: CatalogArtist, group: String) throws -> PagedLoader {
        let url = try ArtistCatalogLoader.albumsURL(artistID: artist.spotifyID, group: group)
        return pages.loader("\(Destination.artist(artist).key)/albums:\(group)") {
            PagedLoader(firstURL: url, report: { [weak self] in self?.report($0) }) { [artistCatalog] url, refresh in
                try await artistCatalog.albums(from: url, refresh: refresh)
            }
        }
    }

    func open(_ artist: CatalogArtist) {
        guard CatalogArtist.validURI(artist.uri) else { return }
        navigator.go(.artist(artist))
    }

    func open(_ item: CatalogItem) {
        if let route = Destination.collection(item) {
            navigator.go(route)
        } else if item.kind == "artist" {
            open(CatalogArtist(uri: item.uri, name: item.name, imageURL: item.imageURL, images: item.images))
        }
    }

    func open(_ album: CatalogAlbumRef) {
        navigator.go(.album(CatalogItem(uri: album.uri, name: album.name, subtitle: "", kind: "album", durationMS: 0, imageURL: nil)))
    }

    /// Routes the app's own links, `smalltify://artist/<id>?name=…` and `smalltify://album/<id>?name=…`,
    /// which list text uses so each artist name in a line can be clicked on its own.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == AppLink.scheme, let host = url.host() else { return false }
        let id = url.lastPathComponent
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "name" }?.value ?? ""
        switch host {
        case "artist": open(CatalogArtist(uri: "spotify:artist:\(id)", name: name))
        case "album" where CatalogItem.validURI("spotify:album:\(id)"):
            open(CatalogAlbumRef(uri: "spotify:album:\(id)", name: name))
        default: return false
        }
        return true
    }

    // MARK: - Playback

    /// Plays a whole track, album, playlist or episode by uri.
    func play(uri: String) {
        player.control("play", uri: uri)
    }

    /// Plays a track; within `context`, playback is meant to carry on through the rest of it.
    /// TODO(player worker): start the context at this track once Soloist's play command is confirmed.
    func play(_ track: CatalogItem, in context: PlaybackContext?) {
        player.control("play", uri: track.uri)
    }

    /// Plays `tracks[index]` from a list as shown, so playback carries on through the tracks after it.
    func play(_ tracks: [CatalogItem], startingAt index: Int, in context: PlaybackContext?) {
        guard tracks.indices.contains(index) else { return }
        var context = context
        context?.upcoming = PlaybackContext.upcoming(tracks, from: index)
        play(tracks[index], in: context)
    }

    func enqueue(_ item: CatalogItem) {
        guard item.kind == "track" || item.kind == "episode" else { return }
        Task {
            do {
                try await player.send("add_to_queue", uri: item.uri)
                notices.toast("已加入队列")
            } catch { player.error = error.localizedDescription }
        }
    }

    /// The user's saved tracks as a playback context.
    var collectionContext: PlaybackContext? {
        profile.map { PlaybackContext(uri: "spotify:user:\($0.id):collection") }
    }

    func copyLink(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        notices.toast("已复制链接")
    }

    func openInSpotify(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Account

    private func loadProfile() {
        Task {
            do {
                let data = try await api.get(OfficialWebAPI.apiURL(path: "/me"))
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = object["id"] as? String else { return }
                profile = AccountProfile(id: id, displayName: object["display_name"] as? String ?? id,
                                      imageURL: CatalogItem.parseImages(object["images"]).first?.url)
            } catch { report(error) }
        }
    }

    private func observePlaybackForPrefetch() {
        playbackObservation = Task { [weak self, player] in
            let changes = Observations { [weak self] in
                (player.displaySnapshot.artists.first, player.displaySnapshot.status, self?.signedIn ?? false)
            }
            for await (artist, status, authorized) in changes {
                guard let self, !Task.isCancelled else { return }
                let candidate = authorized && status == "playing" ? artist : nil
                guard candidate?.uri != prefetchArtistURI else { continue }
                prefetchTask?.cancel()
                prefetchArtistURI = candidate?.uri
                guard let candidate else { continue }
                prefetchTask = Task { [artistCatalog] in
                    do {
                        try await Task.sleep(for: .milliseconds(800))
                        await artistCatalog.prefetch(candidate)
                    } catch {}
                }
            }
        }
    }

    func signIn() {
        guard !authorizing else { return }
        guard !isFixture else { return notices.toast("演示模式：不会真的登录") }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count == 32, id.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) }) else {
            signInError = "Client ID 应为 32 位十六进制字符，当前只有 \(id.count) 位。"
            notices.show(.init(message: "请在设置中填写 Dashboard 中的 32 位 Client ID。Client Secret 不需要填写。"))
            return
        }
        authorizing = true
        signInError = nil
        authTask = Task {
            let server = LoopbackCallbackServer()
            do {
                let port: UInt16
                do {
                    port = try await server.start(port: SmalltifyOAuth.callbackPort)
                } catch {
                    throw SmalltifyError("无法监听本机端口 \(SmalltifyOAuth.callbackPort)。请关闭其他 Smalltify 实例或占用此端口的程序后重试。")
                }
                let verifier = PKCE.codeVerifier()
                let state = PKCE.randomState()
                let url = try OfficialWebAPI.authorizationURL(clientID: id, port: port, verifier: verifier, state: state)
                guard NSWorkspace.shared.open(url) else { throw SmalltifyError("无法打开授权浏览器。") }
                let callback = try await server.waitForCallback()
                guard callback.path == "/login" else { throw SmalltifyError("授权回调路径不正确。") }
                let code = try KeymasterAuth.authorizationCode(from: callback, expectedState: state)
                let session = SmalltifyHTTPDelegate.session()
                defer { session.finishTasksAndInvalidate() }
                let tokens = try await OfficialWebAPI.exchange([
                    "grant_type": "authorization_code", "client_id": id, "code": code,
                    "redirect_uri": "http://127.0.0.1:\(port)/login", "code_verifier": verifier,
                ], session: session)
                try Task.checkCancellation()
                prefetchTask?.cancel()
                prefetchArtistURI = nil
                await artistCatalog.clear()
                try await api.replaceGrant(OfficialGrant(clientID: id, tokens: tokens, connectEnabled: true,
                                                         scopeVersion: OfficialWebAPI.scopeVersion))
                signedIn = true
                authExpired = false
                needsScopeUpgrade = false
                connect.setAuthorized(true)
                clientID = id
                UserDefaults.standard.set(id, forKey: "smalltify.clientID")
                pages.clear()
                notices.dismissBanner()
                notices.toast("Spotify 已授权")
                loadProfile()
            } catch {
                if !Task.isCancelled {
                    signInError = error.localizedDescription
                    notices.show(.init(message: error.localizedDescription))
                }
            }
            await server.stop()
            authorizing = false
            authTask = nil
        }
    }

    func cancelSignIn() { authTask?.cancel() }

    func signOut() {
        guard !isFixture else { return notices.toast("演示模式：不会退出") }
        authTask?.cancel()
        prefetchTask?.cancel()
        prefetchArtistURI = nil
        connect.setAuthorized(false)
        pages.clear()
        Task {
            do {
                try await api.replaceGrant(nil)
                await artistCatalog.clear()
                signedIn = false
                authExpired = false
                profile = nil
                navigator.reset(to: .home)
                notices.toast("已退出 Spotify 文库")
            } catch { notices.show(.init(message: error.localizedDescription)) }
        }
    }

    func savePlayer(key: String) {
        guard !isFixture else { return notices.toast("演示模式：不会保存密钥") }
        do {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || hasPlayerKey else { throw SmalltifyError("请输入 Soloist API Key。") }
            guard trimmed.count <= 4096, !trimmed.contains("\n"), !trimmed.contains("\0") else { throw SmalltifyError("API Key 格式不正确。") }
            if !trimmed.isEmpty { try SmalltifySecrets.save(Data(trimmed.utf8), key: "soloist-key") }
            hasPlayerKey = true
            cacheMB = min(102_400, max(100, cacheMB))
            UserDefaults.standard.set(cacheMB, forKey: "smalltify.cacheMB")
            Task {
                await player.stop()
                await player.start(cacheMB: cacheMB)
            }
        } catch { notices.show(.init(message: error.localizedDescription)) }
    }

    /// Plays an `open.spotify.com` link or `spotify:` uri; false when it is neither.
    @discardableResult
    func play(link: String) -> Bool {
        guard let uri = Self.spotifyURI(from: link) else { return false }
        play(uri: uri)
        return true
    }

    nonisolated static func spotifyURI(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if CatalogItem.validURI(text) { return text }
        guard let url = URL(string: text), url.scheme == "https", url.host == "open.spotify.com", url.user == nil, url.password == nil else { return nil }
        var parts = url.path.split(separator: "/").map(String.init)
        if parts.first?.hasPrefix("intl-") == true { parts.removeFirst() }
        guard parts.count == 2 else { return nil }
        let uri = "spotify:\(parts[0]):\(parts[1])"
        return CatalogItem.validURI(uri) ? uri : nil
    }
}

/// Links the app routes itself; see `SmalltifyModel.handle(_:)`.
nonisolated enum AppLink {
    static let scheme = "smalltify"

    static func artist(_ artist: CatalogArtist) -> URL? {
        url(host: "artist", id: artist.spotifyID, name: artist.name)
    }

    static func album(_ album: CatalogAlbumRef) -> URL? {
        url(host: "album", id: String(album.uri.dropFirst("spotify:album:".count)), name: album.name)
    }

    private static func url(host: String, id: String, name: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.path = "/" + id
        parts.queryItems = [URLQueryItem(name: "name", value: name)]
        return parts.url
    }
}

#if DEBUG
    extension SmalltifyModel {
        /// Fixture mode: shows a failed sign-in without attempting one.
        func debugSetSignInError(_ message: String?) {
            signInError = message
        }
    }
#endif
