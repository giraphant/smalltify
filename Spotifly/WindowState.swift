//
//  WindowState.swift
//  Spotifly
//
//  Manages window state for mini player mode
//

import AppKit
import SwiftUI

@MainActor
@Observable
final class WindowState {
    var isMiniPlayerMode = false
    /// Whether the Now Playing inspector shows beside the content. Opening it first widens a
    /// window too narrow for it (`makeRoomForInspector`).
    var isInspectorPresented = false {
        didSet {
            if isInspectorPresented, !oldValue {
                makeRoomForInspector()
            }
        }
    }

    /// The inspector's width, as `LoggedInView` sets it.
    static let inspectorWidth: CGFloat = 320

    /// Store the previous window frame to restore when exiting mini player
    private var savedWindowFrame: NSRect?

    /// Wide enough for the whole bar, volume and time included.
    static let miniPlayerSize = NSSize(width: NowPlayingBarView.maxBarWidth, height: 96)
    static let defaultSize = NSSize(width: 800, height: 600)

    func toggleMiniPlayerMode() {
        if isMiniPlayerMode {
            exitMiniPlayerMode()
        } else {
            enterMiniPlayerMode()
        }
    }

    private func resolvedWindow(preferred window: NSWindow? = nil) -> NSWindow? {
        window ?? NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first
    }

    /// Widens the window to its minimum width so far plus the inspector's, before SwiftUI lays the
    /// inspector out, keeping it on its screen.
    ///
    /// On a page with a list beside its detail the window did not grow for the inspector by
    /// itself, as it does on other pages: too narrow for it, the split views inside it set each
    /// other's size until AppKit ended the app ("more Update Constraints in Window passes than
    /// there are views in the window"; from 686 pt, 2026-10-24). Not animated, so it is done
    /// before the inspector arrives.
    private func makeRoomForInspector() {
        guard !isMiniPlayerMode, let window = resolvedWindow() else { return }
        let width = window.minSize.width + Self.inspectorWidth
        guard window.frame.width < width else { return }
        var frame = window.frame
        frame.size.width = width
        if let visible = window.screen?.visibleFrame, frame.maxX > visible.maxX {
            frame.origin.x = max(visible.minX, visible.maxX - width)
        }
        window.setFrame(frame, display: true)
    }

    private func enterMiniPlayerMode() {
        guard let window = resolvedWindow() else { return }

        // Save current window frame before switching
        savedWindowFrame = window.frame

        // Set mini player mode FIRST so SwiftUI removes the navigation views
        // before we resize the window
        isMiniPlayerMode = true

        // Give SwiftUI a chance to update the view hierarchy
        Task { @MainActor [window] in
            // Remove resizable style
            window.styleMask.remove(.resizable)

            // Calculate new frame maintaining the same top-left position
            let currentFrame = window.frame
            let newHeight = Self.miniPlayerSize.height
            let newWidth = Self.miniPlayerSize.width
            let newOrigin = NSPoint(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + currentFrame.height - newHeight,
            )
            let newFrame = NSRect(origin: newOrigin, size: NSSize(width: newWidth, height: newHeight))

            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    func exitMiniPlayerMode(window preferredWindow: NSWindow? = nil) {
        guard isMiniPlayerMode else { return }
        guard let window = resolvedWindow(preferred: preferredWindow) else { return }

        // Restore resizable style
        window.styleMask.insert(.resizable)

        // Restore previous frame or use default
        if let savedFrame = savedWindowFrame {
            // Maintain top-left position when restoring
            let currentFrame = window.frame
            let newOrigin = NSPoint(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + currentFrame.height - savedFrame.height,
            )
            let newFrame = NSRect(origin: newOrigin, size: savedFrame.size)
            window.setFrame(newFrame, display: true, animate: true)
        } else {
            window.setContentSize(Self.defaultSize)
        }

        // Set mini player mode AFTER resizing so SwiftUI adds the navigation views
        // after the window is big enough to contain them
        isMiniPlayerMode = false
    }
}
