//
//  AirPlayRoutePickerView.swift
//  Spotifly
//
//  NSViewRepresentable wrapper for AVRoutePickerView (macOS only)
//

#if os(macOS)
    import AVKit
    import SwiftUI

    /// The system's AirPlay picker, bound to the app's player: it routes Spotifly alone, and the
    /// rest of the Mac's audio stays where it is.
    ///
    /// One picker serves the whole run, and this view only borrows it. A route chosen in a picker
    /// lives with that picker: once it was gone and another was bound to the player, macOS
    /// released the route, and a HomePod fell back to the Mac a few seconds later. The bar's
    /// picker went whenever the bar was rebuilt: after a reconnect or a handover, which swaps it
    /// for the Playing On button and back, and on leaving the mini player
    /// (`plans/done/airplay-route-dies-with-its-picker.md`). Shown in one place at a time; the
    /// place made last has it.
    struct AirPlayRoutePickerView: NSViewRepresentable {
        private static let picker: AVRoutePickerView = {
            let picker = AVRoutePickerView()
            picker.isRoutePickerButtonBordered = false
            picker.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
            picker.setRoutePickerButtonColor(.controlAccentColor, for: .active)
            picker.player = AudioOutputPlayer.shared.player
            return picker
        }()

        func makeNSView(context _: Context) -> NSView {
            let container = NSView()
            Self.picker.removeFromSuperview()
            Self.picker.frame = container.bounds
            Self.picker.autoresizingMask = [.width, .height]
            container.addSubview(Self.picker)
            return container
        }

        func updateNSView(_: NSView, context _: Context) {}

        /// Lets go of the picker without ending it, unless another place has taken it since.
        static func dismantleNSView(_ container: NSView, coordinator _: ()) {
            if picker.superview === container {
                picker.removeFromSuperview()
            }
        }
    }
#endif
