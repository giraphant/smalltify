import Foundation

nonisolated struct OfficialGrant: Codable, Sendable {
    var clientID: String
    var tokens: KeymasterTokens
    var connectEnabled: Bool? = nil
    /// The `OfficialWebAPI.scopeVersion` this grant was authorized with; nil predates versioning.
    var scopeVersion: Int? = nil

    /// Whether features added since this grant need the user to authorize once more.
    var needsScopeUpgrade: Bool { (scopeVersion ?? 0) < OfficialWebAPI.scopeVersion }

    static func load() -> Self? {
        guard let data = SmalltifySecrets.load("web-grant") else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

/// Own-client PKCE grant only. Never uses KeymasterSession or the desktop client id.
actor OfficialWebAPI {
    /// Bump `scopeVersion` whenever `scopes` grows, so older grants are asked to reauthorize.
    nonisolated static let scopes = [
        "user-read-private", "user-library-read", "user-library-modify",
        "playlist-read-private", "playlist-read-collaborative",
        "user-follow-read", "user-follow-modify",
        "user-top-read", "user-read-recently-played",
        "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
    ].joined(separator: " ")
    nonisolated static let scopeVersion = 2

    private var grant: OfficialGrant?
    private var epoch = UUID()
    private var refreshing: Task<OfficialGrant, Error>?
    private var retryAfter = Date.distantPast
    private let session: URLSession
    private let persist: @Sendable (OfficialGrant?) throws -> Void

    init(grant: OfficialGrant?, session: URLSession = SmalltifyHTTPDelegate.session(),
         persist: @escaping @Sendable (OfficialGrant?) throws -> Void = OfficialWebAPI.persistGrant) {
        self.grant = grant
        self.session = session
        self.persist = persist
    }

    nonisolated static func persistGrant(_ newGrant: OfficialGrant?) throws {
        if let newGrant {
            try SmalltifySecrets.save(JSONEncoder().encode(newGrant), key: "web-grant")
        } else {
            SmalltifySecrets.delete("web-grant")
        }
    }

    func replaceGrant(_ newGrant: OfficialGrant?) throws {
        try persist(newGrant)
        epoch = UUID()
        refreshing?.cancel()
        refreshing = nil
        grant = newGrant
    }

    nonisolated static func apiURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard path.hasPrefix("/"), !path.contains(".."), !path.contains("?") else {
            throw SmalltifyError("无效的 Spotify API 路径。")
        }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "api.spotify.com"
        parts.path = "/v1" + path
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw SmalltifyError("无法构建 Spotify 请求。") }
        return url
    }

    nonisolated static func allowedAPIURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "api.spotify.com"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.fragment == nil && url.path.hasPrefix("/v1/")
            && !url.path.split(separator: "/").contains("..")
    }

    func get(_ url: URL) async throws -> Data {
        try await request(url, method: "GET")
    }

    /// Library writes: saving albums and tracks, following artists and playlists.
    @discardableResult
    func send(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        let writable = ["/me/library", "/me/albums", "/me/tracks", "/me/following"]
        let playlistFollow = path.hasPrefix("/playlists/") && path.hasSuffix("/followers")
        guard ["PUT", "POST", "DELETE"].contains(method),
              playlistFollow || writable.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            throw SmalltifyError("无效的文库写入请求。")
        }
        return try await request(Self.apiURL(path: path, query: query), method: method, body: body)
    }

    func sendPlayer(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws {
        guard ["PUT", "POST"].contains(method), path == "/me/player" || path.hasPrefix("/me/player/") else {
            throw SmalltifyError("无效的播放控制请求。")
        }
        _ = try await request(Self.apiURL(path: path, query: query), method: method, body: body)
    }

    private func request(_ url: URL, method: String, body: Data? = nil) async throws -> Data {
        guard Self.allowedAPIURL(url) else { throw SmalltifyError("拒绝向非 Spotify 地址发送登录凭据。") }
        let expectedEpoch = epoch
        for attempt in 0 ... 1 {
            guard Date() >= retryAfter else {
                let seconds = max(1, Int(retryAfter.timeIntervalSinceNow))
                throw SmalltifyError("Spotify 请求限流，请稍后再试（约 \(seconds) 秒）。", reason: .rateLimited(seconds: seconds))
            }
            let token = try await accessToken()
            guard expectedEpoch == epoch else { throw CancellationError() }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            debugLog("OfficialWebAPI", "[\(method)] \(url.path)")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard expectedEpoch == epoch else { throw CancellationError() }
            guard let http = response as? HTTPURLResponse else { throw SmalltifyError("Spotify 返回了无效响应。") }
            switch http.statusCode {
            case 200, 204: return data
            case 401 where attempt == 0:
                if grant?.tokens.accessToken == token { grant?.tokens.expiresAt = .distantPast }
            case 401: throw SmalltifyError("Spotify 登录已失效，请在设置中重新授权。", reason: .authExpired)
            case 403 where url.path.hasPrefix("/v1/me/player"):
                throw SmalltifyError("Spotify 拒绝播放控制（403）。请重新授权 Connect，并确认目标设备支持远程控制。", reason: .forbidden)
            case 403:
                throw SmalltifyError("Spotify 拒绝访问（403）。请确认开发者应用的 Premium 与用户授权；歌单曲目接口仅允许读取自己拥有或参与协作的歌单。", reason: .forbidden)
            case 429:
                let delay = max(1, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "30") ?? 30)
                retryAfter = Date().addingTimeInterval(delay)
                throw SmalltifyError("Spotify 请求限流，请 \(Int(delay)) 秒后重试。", reason: .rateLimited(seconds: Int(delay)))
            default:
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let details = object?["error"] as? [String: Any]
                let message = (details?["message"] as? String ?? "")
                    .replacing(token, with: "[redacted]")
                    .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                let suffix = message.isEmpty ? "" : " " + String(message.prefix(240))
                throw SmalltifyError("Spotify 请求失败（HTTP \(http.statusCode)）。" + suffix)
            }
        }
        throw SmalltifyError("请重新登录 Spotify。", reason: .authExpired)
    }

    private func accessToken() async throws -> String {
        guard let grant else { throw SmalltifyError("请先在设置中使用 Client ID 登录。", reason: .signedOut) }
        if !grant.tokens.needsRefresh() { return grant.tokens.accessToken }
        if let refreshing { return try await refreshing.value.tokens.accessToken }
        let expectedEpoch = epoch
        let task = Task {
            let tokens = try await Self.exchange([
                "grant_type": "refresh_token", "refresh_token": grant.tokens.refreshToken,
                "client_id": grant.clientID,
            ], fallback: grant.tokens.refreshToken, session: session)
            return OfficialGrant(clientID: grant.clientID, tokens: tokens, connectEnabled: grant.connectEnabled,
                                 scopeVersion: grant.scopeVersion)
        }
        refreshing = task
        defer { if expectedEpoch == epoch { refreshing = nil } }
        let updated = try await task.value
        guard expectedEpoch == epoch else { throw CancellationError() }
        try persist(updated)
        self.grant = updated
        return updated.tokens.accessToken
    }

    nonisolated static func authorizationURL(clientID: String, port: UInt16, verifier: String, state: String) throws -> URL {
        var parts = URLComponents(string: "https://accounts.spotify.com/authorize")
        parts?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "http://127.0.0.1:\(port)/login"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.codeChallenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = parts?.url else { throw SmalltifyError("无法创建授权地址。") }
        return url
    }

    nonisolated static func exchange(_ fields: [String: String], fallback: String? = nil,
                                    session: URLSession) async throws -> KeymasterTokens {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            throw SmalltifyError("无法创建授权地址。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = KeymasterAuth.formURLEncoded(fields)
        debugLog("OfficialWebAPI", "[POST] /api/token")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // A refresh token Spotify no longer accepts answers 400 invalid_grant: only a new sign-in helps.
            throw SmalltifyError("Spotify 授权失败（HTTP \(status)），请检查 Client ID、回调地址，或重新登录。",
                                 reason: status == 400 || status == 401 ? .authExpired : .other)
        }
        return try KeymasterAuth.parseTokenResponse(data, fallbackRefreshToken: fallback)
    }
}
