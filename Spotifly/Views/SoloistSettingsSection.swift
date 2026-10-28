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
    @State private var confirmingReset = false

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
            if let error = soloist.pairingError, soloist.state == .waitingForPairing {
                Text(verbatim: error).foregroundStyle(.red)
            }
            HStack {
                if soloist.state == .waitingForPairing {
                    Button(soloist.pairing ? "preferences.soloist.pairing" : "preferences.soloist.pair") {
                        Task { await soloist.pair() }
                    }
                    .disabled(soloist.pairing)
                }
                if soloist.isRunning {
                    Button("preferences.soloist.reset") { confirmingReset = true }
                }
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
        .alert("preferences.soloist.reset.title", isPresented: $confirmingReset) {
            Button("preferences.soloist.reset.action", role: .destructive) { Task { await soloist.reset() } }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("preferences.soloist.reset.message")
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
