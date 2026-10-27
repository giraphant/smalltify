//
//  SpotiflyApp.swift
//  Spotifly
//
//  Created by Ralph von der Heyden on 30.12.25.
//

import AppKit
import SwiftUI

// MARK: - Focused Values for Menu Commands

struct FocusedNavigationCoordinator: FocusedValueKey {
    typealias Value = NavigationCoordinator
}

struct FocusedHomeService: FocusedValueKey {
    typealias Value = HomeService
}

extension FocusedValues {
    /// The key window's navigation, for the Navigate menu's sections and history.
    var navigationCoordinator: NavigationCoordinator? {
        get { self[FocusedNavigationCoordinator.self] }
        set { self[FocusedNavigationCoordinator.self] = newValue }
    }

    var homeService: HomeService? {
        get { self[FocusedHomeService.self] }
        set { self[FocusedHomeService.self] = newValue }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var allowedTermination = false
    weak var soloist: SoloistController?

    func applicationDidFinishLaunching(_: Notification) {
        // Artwork is loaded through URLSession.shared; the default cache keeps almost none of it.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        #if DEBUG
            DebugFixtures.snapshotAndQuit()
        #endif
        _ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            endSearchEditing(onClickOf: event)
            return event
        }
    }

    /// Let the locally owned Soloist child close its session and cache before quitting.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await soloist?.stop()
            allowTermination()
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            allowTermination()
        }
        return .terminateLater
    }

    private func allowTermination() {
        guard !allowedTermination else { return }
        allowedTermination = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}

// MARK: - App

@main
struct SpotiflyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model: SmalltifyModel? = SpotiflyApp.makeModel()
    static let hostsUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private static func makeModel() -> SmalltifyModel? {
        guard !hostsUnitTests else { return nil }
        #if DEBUG
            if DebugFixtures.isEnabled { return DebugFixtures.makeModel() }
        #endif
        return SmalltifyModel()
    }

    var body: some Scene {
        Window("Smalltify", id: "main") {
            if let model {
                SmalltifyWorkspace(model: model)
                    .task {
                        appDelegate.soloist = model.player
                        await model.start()
                    }
            }
        }
        .defaultSize(width: 1280, height: 800)
        .commands { SmalltifyCommands(model: model) }

        Window("迷你播放器", id: MiniPlayerWindow.id) {
            if let model {
                MiniPlayerWindow(model: model)
                    .environment(model)
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Settings {
            if let model {
                SettingsWindow(model: model)
                    .environment(model)
            }
        }
    }
}

// MARK: - Search Field Focus

/// Focuses the toolbar's always-visible `.searchable` field. SwiftUI offers no API
/// to focus an always-visible search field, so we make the underlying NSSearchField
/// the window's first responder. No-op if the field can't be found.
@MainActor
func focusToolbarSearchField() {
    let windows = NSApp.windows.sorted { $0.isKeyWindow && !$1.isKeyWindow }
    for window in windows where window.isVisible {
        // The toolbar lives in the window frame view, above contentView.
        if let field = firstSearchField(in: window.contentView?.superview ?? window.contentView) {
            window.makeFirstResponder(field)
            return
        }
    }
}

/// Ends the search field's editing on a click anywhere else in its window.
///
/// SwiftUI's lists and grids take no focus when clicked, so once the toolbar's field had it, from
/// a click or ⌘F, it kept it: Space typed into the field and never reached the Playback menu's
/// Play/Pause. In an AppKit window, the list clicked on would have taken the focus.
func endSearchEditing(onClickOf event: NSEvent) {
    guard let window = event.window,
          let field = (window.firstResponder as? NSText)?.delegate as? NSSearchField,
          !field.bounds.contains(field.convert(event.locationInWindow, from: nil))
    else { return }
    window.makeFirstResponder(nil)
}

private func firstSearchField(in view: NSView?) -> NSSearchField? {
    guard let view else { return nil }
    if let field = view as? NSSearchField {
        return field
    }
    for subview in view.subviews {
        if let field = firstSearchField(in: subview) {
            return field
        }
    }
    return nil
}
