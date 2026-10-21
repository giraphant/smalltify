//
//  PreferencesView.swift
//  Spotifly
//
//  The settings window: General, Playback and Shortcuts, with the version at its foot
//

import SwiftUI

/// The redesign's settings window (`plans/done/redesign-settings.md`): only what the app acts on.
/// The handoff's offline cache, Dock and notification switches, volume levelling and Autoplay
/// have nothing behind them here, so they are not offered.
struct PreferencesView: View {
    var body: some View {
        // Each tab its own height, so the window fits the tab shown, as a settings window does.
        TabView {
            Tab("preferences.general", systemImage: "gearshape") {
                GeneralSettingsView()
                    .settingsPage(height: 90)
            }

            Tab("preferences.playback", systemImage: "speaker.wave.3") {
                PlaybackSettingsView()
                    .settingsPage(height: 170)
            }

            Tab("preferences.shortcuts", systemImage: "command") {
                ShortcutsSettingsView()
                    .settingsPage(height: 420)
            }
        }
    }
}

private extension View {
    /// A tab of the window: 600 pt wide, the height given, and the version at its foot.
    func settingsPage(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            frame(height: height)
            VersionFooter()
        }
        .frame(width: 600)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system

    var body: some View {
        Form {
            Picker("preferences.appearance", selection: Binding(
                get: { appearanceMode },
                set: { newValue in
                    appearanceMode = newValue
                    newValue.apply()
                },
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.titleKey).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: - Playback

private struct PlaybackSettingsView: View {
    @AppStorage("streamingBitrate") private var bitrateRawValue: Int = 1
    @AppStorage("gaplessPlayback") private var gaplessEnabled: Bool = true

    private var selectedBitrate: SpotifyPlayer.Bitrate {
        SpotifyPlayer.Bitrate(rawValue: UInt8(bitrateRawValue)) ?? .normal
    }

    var body: some View {
        Form {
            Section {
                Picker("preferences.streaming_quality", selection: Binding(
                    get: { selectedBitrate },
                    set: { newValue in
                        bitrateRawValue = Int(newValue.rawValue)
                        SpotifyPlayer.setBitrate(newValue)
                    },
                )) {
                    ForEach(SpotifyPlayer.Bitrate.allCases) { bitrate in
                        Text(verbatim: localizedNumberString("preferences.bitrate", bitrate.kilobitsPerSecond))
                            .tag(bitrate)
                    }
                }

                Toggle("preferences.gapless_playback", isOn: Binding(
                    get: { gaplessEnabled },
                    set: { newValue in
                        gaplessEnabled = newValue
                        SpotifyPlayer.setGapless(newValue)
                    },
                ))
            } footer: {
                Text("preferences.restart_note")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear {
            // Sync UI with actual player settings
            SpotifyPlayer.setBitrate(selectedBitrate)
            SpotifyPlayer.setGapless(gaplessEnabled)
        }
    }
}

// MARK: - Shortcuts

/// The app's shortcuts, read-only, each named as its menu item is. The keys are the ones
/// `SpotiflyCommands` and `SidebarCommands` set; a change there belongs here too.
private struct ShortcutsSettingsView: View {
    private static let shortcuts: [(name: LocalizedStringKey, keys: String)] = [
        ("menu.play_pause", String(localized: "preferences.shortcut.space")),
        ("menu.next_track", "⌘→"),
        ("menu.previous_track", "⌘←"),
        ("menu.volume_up", "⌘↑"),
        ("menu.volume_down", "⌘↓"),
        ("menu.like_track", "⌘L"),
        ("menu.search", "⌘F"),
        ("preferences.shortcut.sidebar", "⌃⌘S"),
        ("inspector.title", "⌥⌘I"),
        ("mini_player.menu", "⌥⌘M"),
        ("nav.back", "⌘["),
        ("nav.forward", "⌘]"),
        ("menu.favorites", "⌘1"),
        ("menu.playlists", "⌘2"),
        ("menu.albums", "⌘3"),
        ("menu.artists", "⌘4"),
        ("menu.refresh", "⌘R"),
        ("nav.settings", "⌘,"),
    ]

    var body: some View {
        Form {
            ForEach(Self.shortcuts, id: \.keys) { shortcut in
                LabeledContent(shortcut.name) {
                    Text(verbatim: shortcut.keys)
                        .monospaced()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Footer

/// The version and where the source lives, under every tab.
private struct VersionFooter: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(String(localized: "app.name")) \(version)")
            Text("metadata.separator")
            Link(destination: URL(string: "https://github.com/ralph/Spotifly")!) {
                Text(verbatim: "github.com/ralph/Spotifly")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
    }
}
