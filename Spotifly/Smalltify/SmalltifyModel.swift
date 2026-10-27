import AppKit
import Foundation
import Observation

@MainActor @Observable final class SmalltifyModel {
    let player = SoloistController()
    let playlistShortcuts = PlaylistShortcuts()
    let api: OfficialWebAPI
    var clientID: String
    var signedIn: Bool
    var authorizing = false
    var hasPlayerKey: Bool
    var cacheMB: Int
    var error: String?
    var notice: String?
    var items: [CatalogItem] = []
    var nextPage: URL?
    var title = "喜欢的歌曲"
    var loading = false
    var selected = "liked"
    var query = ""
    var searchType = "track"
    var directLink = ""
    var collection: CatalogItem?
    private var started = false
    private var authTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var loadedURL: URL?
    private var loadedSearchType: String?

    init() {
        let grant = OfficialGrant.load()
        api = OfficialWebAPI(grant: grant)
        signedIn = grant != nil
        clientID = grant?.clientID ?? UserDefaults.standard.string(forKey: "smalltify.clientID") ?? ""
        hasPlayerKey = SmalltifySecrets.load("soloist-key") != nil
        let savedCache = UserDefaults.standard.integer(forKey: "smalltify.cacheMB")
        cacheMB = savedCache >= 100 ? min(102400, savedCache) : 2048
        if grant == nil && !hasPlayerKey { selected = "settings" }
    }

    func start() async {
        guard !started else { return }
        started = true
        if signedIn { navigate(selected) }
        if hasPlayerKey { await player.start(cacheMB: cacheMB) }
    }

    func signIn() {
        guard !authorizing else { return }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count == 32, id.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) }) else {
            error = "请输入 Dashboard 中的 32 位 Client ID。Client Secret 不需要填写。"
            return
        }
        authorizing = true
        error = nil
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
                try await api.replaceGrant(OfficialGrant(clientID: id, tokens: tokens))
                signedIn = true
                clientID = id
                UserDefaults.standard.set(id, forKey: "smalltify.clientID")
                notice = "Spotify 文库已授权。播放器仍需单独配对。"
                navigate("liked")
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            await server.stop()
            authorizing = false
            authTask = nil
        }
    }

    func cancelSignIn() { authTask?.cancel() }

    func signOut() {
        authTask?.cancel()
        loadTask?.cancel()
        loadGeneration = UUID()
        items = []
        nextPage = nil
        loading = false
        Task {
            do {
                try await api.replaceGrant(nil)
                signedIn = false
                notice = "文库已退出；Soloist 配对独立保留。"
            } catch { self.error = error.localizedDescription }
        }
    }

    func savePlayer(key: String) {
        do {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || hasPlayerKey else { throw SmalltifyError("请输入 Soloist API Key。") }
            guard trimmed.count <= 4096, !trimmed.contains("\n"), !trimmed.contains("\0") else { throw SmalltifyError("API Key 格式不正确。") }
            if !trimmed.isEmpty { try SmalltifySecrets.save(Data(trimmed.utf8), key: "soloist-key") }
            hasPlayerKey = true
            cacheMB = min(102400, max(100, cacheMB))
            UserDefaults.standard.set(cacheMB, forKey: "smalltify.cacheMB")
            Task {
                await player.stop()
                await player.start(cacheMB: cacheMB)
            }
            notice = "设置已保存。首次使用请在官方 Spotify 的设备列表中选择 Smalltify。"
        } catch { self.error = error.localizedDescription }
    }

    func navigate(_ section: String) {
        selected = section
        collection = nil
        if section == "settings" { return }
        do {
            switch section {
            case "liked": title = "喜欢的歌曲"; load(try OfficialWebAPI.apiURL(path: "/me/tracks", query: [.init(name: "limit", value: "50")]))
            case "playlists": title = "我的歌单"; load(try OfficialWebAPI.apiURL(path: "/me/playlists", query: [.init(name: "limit", value: "50")]))
            case "albums": title = "收藏专辑"; load(try OfficialWebAPI.apiURL(path: "/me/albums", query: [.init(name: "limit", value: "50")]))
            case "search": search()
            default: break
            }
        } catch { self.error = error.localizedDescription }
    }

    func search() {
        selected = "search"
        collection = nil
        title = "搜索"
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            loadTask?.cancel(); loadGeneration = UUID(); items = []; nextPage = nil; loading = false
            return
        }
        do {
            load(try OfficialWebAPI.apiURL(path: "/search", query: [
                .init(name: "q", value: text), .init(name: "type", value: searchType), .init(name: "limit", value: "10"),
            ]), searchType: searchType)
        } catch { self.error = error.localizedDescription }
    }

    func openCollection(_ item: CatalogItem) {
        guard item.isCollection else { return }
        collection = item
        title = item.name
        do {
            let path = item.kind == "playlist" ? "/playlists/\(item.spotifyID)/items" : "/albums/\(item.spotifyID)/tracks"
            load(try OfficialWebAPI.apiURL(path: path, query: [.init(name: "limit", value: "50")]))
        } catch { self.error = error.localizedDescription }
    }

    func refresh() {
        if let loadedURL { load(loadedURL, searchType: loadedSearchType) }
    }

    func loadMore() {
        if let nextPage, !loading { load(nextPage, searchType: loadedSearchType, append: true) }
    }

    private func load(_ url: URL, searchType: String? = nil, append: Bool = false) {
        loadTask?.cancel()
        let generation = UUID()
        loadGeneration = generation
        if !append {
            items = []; nextPage = nil; loadedURL = url; loadedSearchType = searchType
        }
        guard signedIn else { loading = false; return }
        loading = true
        error = nil
        loadTask = Task {
            defer { if generation == loadGeneration { loading = false } }
            do {
                let data = try await api.get(url)
                let page = try CatalogPage.parse(data, searchType: searchType)
                try Task.checkCancellation()
                guard generation == loadGeneration else { return }
                if append { items.append(contentsOf: page.items) } else { items = page.items }
                nextPage = page.next
            } catch {
                if generation == loadGeneration, !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    func playLink() {
        guard let uri = Self.spotifyURI(from: directLink) else {
            error = "请输入 open.spotify.com 的曲目、专辑、歌单链接，或 spotify: 类型的 URI。"
            return
        }
        player.control("play", uri: uri)
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
