# An AirPlay receiver is dropped when the bar's picker is rebuilt

Status: **Done**, 2026-10-24, on #220 (`airplay/stalls`); checked on the Küche HomePod.
Components: `Spotifly/Views/AirPlayRoutePickerView.swift`, `Spotifly/Views/SpeakersView.swift`
Found: 2026-10-24, in Ralph's run of the testing plan: after a pause the HomePod played on for a
few seconds after Resume, then the music came from the Mac.

## Summary

A route chosen in an `AVRoutePickerView` lives with that picker. Once the picker is gone and
another is bound to the player, macOS releases the routing context that held the receiver, and
the player falls back to the Mac a few seconds later. SwiftUI rebuilt the bar's picker whenever
the bar was rebuilt: after a reconnect or a Connect handover, which swap it for the Playing On
button and back, and on leaving the mini player. Now one picker serves the whole run, and the
places that show it only borrow it.

## Problem

Times are local. Ralph's run: paused at 16:45:21; at 16:46:16 Spotify reset the accesspoint
connection, the app reconnected and came back "No longer the active device", so the bar replaced
its picker with the Playing On button. Resume at 16:46:56.68 made it the active device again
(16:46:57.21), and the bar made a new picker. The system log:

- 16:46:57.218, `audiomxd`: "Adding context E3F8F879-… of type Audio" for Spotifly, the new
  picker's.
- 16:47:00.326, `audiomxd`: "MXAudioContext_HandleContextRemoval: Going to empty AirPlay
  aggregate and deactivate endpoint due to routing context finalize"; `AirPlayXPCHelper`:
  "Deactivating endpoint 'Küche HomePod' with reason 'RemovedFromAggregate'". The app's own log
  shows only the playhead standing still at 16:47:01.

Reproduced on purpose with nothing else going on: routed and playing, the mini player on and off
deactivated the HomePod at 17:11:20. Opening Playing On, which had a second picker, and going back
did not, while the bar's picker, where the HomePod had been chosen, stayed.

This also explains #219's "a paused Spotifly loses its receiver after a Connect handover".

## Solution

`AirPlayRoutePickerView` holds one `AVRoutePickerView`, made on first use and bound to the
player, and hands each place an empty container it puts the picker in; letting go takes it out
again without ending it, unless another place has taken it since. An `NSView` has one superview,
so the picker shows in one place at a time, the one made last. So Playing On's AirPlay section no
longer has a picker of its own; it says to choose a receiver with the AirPlay button in the
player bar, and keeps the footer on what goes there and where the receiver's volume is set.

## Verification

- Build, unit tests (the localization tests included).
- Küche HomePod, at 10 %, routed and playing: the mini player on and off, Playing On and back, a
  connection dropped by `SPOTIFLY_DEBUG_DROP_AP_AFTER` while paused and then Resume (the bar went
  to the Playing On button and back), and the window closed and reopened. No deactivation in the
  system log after any of them, and the picker still had the HomePod ticked; the picker opened and
  worked after each move.
- Not run: a Connect handover to another device and back, which takes the bar through the same
  swap as the reconnect.
