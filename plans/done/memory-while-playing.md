# Memory while playing: what the testing run's 344 MB is made of

Status: **Done**, 2026-10-24, #222 (`memory/footprint`). No leak: playing holds steady, the
window frees what it held, and the pages' data is a one-time cost. The output now streams 16-bit
samples, about 40 MB less on a HomePod; Ralph heard no difference there.
Components: `Spotifly/AudioOutput.swift`
Found: 2026-10-24, in Ralph's run of the testing plan: Activity Monitor showed 344 MB for a Debug
build about 3½ minutes after launch, playing on the Küche HomePod, after the pages, the mini
player and a closed and reopened window. The plan expected 200–260 MB.

## Summary

The reading adds up without a leak. A Release build sits at 75 MB idle; playing on this Mac
takes it to about 160–210 MB, depending on the tracks' size, and it stays there; the pages'
library data and covers add about 40 MB once; a HomePod adds about 85–90 MB, most of it macOS's
AirPlay sending, freed when the route ends; a Debug build is 15–35 MB above a Release one. The
output's stream now carries 16-bit samples instead of Float32, which halves its own buffer and
AVFoundation's byte cache for the item: on the HomePod 251 MB instead of 293.

## Problem

### How it was measured

Release builds of `main` (Float32) and of this branch (16-bit), each launched alone, with
`footprint` read every 15–20 s; the large blocks traced to their allocation with
`MallocStackLogging=lite` and `malloc_history`. The first runs played over Spotify Connect from
the web player while the screen was locked; the rest were driven through accessibility, the
HomePod at 10 % on its own slider.

### Playing on this Mac

| Build | Idle | Playing, settled |
|---|---|---|
| Debug, Float32 | 93 MB | about 220 MB |
| Release, Float32 | 76–87 MB | 186 MB; 199–208 MB in a later run |
| Release, 16-bit | 75 MB | 159–179 MB |

Flat over four minutes and across track changes; for some seconds while a track downloads,
25–30 MB more. What playing holds:

- **AVFoundation's byte cache for the item**: one block, allocated in MediaToolbox's
  `FigCRABSCreate` when the stream starts. 25 MB with Float32, 14 MB with 16-bit.
- **"CoreMedia HTTP Cache"**: fills to 32 MB and stops, with either format. No API sizes it.
- **The output's stream chunks**: 30 s ahead, a minute behind the player's reader. About 21 MB
  with Float32, 10–13 MB with 16-bit.
- **The pipeline's Ogg data** for the current and the next track (`PreparedTrack.ogg`): 15–20 MB.
- **The player's sample buffers**: 1.4 MB each, the same with either format, so the player's own
  decoded audio: 3–4 of them here.
- **A download**: its ciphertext, plaintext and the Ogg copy at once, for some seconds per track.

### The window and the pages (16-bit, playing on this Mac)

- **Closing and reopening the window**, 20 times: within 3 MB of the baseline, Malloc Small 69 MB
  before, 72 MB after 10 and after 20. The mini player, five times: 1 MB.
- **A tour of every page**, three times: Malloc Small 73 → 100 → 113 → 110 MB. About 40 MB the
  first two times, then nothing more: the library's data and covers, kept for the next visit.

### On the HomePod

Each build played two minutes here, then was paused, routed to the Küche HomePod and resumed:

| Build | This Mac | Küche HomePod, settled |
|---|---|---|
| Release, Float32 | 199–208 MB | 292–294 MB |
| Release, 16-bit | about 165 MB | 248–264 MB, mostly 251 |

What the HomePod adds, with either format:

- **About 57 MB of graphics memory** ("Owned physical footprint (unmapped) (graphics)", 2.6 MB
  on this Mac): macOS's AirPlay sending, which holds it while the route is up. Back on the Mac
  it was gone at once; opening the picker on the Mac adds none.
- **About 17 MB more of the player's sample buffers**: 15–16 of them, about a minute of decoded
  audio held for the receiver.
- **Malloc Small**: 40 MB more with Float32, 20 MB with 16-bit. The HomePod takes in what is
  written at once, so the player holds more of the stream; the route change also lets the
  output write up to 120 s ahead while the playhead stands still (`AudioOutput.aheadLimit`).

### The 344 MB, put together

A Debug build (about 15–35 MB above Release) playing Float32 on the HomePod (Release 293 MB),
after the pages (about 40 MB): roughly 350 MB, as read.

## Solution

**16-bit samples** (`AudioOutput.int16`): the output converts the pipeline's Float32 buffers
before writing them, and the CAF header says 16-bit integers. Nothing audible is lost: Spotifly
plays Ogg Vorbis only, whose coding noise lies far above 16 bits', and the player's volume
applies after the samples. A future lossless format at 24 bits would want its own look.

Left as they are:

- **The HomePod's graphics memory and sample buffers** are macOS's, and no API sizes them.
- **The HTTP cache** fills to 32 MB whatever is streamed.
- **The pages' caches** are what makes going back to a page instant.
- **A download's copies** (decrypting in place, keeping a slice of the plaintext instead of an
  `[UInt8]` copy) would only lower a peak of some seconds.

## Verification

- Unit tests, with a new one that reads the header and converted samples back through Core
  Audio: the samples come back to 16 bits, out-of-range ones at full scale.
- The measurements above, Release builds of both formats.
- Ralph listened on the Küche HomePod to both builds: no difference he could hear. The 16-bit
  build played on this Mac throughout the window and page runs.
