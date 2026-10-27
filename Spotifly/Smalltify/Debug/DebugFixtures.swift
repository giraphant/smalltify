#if DEBUG
    import AppKit
    import CryptoKit
    import SwiftUI

    /// Debug builds only: runs the window against canned Web API responses, so pages can be
    /// built and checked without the account, the Keychain or Soloist.
    ///
    /// Environment, read at launch:
    /// - `SMALLTIFY_FIXTURES=1` turns the mode on.
    /// - `SMALLTIFY_ROUTE` picks the first page: `home`, `liked`, `playlists`, `albums`, `artists`,
    ///   `search:<query>`, `album:<name>`, `playlist:<name>`, `artist:<name>` (names from `FixtureData`).
    /// - `SMALLTIFY_DARK=1` uses the dark appearance; `SMALLTIFY_INSPECTOR=1` opens 正在播放.
    /// - `SMALLTIFY_WINDOW=<width>x<height>` sizes the main window's content (minimum 900×600; with
    ///   the inspector open, 900 wide leaves a narrow page).
    /// - `SMALLTIFY_SNAPSHOT=<path.png>` writes every visible window after `SMALLTIFY_SNAPSHOT_DELAY`
    ///   seconds (default 3) and quits: the main window to the path, others beside it.
    /// - `SMALLTIFY_OPEN` is free for pages and panels to read, to open a popover or a window
    ///   (`DebugFixtures.opens("devices")`) so the snapshot shows it. `signed-out` starts signed out;
    ///   `paste`, `shortcut` and `settings` open the paste-link popover, the add-shortcut sheet and
    ///   the settings window; `inspector-later` opens 正在播放 after launch, as a click would.
    enum DebugFixtures {
        static let environment = ProcessInfo.processInfo.environment
        static var isEnabled: Bool { environment["SMALLTIFY_FIXTURES"] == "1" }

        /// Whether `SMALLTIFY_OPEN` (comma-separated) names something to open at launch.
        static func opens(_ name: String) -> Bool {
            isEnabled && (environment["SMALLTIFY_OPEN"] ?? "").split(separator: ",").contains { $0 == name }
        }

        @MainActor static func makeModel() -> SmalltifyModel {
            // Snapshot runs launch over and over while a page is checked: keep them out of the
            // Dock and the app switcher, so they do not catch the user's eye every few seconds.
            if environment["SMALLTIFY_SNAPSHOT"] != nil { NSApplication.shared.setActivationPolicy(.accessory) }
            // Every worktree's debug build shares one defaults domain: start each run from the
            // default frames, not whatever size the last run, maybe another worktree's, saved.
            for key in UserDefaults.standard.dictionaryRepresentation().keys
                where key.hasPrefix("NSWindow Frame") || key.hasPrefix("NSSplitView Subview Frames") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            URLProtocol.registerClass(FixtureURLProtocol.self)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [FixtureURLProtocol.self]
            let grant = OfficialGrant(clientID: "fixture", tokens: KeymasterTokens(
                accessToken: "fixture-token", refreshToken: "fixture-refresh", expiresAt: .distantFuture, username: ""),
            connectEnabled: true, scopeVersion: OfficialWebAPI.scopeVersion)
            let api = OfficialWebAPI(grant: grant, session: URLSession(configuration: config), persist: { _ in })
            let defaults = UserDefaults(suiteName: "smalltify.fixtures") ?? .standard
            defaults.removePersistentDomain(forName: "smalltify.fixtures")
            let shortcuts = PlaylistShortcuts(defaults: defaults)
            try? shortcuts.save(name: "每周新发现", link: FixtureData.playlist("每周新发现").uri)
            try? shortcuts.save(name: "新歌雷达", link: FixtureData.playlist("新歌雷达").uri)
            let model = SmalltifyModel(restoreCredentials: false, api: api, shortcuts: shortcuts)
            model.isFixture = true
            model.connect.setAuthorized(true)
            // SMALLTIFY_OPEN=signed-out shows the pages as before authorization.
            model.signedIn = !opens("signed-out")
            model.hasPlayerKey = true
            model.player.snapshot = FixtureData.nowPlaying
            model.player.debugPretendConnected()
            if let route = environment["SMALLTIFY_ROUTE"].flatMap(destination) { model.navigator.reset(to: route) }
            model.inspectorPresented = environment["SMALLTIFY_INSPECTOR"] == "1"
            FixtureData.configurePlayer(model)
            FixtureData.configureSettings(model)
            if environment["SMALLTIFY_DARK"] == "1" { NSApp.appearance = NSAppearance(named: .darkAqua) }
            return model
        }

        static func destination(_ text: String) -> Destination? {
            let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1] : ""
            switch parts.first {
            case "home": return .home
            case "liked": return .liked
            case "playlists": return .playlists
            case "albums": return .albums
            case "artists": return .artists
            case "search": return .search(argument)
            case "album": return .album(FixtureData.album(argument).stub)
            case "playlist": return .playlist(FixtureData.playlist(argument).stub)
            case "artist": return .artist(FixtureData.artist(argument).catalog)
            default: return nil
            }
        }

        /// Prints the view tree's tables and their row counts, for checking what a snapshot misses.
        @MainActor private static func dump(_ view: NSView, depth: Int) {
            if let table = view as? NSTableView {
                print(String(repeating: "  ", count: depth), type(of: table), "rows:", table.numberOfRows, "frame:", table.frame)
            }
            for subview in view.subviews { dump(subview, depth: depth + 1) }
        }

        /// `1280x800` as a size; the main window's minimum, 900×600, still applies.
        static func windowSize(_ text: String) -> CGSize? {
            let parts = text.lowercased().split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }

        /// Writes each visible window as a PNG, then quits.
        @MainActor static func snapshotAndQuit() {
            guard isEnabled, let path = environment["SMALLTIFY_SNAPSHOT"] else { return }
            let delay = Double(environment["SMALLTIFY_SNAPSHOT_DELAY"] ?? "") ?? 3
            // Snapshot runs stay invisible: windows are drawn for the capture, never shown to the user.
            var size = environment["SMALLTIFY_WINDOW"].flatMap(windowSize)
            Task { @MainActor in
                while true {
                    for window in NSApp.windows where window.alphaValue > 0 { window.alphaValue = 0 }
                    // Once only: the window may not take the exact size (its minimum, the inspector),
                    // and resizing it again on every pass loops AppKit's constraint updates.
                    if let requested = size, let main = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
                        main.setContentSize(requested)
                        size = nil
                    }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let base = URL(fileURLWithPath: path)
                let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 20 }
                    .sorted { ($0.identifier?.rawValue ?? "").contains("main") && !($1.identifier?.rawValue ?? "").contains("main") }
                for (index, window) in windows.enumerated() {
                    guard let view = window.contentView?.superview ?? window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = index == 0 ? base : base.deletingPathExtension()
                        .appendingPathExtension("\(index)").appendingPathExtension("png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    print("snapshot:", url.path, window.title)
                    if environment["SMALLTIFY_DUMP"] == "1" { dump(view, depth: 0) }
                }
                exit(0)
            }
        }
    }

    /// Serves `api.spotify.com` from `FixtureData`, and solid-color covers from
    /// `https://fixtures.smalltify.invalid/cover/<RRGGBB>.png`.
    nonisolated final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool {
            ["api.spotify.com", FixtureData.imageHost].contains(request.url?.host)
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
            debugLog("Fixtures", "[LOAD] \(url.host() ?? "")\(url.path)")
            let (status, body, type) = url.host == FixtureData.imageHost
                ? (200, FixtureData.png(hex: url.deletingPathExtension().lastPathComponent), "image/png")
                : FixtureData.respond(method: request.httpMethod ?? "GET", url: url)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type])
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    extension View {
        /// Fixture mode's SMALLTIFY_DARK, set on every scene: NSApp.appearance alone left some
        /// SwiftUI text, such as the inspector's, drawn for light mode.
        func fixtureAppearance() -> some View {
            preferredColorScheme(DebugFixtures.isEnabled && DebugFixtures.environment["SMALLTIFY_DARK"] == "1" ? .dark : nil)
        }
    }
#else
    import SwiftUI

    extension View {
        func fixtureAppearance() -> some View { self }
    }
#endif
