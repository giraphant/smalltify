# Probe: AVPlayer as the only audio output, streamed, with AirPlay from the shell

Status: **Open**, probed 2026-10-21 (PR #219): it works, locally and on the Küche HomePod, behind a
Debug switch; the renderer stays the default. Not yet heard by the user, nor its volume on a HomePod
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
  URL scheme, with a data chunk declared a day long. **One item serves the session**: a
  `restart` (a load, a seek) is a seek within it to the end of what is written, where the new
  audio begins (see Result for why). Between tracks the stream runs on, so a track change is the
  next sample, as with the renderer.
- Pacing: `enqueue` appends to the stream and returns once what is written ahead of the
  playhead is under a target (a few seconds); the loader answers `AVPlayer`'s requests from what
  is written, holding a request until the bytes exist.
- `playedFrames` from the item's timebase, so it is audible time, as `AVPlayer` accounts for an
  AirPlay receiver's latency.
- Volume: `AVPlayer.volume`.

`SpotifyPlayer` picks the sink at launch from a Debug menu toggle ("Use AVPlayer Output (from
Next Launch)"), or a launch argument, `-useAVPlayerOutput YES`.

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

### Result

Measured on 2026-10-21 with the switch on, macOS 27, Green Day's artist context, on the LG
display's speakers and on the Küche HomePod. Each line is from the `PlayerSink` log (a line every
5 s: the item's playhead, what it has loaded, its rate).

**Streaming works; nothing is decoded ahead as a file.** `AVPlayer` asks the loader for 2 bytes
at 0, then the stream from 0, and reads the declared end before it plays: with an hour declared,
the last 57 KB (aligned to 64 KB); with a day, at 1,667,301,376 and at the true end, 30.48 GB.
Those are answered with silence (zeros, at most 4 MB, then finished), which is what PCM that far
in would be; unanswered, the item never became ready. Then one sequential range request serves
the whole session, the loader answering it as the pipeline writes. Ready 51–65 ms after a load;
the pipeline feeds 10 s ahead of the playhead (the player loaded up to 30 s ahead locally, 25 s
on the HomePod), and drops bytes 8 MB behind what the player has read. Memory is bounded.

Findings, in the order they were met:

1. **Feeding 3 s ahead starved the player** after a resume: it stood still for 8 s reporting
   "playing". With `automaticallyWaitsToMinimizeStalling` off a starved player does not report
   waiting, so the sink also counts a player that plays and does not move for 300 ms as wanting
   data, and feeds 10 s ahead.
2. **An item started while a receiver is chosen never loads.** After a seek on the HomePod the
   new item asked the loader for nothing, with `allowsExternalPlayback` on or off. An item that
   started locally keeps playing after the switch. Hence one item per session, a restart being a
   seek within it: seeks then took 26–59 ms, locally and on the HomePod, and Next 57 ms.
3. **A stalled player pauses itself** (status paused, rate 1) and stays so; seen once on resuming
   on the HomePod. The output now plays it again when it pauses while meant to play; three
   pause/resume cycles on the HomePod after that were clean.

What held:

- **Gapless**, locally and on the HomePod: "follows without a gap", the playhead running on
  through the boundary (30.0 → 35.1 → 40.1 s; on the HomePod 93.3 → 98.3 → 103.3 s). The track
  change is inside one stream, so there is nothing for the player to join.
- **Output changes** (display speakers ↔ MacBook speakers, by setting the default output): the
  player follows on its own, losing 0.2–0.6 s of playhead around each; no stall workaround.
- **AirPlay from the bar's picker**: "Küche HomePod" ticked, the Mac's default output stayed the
  LG display, so only Spotifly went there; the switch cost about 0.9 s of playhead. Seek, Next,
  pause/resume and a track boundary on the HomePod as above; picking the Mac again went back
  without a stop. The picker keeps the HomePod across seeks, as the route belongs to the player.
- The renderer path, switch off, plays as before, and the bar shows its Wiedergabe-auf button.

Not yet known:

- Whether it sounds right: the user has not listened. Audible position on the HomePod against
  what Connect reports, and what a switch sounds like.
- The bar's volume on a HomePod (`AVPlayer.volume`); #202 found none reaching it.
- The one range request covers 1.67 GB, about 79 minutes of stream; what the player asks after
  it is untested, as is a session past a day's declared length (a restart then begins a new
  stream, which on a receiver would not load).
- CPU against the renderer, a Connect handover in and out, sleep and wake, receiver loss.

Codex found two, fixed: a failed item was only logged, so the decode waited on it forever and a
restart sought within it (now reported to the pipeline as `.failed`, and replaced on the next
restart); and Wiedergabe auf named the Mac's default output while Spotifly played on the HomePod
(left out in this mode).
