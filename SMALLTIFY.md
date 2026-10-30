# Smalltify

Smalltify is upstream Spotifly 1.4.0 (`6077b513`, https://github.com/ralph/Spotifly, MIT), with its
interface and its data layer as they are, plus three things: Spotify Soloist as the player, so that
lossless plays; a Simplified Chinese translation with a language setting; and its own name, icon and
signing. The earlier Smalltify, a rebuilt interface on the public Web API, is on the `ui/rebuild`
branch.

## Why Soloist

Spotifly's own player (`SwiftLibrespot`) asks Spotify's accesspoint for each file's key. Spotify
answers that for Ogg Vorbis, up to 320 kbit/s, but gives the keys to its lossless FLAC files only
to its own players, through its DRM (librespot reached the same conclusion:
https://github.com/librespot-org/librespot/issues/1583). Soloist is one of Spotify's own players,
so the app runs it as the Connect device "Smalltify" and sends plays to it
(`PlaybackViewModel.playbackTarget`).

Soloist signs in with the app's own login (`SoloistPairing`): Spotify Connect's ZeroConf
`addUser`, which is what an official app sends when the device is chosen in its list. Its quality,
Lossless included, is still set once in an official app's device list, as for any Connect device.
Measured 2026-10-28: about 634 and 1330 kbit/s per track, where 320 kbit/s Ogg came to 293.

## Build

1. `make fetch-soloist` downloads the current Soloist for macOS from Spotify's official address,
   the one https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates
   links, into `build/soloist/`. `scripts/stage-soloist.py` accepts any build that carries
   Spotify's own signature (`com.spotify.soloist`, team `2FNC3A47ZF`) and refuses everything
   else. It does not pin a hash: Spotify rebuilds Soloist every few days and a build expires 90
   days after it is signed (exit status 10), so the script prints that date and warns two weeks
   ahead; fetch again then.
2. `make build` builds, stages Soloist into `Contents/Helpers`, and signs with the Developer ID
   in the Makefile (override it in `Makefile.local`). The first signing asks the Keychain for the
   key; "Always Allow" keeps later builds from asking.

**The app with Soloist inside is for this Mac only.** Spotify does not allow the Soloist binary
to be redistributed, so it goes into no release.

## Setup

1. Sign in with "Connect with Spotify".
2. Settings → Playback → Soloist: paste the Soloist API key from
   https://developer.spotify.com/dashboard and press Save and Start. Smalltify signs Soloist in
   with the same account.
3. In an official Spotify app, choose Lossless for "Smalltify" once, in its device list.

Settings → General → Language picks English, Deutsch, Français or 简体中文 over the system's
language, after a restart.

Identity: bundle id `io.github.giraphant.smalltify`, the same as the earlier Smalltify, so its
sandbox container, its Soloist pairing (`Smalltify/Soloist`) and its Soloist API key carry over.
