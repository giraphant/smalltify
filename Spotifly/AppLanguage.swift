//
//  AppLanguage.swift
//  Spotifly
//
//  The app's own language, chosen in Settings over the system's
//

import AppKit
import Foundation

/// The language the app shows, overriding the system's as macOS allows each app: kept as this
/// app's own `AppleLanguages`, which Foundation reads once, at launch. A change therefore shows
/// after a restart, which the settings offer.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german = "de"
    case french = "fr"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    private static let key = "AppleLanguages"

    /// The name in its own language, so it can be found whatever language the app shows.
    var nativeName: String {
        switch self {
        case .system: ""
        case .english: "English"
        case .german: "Deutsch"
        case .french: "Français"
        case .chinese: "简体中文"
        }
    }

    /// The language this app was set to, read from its own domain only: `UserDefaults.standard`
    /// would answer with the system's list when the app has none.
    static var current: AppLanguage {
        guard let domain = Bundle.main.bundleIdentifier,
              let saved = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String],
              let first = saved.first else { return .system }
        return AppLanguage(rawValue: first) ?? .system
    }

    /// The language the running app shows, which a change does not alter until a restart.
    static let atLaunch = current

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
    }

    /// Opens a new instance and quits this one. The new one waits for this one to have gone
    /// before it starts Soloist (`AppDelegate`), as both would use one data directory.
    @MainActor static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
