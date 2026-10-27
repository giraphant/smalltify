#if DEBUG
    import AppKit
    import Foundation
    import SwiftUI

    extension FixtureData {
        /// SMALLTIFY_SETTINGS selects auth-none/auth-busy/auth-error/auth-format/auth-expired,
        /// player-starting/player-stopping/player-stopped/player-no-key/player-error/player-expired,
        /// or unpaired; the default is authorized, running and paired.
        /// SMALLTIFY_INPUT selects empty/invalid/album/playlist/track/episode/failure/loading for inputs.
        @MainActor static func configureSettings(_ model: SmalltifyModel) {
            model.clientID = "3f9a1c0e7b2d4a6f8e5c1b0a9d7e6f42"
            model.cacheMB = 5120
            let state = DebugFixtures.environment["SMALLTIFY_SETTINGS"] ?? ""
            switch state {
            case "auth-none":
                model.signedIn = false
                model.clientID = ""
            case "auth-busy": model.authorizing = true
            case "auth-error":
                model.signedIn = false
                model.debugSetSignInError("端口 43821 被占用，无法接收回调。关闭占用该端口的程序后重试。")
            case "auth-format":
                model.signedIn = false
                model.clientID = "3f9a1c0e7b2d"
            case "auth-expired": model.report(SmalltifyError("授权已失效", reason: .authExpired))
            case "player-starting": model.player.debugSetLifecycle(running: false, starting: true, stopping: false, connected: false)
            case "player-stopping": model.player.debugSetLifecycle(running: true, starting: false, stopping: true, connected: false)
            case "player-stopped", "player-no-key", "player-expired":
                model.player.debugSetLifecycle(running: false, starting: false, stopping: false, connected: false)
                model.hasPlayerKey = state != "player-no-key"
                if state == "player-expired" { model.player.error = "Soloist 构建已过期，需要手动更新官方播放器。" }
            case "player-error": model.player.error = "播放器连接中断，正在重新连接。"
            default: break
            }
            if state.hasPrefix("player-"), state != "player-error" {
                model.player.snapshot.loggedIn = false
            }
            if state == "unpaired" { model.player.snapshot.loggedIn = false }
            if DebugFixtures.opens("paste-panel") {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    showSettingsPastePanel(model)
                }
            }
        }

        @MainActor private static var settingsPastePanel: NSPanel?

        /// Snapshot-only host for the exact popover content: transient popovers close when the
        /// invisible fixture app is inactive. SMALLTIFY_OPEN=paste still uses the real popover.
        @MainActor private static func showSettingsPastePanel(_ model: SmalltifyModel) {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 220),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.title = "粘贴 Spotify 链接"
            let hosting = NSHostingView(rootView: PasteLinkPopover { panel.close() }.environment(model))
            panel.contentView = hosting
            panel.setContentSize(hosting.fittingSize)
            panel.center()
            panel.orderFront(nil)
            settingsPastePanel = panel
            Task {
                try? await Task.sleep(for: .seconds(1))
                panel.setContentSize(hosting.fittingSize)
            }
        }
    }
#endif
