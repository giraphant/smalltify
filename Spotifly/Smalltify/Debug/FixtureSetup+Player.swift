#if DEBUG
    import AppKit
    import Foundation
    import SwiftUI

    nonisolated extension FixtureData {
        /// SMALLTIFY_PLAYER selects local, remote (no volume), idle, unpaired, starting,
        /// no-key, no-connect, pending, paused, repeat-all, repeat-one, queue-empty or queue-error.
        /// SMALLTIFY_OPEN=devices/mini opens those surfaces; compact-bar opens a 630pt bar.
        @MainActor static func configurePlayer(_ model: SmalltifyModel) {
            model.player.snapshot.shuffle = true
            model.player.snapshot.album = CatalogItem.parse(allTracks[0])?.album
            model.player.snapshot.releaseYear = "2024"
            // A fixed position keeps light and dark snapshots comparable.
            model.player.snapshot.speed = 0
            switch playerState {
            case "remote", "pending":
                model.player.snapshot.active = false
                model.connect.debugSetPlayback(remotePlayback, pending: playerState == "pending" ? "phone" : nil)
            case "idle": model.player.snapshot = SoloistSnapshot(loggedIn: true, active: true)
            case "unpaired": model.player.snapshot = SoloistSnapshot()
            case "starting":
                model.player.snapshot = SoloistSnapshot()
                model.player.debugSetLifecycle(running: true, starting: true, connected: false)
            case "no-key":
                model.hasPlayerKey = false
                model.player.snapshot = SoloistSnapshot()
                model.player.debugSetLifecycle(running: false, connected: false)
            case "no-connect": model.connect.setAuthorized(false)
            case "paused": model.player.snapshot.status = "paused"
            case "repeat-all": model.player.snapshot.repeatMode = "context"
            case "repeat-one": model.player.snapshot.repeatMode = "track"
            default: break
            }
            if DebugFixtures.opens("compact-bar") {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 64),
                                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    window.title = "播放器紧凑布局"
                    window.contentView = NSHostingView(rootView: PlayerBar().environment(model))
                    playerPreviewWindow = window
                    window.orderFront(nil)
                }
            }
        }

        @MainActor private static var playerPreviewWindow: NSWindow?
    }
#endif
