# Spotifly fork with Soloist

Upstream Spotifly 1.4.0 (`6077b513`, https://github.com/ralph/Spotifly), built for this Mac,
with Spotify Soloist as the player so that lossless plays. Everything else is upstream's.

## Why Soloist

Spotifly's own player (`SwiftLibrespot`) asks Spotify's accesspoint for each file's key. Spotify
answers that for Ogg Vorbis, up to 320 kbit/s, but gives the keys to its lossless FLAC files only
to its own players, through its DRM (librespot reached the same conclusion:
https://github.com/librespot-org/librespot/issues/1583). Soloist is one of Spotify's own players,
so the app runs it as a Connect device and sends plays to it.

## Build

1. Download Soloist for macOS from https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates
   and put `soloist` (and `THIRD_PARTY_LICENSES.txt`) in `build/soloist/`. Nothing is fetched by
   the build; `scripts/stage-soloist.py` refuses any binary but the pinned 1.3.10.19 with
   Spotify's signature.
2. `make build` builds, stages Soloist into `Contents/Helpers`, and signs with the Developer ID
   in the Makefile (override it in `Makefile.local`).

**The app with Soloist inside is for this Mac only.** Spotify does not allow the Soloist binary
to be redistributed, so it goes into no release.

## Setup

1. Sign in with "Connect with Spotify", as upstream.
2. Settings → Playback → Soloist: paste the Soloist API key from
   https://developer.spotify.com/dashboard and press Save and Start.
3. In an official Spotify app, choose "Spotifly Soloist" once in the device list, and set its
   quality to Lossless there.

From then on Soloist starts and stops with the app, and with "Play through Soloist" on, plays go to
it. Its builds expire after about 90 days; the settings say so when it happens.
