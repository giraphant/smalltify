//
//  SoloistSettingsSection.swift
//  Spotifly
//
//  The Playback tab's Soloist section: its key, whether plays go to it, and how it is doing.
//

import SwiftUI

struct SoloistSettingsSection: View {
    @Bindable private var soloist = SoloistService.shared
    @State private var key = ""

    var body: some View {
        Section {
            SecureField("preferences.soloist.key", text: $key,
                        prompt: Text(soloist.hasKey ? "preferences.soloist.key_saved" : "preferences.soloist.key_prompt"))
            Toggle("preferences.soloist.prefer", isOn: $soloist.preferred)
            Picker("preferences.soloist.cache", selection: $soloist.cacheGB) {
                ForEach(SoloistService.cacheSizesGB, id: \.self) { size in
                    Text(verbatim: "\(size) GB").tag(size)
                }
            }
            LabeledContent("preferences.soloist.status") {
                status
            }
            HStack {
                Spacer()
                Button("preferences.soloist.stop") { Task { await soloist.stop() } }
                    .disabled(!soloist.isRunning)
                Button(soloist.isRunning ? "preferences.soloist.save_restart" : "preferences.soloist.save_start") {
                    let entered = key
                    key = ""
                    Task { await soloist.save(key: entered) }
                }
                .disabled(soloist.state == .starting || (!soloist.hasKey && key.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        } header: {
            Text("preferences.soloist")
        } footer: {
            Text("preferences.soloist.footer")
        }
    }

    @ViewBuilder private var status: some View {
        switch soloist.state {
        case .notConfigured: Text("preferences.soloist.state.not_configured").foregroundStyle(.secondary)
        case .stopped: Text("preferences.soloist.state.stopped").foregroundStyle(.secondary)
        case .starting: Text("preferences.soloist.state.starting").foregroundStyle(.secondary)
        case .waitingForPairing: Text("preferences.soloist.state.pairing").foregroundStyle(.orange)
        case .ready: Text("preferences.soloist.state.ready").foregroundStyle(.green)
        case let .failed(message): Text(verbatim: message).foregroundStyle(.red)
        }
    }
}
