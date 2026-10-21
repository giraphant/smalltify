//
//  AudioSink.swift
//  Spotifly
//
//  Where the pipeline's decoded audio goes
//

import Foundation

/// What became of a buffer handed to `AudioSink.enqueue`.
enum AudioSinkEnqueued: Sendable {
    case accepted
    /// Discarded by a flush, or the caller's task was cancelled.
    case flushed
    /// The output changed under the sink — another device, AirPlay — and it
    /// dropped what it had queued. The caller has to fill it again from the
    /// playhead.
    case outputChanged
    case failed
}

/// An output the pipeline pushes interleaved 44.1 kHz stereo Float32 PCM into and paces itself
/// on: `AudioRenderer`, or `StreamingPlayerSink` behind the Debug menu's switch.
///
/// The contract the pipeline relies on: `enqueue` suspends until the output wants more, and a
/// paused output wants nothing, so the decode waits out a pause inside it; the first buffer after
/// a `restart` plays at playhead zero and each one after it directly follows, which is all the
/// pipeline's gapless playback is; `playedFrames` is the audible playhead since that `restart`.
protocol AudioSink: Actor {
    func enqueue(_ samples: Data, frames: Int) async -> AudioSinkEnqueued
    /// Discards everything queued and starts the playhead again at zero, running or held.
    func restart(paused: Bool) async
    func pause() async
    func resume() async
    /// Stops playout and discards what is queued.
    func stop() async
    /// Whether the output has stopped asking for audio it needs, which a refill from the
    /// playhead then mends.
    var isStalled: Bool { get async }
    /// Frames played out since the last `restart`: the audible playhead.
    nonisolated var playedFrames: Int64 { get }
    /// The output gain, 0…1, after the perceptual curve.
    nonisolated func setVolume(_ volume: Float)
}
