//
//  StreamingPlayerSink.swift
//  Spotifly
//
//  The probe's audio output: the pipeline's PCM played by an AVPlayer, as one stream
//

import AVFoundation
import CoreMedia
import Synchronization

/// Plays the pipeline's PCM through an `AVPlayer`, so the native AirPlay picker can send it, and
/// nothing else of the Mac's audio, to a receiver (`plans/open/avplayer-output-probe.md`).
///
/// The player's item is a stream this sink writes as the pipeline pushes: a CAF of 44.1 kHz
/// stereo Float32 PCM, served through a resource loader under a custom scheme, its data chunk
/// declared a day long. One item serves the session: an item started while an AirPlay receiver
/// is chosen never asks its loader for a byte, so a `restart` (a load, a seek) is a seek within it
/// to where the new audio begins, the end of what is written. Between tracks the stream runs on,
/// so the next track is the next sample, as with the renderer. Nothing is decoded ahead as a
/// whole file: `enqueue` returns once what is written ahead of the playhead is under
/// `aheadTarget`, or at once while the player waits for data.
actor StreamingPlayerSink: AudioSink {
    nonisolated static let sampleRate = 44100
    nonisolated static let channelCount = 2
    nonisolated static let bytesPerFrame = MemoryLayout<Float>.size * channelCount

    /// Written ahead of the playhead before `enqueue` waits. The player keeps a buffer of its own
    /// ahead of what is heard; with 3 s it starved after a resume and stood still.
    private static let aheadTarget = 10.0
    /// Written ahead at most, whatever the player says, so a player that never starts does not
    /// take the whole track into memory.
    private static let aheadLimit = 30.0

    /// The session's stream, and the number of the run in it: a buffer waiting across a
    /// `restart` is not counted as the new run's.
    private var stream: PCMStream?
    private var generation = 0
    /// Frames written to the stream, all runs together.
    private var streamFrames: Int64 = 0
    /// Where the current run begins in the stream: the playhead's zero. Read from any thread.
    private nonisolated let origin = Mutex<Int64>(0)
    /// Runs a stream holds before the next restart begins a new one: a day, less ten minutes.
    private static let streamCapacity = PCMStream.declaredFrames - Int64(sampleRate * 600)
    /// The playhead when it last moved, and when that was: a player that plays and does not
    /// move wants data it has not got, which it does not say while it does not wait to play.
    private var lastPlayhead: (frames: Int64, at: ContinuousClock.Instant) = (0, .now)

    private nonisolated let requestedVolume = Mutex<Float>(1)

    /// The output, the player the AirPlay picker binds. On the main actor, as the player's KVO
    /// and the picker are.
    nonisolated var output: StreamingPlayerOutput {
        StreamingPlayerOutput.shared
    }

    // MARK: - Feeding

    func enqueue(_ samples: Data, frames: Int) async -> AudioSinkEnqueued {
        guard !Task.isCancelled, let stream else { return .flushed }
        let generation = generation

        stream.append(samples)
        streamFrames += Int64(frames)

        while true {
            if Task.isCancelled || generation != self.generation {
                return .flushed
            }
            let played = playedFrames
            if played != lastPlayhead.frames {
                lastPlayhead = (played, .now)
            }
            let written = streamFrames - origin.withLock { $0 }
            let ahead = Double(written - played) / Double(Self.sampleRate)
            let starved = output.isPlaying && lastPlayhead.at.duration(to: .now) > .milliseconds(300)
            if ahead < Self.aheadTarget || ((output.isWaitingForData || starved) && ahead < Self.aheadLimit) {
                return .accepted
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Playback Control

    func restart(paused: Bool) async {
        generation += 1
        if stream != nil, streamFrames < Self.streamCapacity {
            origin.withLock { $0 = streamFrames }
            await output.seek(toFrame: streamFrames, paused: paused)
            return
        }
        stream?.close()
        streamFrames = 0
        origin.withLock { $0 = 0 }
        let stream = PCMStream(generation: generation)
        self.stream = stream
        let volume = requestedVolume.withLock { $0 }
        await output.play(stream, paused: paused, volume: volume)
    }

    func pause() async {
        await output.pause()
    }

    func resume() async {
        await output.resume()
    }

    /// Holds the item where it is: the next `restart` seeks past what it played.
    func stop() async {
        generation += 1
        await output.pause()
    }

    /// The player waits for data itself, and follows a change of output on its own.
    var isStalled: Bool {
        false
    }

    /// The item's playhead from the run's origin. Until a seek to the origin has taken, the
    /// item is behind it, which counts as zero.
    nonisolated var playedFrames: Int64 {
        let seconds = output.playheadSeconds
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return max(0, Int64(seconds * Double(Self.sampleRate)) - origin.withLock { $0 })
    }

    // MARK: - Volume

    nonisolated func setVolume(_ volume: Float) {
        let volume = max(0, min(1, volume))
        requestedVolume.withLock { $0 = volume }
        Task { @MainActor in StreamingPlayerOutput.shared.setVolume(volume) }
    }
}

// MARK: - Output

/// The `AVPlayer` the sink plays its streams through, and the one the AirPlay picker binds.
@MainActor
final class StreamingPlayerOutput {
    nonisolated static let shared = StreamingPlayerOutput()

    let player: AVPlayer

    /// The item's timebase, read from any thread for the playhead.
    private nonisolated let timebase = Mutex<CMTimebase?>(nil)
    /// Whether the player wants data it has not got, and whether it is playing, read from the
    /// sink's actor.
    private nonisolated let waiting = Mutex(false)
    private nonisolated let playing = Mutex(false)

    private let playerObservation: NSKeyValueObservation
    private var itemObservation: NSKeyValueObservation?
    private var restartedAt: ContinuousClock.Instant?
    private var stream: PCMStream?
    private var diagnostics: Task<Void, Never>?
    /// Whether the sink means the player to play. A player that stalls with nothing to wait for
    /// pauses itself, and stays paused: measured on resuming on a HomePod, where it flipped to
    /// paused 70 ms after playing, with data loaded beyond the playhead.
    private var wantsToPlay = false

    private nonisolated init() {
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        // The Mac renders and sends the audio to a receiver itself. Allowed to, the player hands
        // a new item's URL to the receiver, which cannot open this app's scheme: an item started
        // on the HomePod (after a seek) never asked the loader for a byte.
        player.allowsExternalPlayback = false
        self.player = player
        // KVO calls in on any thread: the handlers are `@Sendable` and hop to the main actor.
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable player, _ in
            let status = player.timeControlStatus
            let reason = player.reasonForWaitingToPlay?.rawValue
            Task { @MainActor in StreamingPlayerOutput.shared.timeControlStatusChanged(status, reason: reason) }
        }
    }

    nonisolated var playheadSeconds: Double {
        timebase.withLock { $0.map { CMTimebaseGetTime($0).seconds } } ?? 0
    }

    nonisolated var isWaitingForData: Bool {
        waiting.withLock { $0 }
    }

    nonisolated var isPlaying: Bool {
        playing.withLock { $0 }
    }

    func play(_ stream: PCMStream, paused: Bool, volume: Float) {
        self.stream = stream
        timebase.withLock { $0 = nil }
        restartedAt = .now

        let asset = AVURLAsset(url: stream.url)
        asset.resourceLoader.setDelegate(stream, queue: stream.queue)
        let item = AVPlayerItem(asset: asset)
        item.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        itemObservation = item.observe(\.status, options: [.new]) { @Sendable item, _ in
            let status = item.status
            let error = item.error.map { "\($0)" }
            let itemTimebase = item.timebase.map { UncheckedTimebase(timebase: $0) }
            Task { @MainActor in
                StreamingPlayerOutput.shared.itemStatusChanged(status, timebase: itemTimebase, error: error, stream: stream.generation)
            }
        }

        player.volume = volume
        player.replaceCurrentItem(with: item)
        wantsToPlay = !paused
        if paused {
            player.pause()
        } else {
            player.playImmediately(atRate: 1)
        }
        debugLog("PlayerSink", "Stream \(stream.generation): new item, \(paused ? "held" : "playing")")

        // The probe's measurements: where the playhead is against what the player has loaded.
        diagnostics?.cancel()
        diagnostics = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let item = player.currentItem else { continue }
                let loaded = item.loadedTimeRanges.last.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds } ?? 0
                debugLog("PlayerSink", String(format: "Stream %d: playhead %.2f s, loaded to %.2f s, rate %.0f, keeping up %@", stream.generation, playheadSeconds, loaded, player.rate, item.isPlaybackLikelyToKeepUp ? "yes" : "no"))
            }
        }
    }

    /// Moves the item to `frame`, where the next run's audio will be written, and plays from
    /// there or holds. The loader answers the range request this makes as the audio arrives.
    func seek(toFrame frame: Int64, paused: Bool) {
        restartedAt = .now
        let generation = stream?.generation ?? 0
        wantsToPlay = !paused
        if paused {
            player.pause()
        }
        let time = CMTime(value: frame, timescale: CMTimeScale(StreamingPlayerSink.sampleRate))
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            Task { @MainActor in
                debugLog("PlayerSink", "Stream \(generation): seek to \(String(format: "%.2f", time.seconds)) s \(finished ? "done" : "superseded") after \(StreamingPlayerOutput.shared.elapsedMs()) ms")
            }
        }
        if !paused {
            player.playImmediately(atRate: 1)
        }
    }

    func pause() {
        wantsToPlay = false
        player.pause()
    }

    func resume() {
        wantsToPlay = true
        player.playImmediately(atRate: 1)
    }

    func setVolume(_ volume: Float) {
        player.volume = volume
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, timebase itemTimebase: UncheckedTimebase?, error: String?, stream generation: Int) {
        guard generation == stream?.generation else { return }
        switch status {
        case .readyToPlay:
            timebase.withLock { $0 = itemTimebase?.timebase }
            debugLog("PlayerSink", "Stream \(generation): ready after \(elapsedMs()) ms")
        case .failed:
            debugLog("PlayerSink", "Stream \(generation): failed: \(error ?? "?")")
        default:
            break
        }
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus, reason: String?) {
        waiting.withLock { $0 = status == .waitingToPlayAtSpecifiedRate }
        playing.withLock { $0 = status == .playing }
        switch status {
        case .playing:
            debugLog("PlayerSink", "Playing, \(elapsedMs()) ms after the restart")
        case .waitingToPlayAtSpecifiedRate:
            debugLog("PlayerSink", "Waiting: \(reason ?? "?")")
        case .paused where wantsToPlay:
            // Stalled: nothing else will start it again.
            debugLog("PlayerSink", "Paused by itself; playing again")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, wantsToPlay, player.timeControlStatus == .paused else { return }
                player.playImmediately(atRate: 1)
            }
        case .paused:
            debugLog("PlayerSink", "Paused")
        @unknown default:
            break
        }
    }

    private func elapsedMs() -> Int {
        guard let restartedAt else { return -1 }
        let elapsed = restartedAt.duration(to: .now)
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

/// A timebase carried from KVO's thread to the main actor. `CMTimebase` is thread-safe; it is
/// only not marked `Sendable`.
private struct UncheckedTimebase: @unchecked Sendable {
    let timebase: CMTimebase
}

// MARK: - Stream

/// One item's bytes: a CAF header, then PCM as the sink writes it, served to the player's
/// resource loader from a window of what has been written.
///
/// Confined to `queue`, the loader's delegate queue: appends hop onto it, and the loader calls
/// in on it. Requests for bytes not yet written wait for them.
final nonisolated class PCMStream: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let generation: Int
    let url: URL
    let queue: DispatchQueue

    /// The data chunk's declared length: a day of audio, far longer than a session plays.
    static let declaredFrames = Int64(StreamingPlayerSink.sampleRate * 86400)
    private static let declaredDataBytes = declaredFrames * Int64(StreamingPlayerSink.bytesPerFrame)

    private let header: Data
    private var storage = Data()
    /// Stream offset of `storage`'s first byte.
    private var storageStart: Int64 = 0
    private var written: Int64 = 0
    private var pending: [AVAssetResourceLoadingRequest] = []
    private var closed = false

    init(generation: Int) {
        self.generation = generation
        url = URL(string: "spotifly-stream://pcm/\(generation).caf")!
        queue = DispatchQueue(label: "PCMStream \(generation)")
        header = Self.cafHeader(dataBytes: Self.declaredDataBytes)
        super.init()
        storage = header
        written = Int64(header.count)
    }

    /// How far past what is written a request must start to be the player's look at the end.
    private static let tailThreshold: Int64 = 256 * 1024 * 1024

    private var declaredLength: Int64 {
        Int64(header.count) + Self.declaredDataBytes
    }

    func append(_ samples: Data) {
        queue.async { [self] in
            guard !closed else { return }
            storage.append(samples)
            written += Int64(samples.count)
            serve()
        }
    }

    func close() {
        queue.async { [self] in
            closed = true
            for request in pending where !request.isFinished {
                request.finishLoading(with: CancellationError())
            }
            pending.removeAll()
            storage = Data()
        }
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard !closed else { return false }
        if let info = request.contentInformationRequest {
            info.contentType = "com.apple.coreaudio-format"
            info.contentLength = declaredLength
            info.isByteRangeAccessSupported = true
        }
        if let data = request.dataRequest {
            debugLog("PlayerSink", "Stream \(generation): request at \(data.requestedOffset), \(data.requestsAllDataToEndOfResource ? "to the end" : "\(data.requestedLength) bytes"), \(written) written")
            // The player reads the declared end before it plays, to look for chunks after the
            // data. That far into the data chunk is audio no one will reach: silence answers it.
            if data.requestedOffset > written + Self.tailThreshold {
                let end = data.requestsAllDataToEndOfResource
                    ? declaredLength
                    : min(declaredLength, data.requestedOffset + Int64(data.requestedLength))
                data.respond(with: Data(count: Int(min(end - data.requestedOffset, 4 * 1024 * 1024))))
                request.finishLoading()
                return true
            }
            pending.append(request)
            serve()
        } else {
            request.finishLoading()
        }
        return true
    }

    func resourceLoader(_: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        pending.removeAll { $0 === request }
    }

    /// Answers every waiting request with what has been written for it, finishes those that have
    /// all they asked for, and lets go of bytes no request can still want.
    private func serve() {
        pending.removeAll { request in
            guard !request.isFinished, !request.isCancelled, let data = request.dataRequest else { return true }
            let offset = data.currentOffset
            guard offset >= storageStart else {
                debugLog("PlayerSink", "Stream \(generation): asked for \(offset), before the kept \(storageStart)")
                request.finishLoading(with: URLError(.dataNotAllowed))
                return true
            }
            let end = data.requestsAllDataToEndOfResource
                ? written
                : min(written, data.requestedOffset + Int64(data.requestedLength))
            if end > offset {
                let from = storage.startIndex + Int(offset - storageStart)
                data.respond(with: storage.subdata(in: from ..< storage.startIndex + Int(end - storageStart)))
            }
            let wanted = data.requestedOffset + Int64(data.requestedLength)
            if !data.requestsAllDataToEndOfResource, data.currentOffset >= wanted {
                request.finishLoading()
                return true
            }
            return false
        }
        trim()
    }

    /// Keeps 8 MB behind the earliest offset a waiting request is at, about 24 s of audio, for a
    /// player that asks again a little way back.
    private func trim() {
        let earliest = pending.compactMap { $0.dataRequest?.currentOffset }.min() ?? written
        let keepFrom = earliest - 8 * 1024 * 1024
        guard keepFrom - storageStart > 16 * 1024 * 1024 else { return }
        storage.removeFirst(Int(keepFrom - storageStart))
        storageStart = keepFrom
    }

    // MARK: CAF

    /// A CAF header for interleaved little-endian Float32 stereo at 44.1 kHz: the file header,
    /// the `desc` chunk, and the `data` chunk's header and edit count, 68 bytes.
    static func cafHeader(dataBytes: Int64) -> Data {
        var data = Data()
        func append(_ string: String) {
            data.append(contentsOf: Array(string.utf8))
        }
        func append(_ value: some FixedWidthInteger) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }

        append("caff")
        append(UInt16(1)) // version
        append(UInt16(0)) // flags

        append("desc")
        append(Int64(32))
        append(Float64(StreamingPlayerSink.sampleRate).bitPattern)
        append("lpcm")
        append(UInt32(1 | 2)) // float, little-endian
        append(UInt32(StreamingPlayerSink.bytesPerFrame)) // bytes per packet
        append(UInt32(1)) // frames per packet
        append(UInt32(StreamingPlayerSink.channelCount))
        append(UInt32(32)) // bits per channel

        append("data")
        append(dataBytes + 4) // the edit count is part of the chunk
        append(UInt32(0)) // edit count
        return data
    }
}
