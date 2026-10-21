//
//  AirPlayRoutePickerView.swift
//  Spotifly
//
//  NSViewRepresentable wrapper for AVRoutePickerView (macOS only)
//

#if os(macOS)
    import AVKit
    import SwiftUI

    /// The system's AirPlay picker. Bound to a player, it routes that player alone, and the rest
    /// of the Mac's audio stays where it is; unbound, it picks the Mac's output for everything.
    /// The app's own player, `StreamingPlayerOutput`, plays only behind the Debug menu's switch
    /// (`plans/open/avplayer-output-probe.md`); otherwise there is none to bind.
    struct AirPlayRoutePickerView: NSViewRepresentable {
        /// The player to route, or nil for the Mac's output.
        var player: AVPlayer?

        func makeNSView(context _: Context) -> AVRoutePickerView {
            let routePickerView = AVRoutePickerView()
            routePickerView.isRoutePickerButtonBordered = false
            routePickerView.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
            routePickerView.setRoutePickerButtonColor(.controlAccentColor, for: .active)
            routePickerView.player = player
            return routePickerView
        }

        func updateNSView(_ routePickerView: AVRoutePickerView, context _: Context) {
            if routePickerView.player !== player {
                routePickerView.player = player
            }
        }
    }

    extension AirPlayRoutePickerView {
        /// The picker for Spotifly's own audio: bound to the app's player where this launch has
        /// one, else the Mac's output.
        static var spotifly: AirPlayRoutePickerView {
            AirPlayRoutePickerView(player: SpotifyPlayer.usesAVPlayerOutput ? StreamingPlayerOutput.shared.player : nil)
        }
    }
#endif
