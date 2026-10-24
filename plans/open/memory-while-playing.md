# Memory while playing: what the testing run's 344 MB is made of

Status: **Open**, 2026-10-24, #222 (`memory/footprint`). On this Mac playing costs about 110 MB
over an idle app, all of it audio buffering, and holds steady: no leak. 16-bit samples take
15 MB off it. The HomePod's share and the pages' share are unmeasured: the screen was locked.
Components: `Spotifly/AudioOutput.swift`, `Spotifly/SwiftLibrespot/Audio/AudioPipeline.swift`
Found: 2026-10-24, in Ralph's run of the testing plan: Activity Monitor showed 344 MB for a Debug
build about 3½ minutes after launch, playing on the Küche HomePod, after the mini player and
closing and reopening the window. The plan expected 200–260 MB.

## Summary

Nothing grows while playing. A Release build on this Mac sits at 75 MB idle and about 186 MB
playing, flat over four minutes and across track changes; a Debug build at 93 and 220 MB. What
playing adds is buffered audio, about half of it AVFoundation's: a byte cache for the item, and
a "CoreMedia HTTP Cache" that fills to 32 MB and stops. The output now writes 16-bit samples
instead of Float32, which halves its own buffer and AVFoundation's byte cache: 172 MB playing.

## Problem

### Measured on this Mac

Each build was launched alone and played over Spotify Connect, moved from the web player (the
screen was locked), with `footprint` read every 20 s.

| Build | Idle | Playing, settled | Over the run |
|---|---|---|---|
| Debug, Float32 | 93 MB | about 220 MB | flat for 2½ minutes, across a track change |
| Release, Float32 | 76 MB | about 186 MB | flat; 211 MB for some seconds while a track downloads |
| Release, 16-bit | 75 MB | 166–179 MB, by the tracks' length | flat over four minutes |

### What playing holds

Release builds, Float32 → 16-bit, from `footprint`'s categories and `heap`, the large blocks
traced to their allocation with `MallocStackLogging=lite` and `malloc_history`:

- **AVFoundation's byte cache for the item**: one block, allocated in MediaToolbox's
  `FigCRABSCreate` when the stream starts. 25 MB → 14 MB.
- **"CoreMedia HTTP Cache"**: 32 MB either way. It fills to 32 MB and stops there; with 16-bit
  samples it takes twice as long to fill. No API sizes it.
- **The output's stream chunks**: 30 s written ahead, a minute kept behind the player's reader.
  About 21 MB → 10 MB.
- **The pipeline's Ogg data** for the current and the next track (`PreparedTrack.ogg`): 15–20 MB.
- **Sample buffers** in the player: 4–6 MB.
- **A download**, for some seconds per track: its ciphertext, its plaintext and the Ogg copy at
  once, about 25–30 MB more.

### Not measured yet

- **The HomePod.** A Debug build playing there measured 278–294 MB (`plans/done/airplay-stalls.md`),
  about 60–75 MB above this Mac. Writing 120 s ahead all the time cost about 150 MB more there
  (`AudioOutput.aheadLimit`),
  far more than the 32 MB of chunks it adds, so the AirPlay path holds buffers that grow with
  what is written. Whether 16-bit samples halve those is open.
- **The pages and the window.** Ralph's run had been through the pages, the mini player and a
  closed and reopened window before the reading. Whether a closed window's views are freed, and
  what a tour of the pages leaves behind (covers, the 323-row table), needs the screen unlocked.
- **Debug's own cost**: 17 MB idle and 34 MB playing on this Mac, so a Debug reading is above
  what a release uses.

## Solution

- **Done here: 16-bit samples** (`AudioOutput.int16`). The output converts the pipeline's Float32
  buffers before writing them; the CAF header says 16-bit integers. Nothing audible is lost:
  Spotifly plays Ogg Vorbis only, whose coding noise lies far above 16 bits', and the player's
  volume applies after the samples. A future lossless format at 24 bits would want its own look.
- **Not done**: the download's transient copies (decrypting in place, keeping a slice of the
  plaintext instead of an `[UInt8]` copy) would only lower the peaks; the HTTP cache has no
  setting.
- **Next**: with the screen unlocked, five closes and reopens of the window and a tour of the
  pages, `footprint` before and after; then a Release build on the HomePod, Float32 against
  16-bit.

## Verification

- Unit tests, with a new one that reads the header and converted samples back through Core
  Audio: the samples come back to 16 bits, out-of-range ones at full scale.
- The 16-bit Release build played over Connect: the web player showed it playing on Spotifly,
  its position advancing in real time. Measured as in the table.
- To do: listening on this Mac and on the HomePod with the 16-bit stream, and the measurements
  under "Next".
