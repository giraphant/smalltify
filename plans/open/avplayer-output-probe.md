# Probe: AVPlayer as the only audio output, streamed, with AirPlay from the shell

Status: **Open**, planned 2026-10-21. A probe behind a Debug switch; the renderer stays the default
Components: `Spotifly/AudioRenderer.swift`, `Spotifly/StreamingPlayerSink.swift` (new),
`Spotifly/SwiftLibrespot/Audio/AudioPipeline.swift`, `Spotifly/SpotifyPlayer.swift`,
`Spotifly/Views/AirPlayRoutePickerView.swift`, `Spotifly/Views/NowPlayingBarView.swift`,
`Spotifly/Views/SpeakersView.swift`, `Spotifly/SpotiflyApp.swift`
Found: 2026-10-21, `plans/open/spotifly-only-airplay.md` on PR #202, and the user: "try AVPlayer
for everything … and get around the whole file needs to be decoded restriction"

## Summary

Only an `AVPlayer` can be sent to AirPlay by itself on macOS (`AVRoutePickerView.player`), so
#202 hands playback over between the renderer and an `AVPlayer` playing one whole decoded song.
This probe tries the other way: `AVPlayer` for all output, fed as one continuous stream, so
AirPlay is a choice in the native picker rather than a mode, and nothing is decoded ahead of
need.

## Problem

- #202's handover is the costly part: two clocks, two volume paths, a one-song limit that
  refuses next-track commands, no gapless or queue on AirPlay, and an "AirPlay verwenden" step
  before the picker.
- Its `AVPlayer` played a complete CAF of a decoded song: 74 MB and 0.9 s of preparation for
  3.5 minutes, written before a note plays. Streaming was named and not tried.
- #202 rejected `AVPlayer` for everything "without evidence". Its tests are not to be relied on
  much; this probe measures its own.

## Solution

### The seam

`AudioPipeline` pushes Float32 PCM into one sink and paces itself on it: `enqueue` suspends until
the output wants more, `restart`, `pause`, `resume`, `stop`, `playedFrames` for the audible
playhead, `isStalled`, `setVolume`. It already decodes the next track into the same sink behind
the current one, which is all its gapless playback is. A second sink with the same contract
leaves the pipeline, Connect and the queue untouched:

- `AudioSink`, a protocol both sinks conform to; `AudioRenderer` unchanged apart from it.
- `StreamingPlayerSink`, an `AVPlayer` whose item is a stream the sink writes: a CAF of
  44.1 kHz stereo Float32 PCM, served through an `AVAssetResourceLoader` delegate under a custom
  URL scheme, with a data chunk declared far longer than anything plays. Each `restart` (a load,
  a seek) starts a new item; between tracks the stream runs on, so a track change is the next
  sample, as with the renderer.
- Pacing: `enqueue` appends to the stream and returns once what is written ahead of the
  playhead is under a target (a few seconds); the loader answers `AVPlayer`'s requests from what
  is written, holding a request until the bytes exist.
- `playedFrames` from the item's timebase, so it is audible time, as `AVPlayer` accounts for an
  AirPlay receiver's latency.
- Volume: `AVPlayer.volume`.

`SpotifyPlayer` picks the sink at launch from a Debug menu toggle ("Use AVPlayer Output",
stored, read at the next launch).

### Measured, each logged under `PlayerSink`

1. Start: from `restart` to the timebase running, for a load and a seek, against the renderer.
2. What `AVPlayer` asks the loader for: offsets, lengths, whether it reads sequentially, how far
   ahead it buffers, and whether it ever asks for bytes not yet written.
3. Track changes: no stall at a boundary on a gapless album (the stream does not break there).
4. Position: what Connect reports against what is heard.
5. Output changes: switching speakers in Control Center, without the renderer's stall
   workaround.
6. AirPlay from the bar's picker, mid-song, Safari staying on the Mac: the user listens.

If `AVPlayer` will not play an open-ended stream, the fallback is a per-track item of exact
length, decoded on demand from byte ranges, in an `AVQueuePlayer`, with gapless measured.

### Shell

- `AirPlayRoutePickerView` binds the sink's player, so the picker routes Spotifly alone.
- Bar: the AirPlay button becomes that picker while this Mac plays (the system highlights it
  while a receiver is chosen); with another Connect device playing, or with the renderer, it
  opens Wiedergabe auf, as now.
- Wiedergabe auf: the AirPlay row's picker, bound the same way.
- Volume: the bar's slider is this Mac's player volume; on a receiver, its own volume is the
  slider in the picker's menu (#202 found no app-side gain reaching a HomePod).

## Verification

- Build, unit tests; renderer behaviour unchanged with the switch off.
- With the switch on: play, pause, seek, skip, a gapless album across a boundary, a Connect
  handover; the `PlayerSink` log for 1–5; the user picks the HomePod and listens for 6.
