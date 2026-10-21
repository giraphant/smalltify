# Redesign: Kurzbefehle

Status: **Open**, planned 2026-10-21. Thirteenth of the stacked redesign PRs
Components: `Spotifly/SpotiflyApp.swift`, `Spotifly/ViewModels/PlaybackViewModel.swift`,
`Spotifly/*.lproj/Localizable.strings`
Found: 2026-10-21, `design_handoff_spotifly_macos/README.md` ("Interactions", Shortcuts)

## Summary

The handoff's shortcuts the app lacks are added: ⌘↑ / ⌘↓ for the volume in the Playback menu,
and ⌃⌘S to show or hide the sidebar in the View menu.

## Problem

The handoff lists Space, ⌘→ / ⌘←, ⌘↑ / ⌘↓, ⌘L, ⌘F, ⌃⌘S, ⌥⌘I and ⌘,. The app has all of them
but two: nothing changes the volume from the keyboard, and the View menu has no sidebar item
(it shows "Tableiste einblenden", "Mini-Player", "Jetzt läuft"), so ⌃⌘S does nothing.

## Solution

### API

Nothing new. The volume steps go through `PlaybackViewModel.setVolumeFromSlider`, so they move
what the bar's slider moves: this Mac's volume, or the active remote device's while another
device plays.

### Commands

- Playback menu: "Lauter" ⌘↑ and "Leiser" ⌘↓, after Previous, ten points a step, clamped to
  0–100. Greyed while the device playing controls its own volume (`sliderRefused`), as the
  slider is.
- `SidebarCommands()`, which puts "Seitenleiste einblenden/ausblenden" (⌃⌘S) in the View menu.
- The handoff's "Prev restarts after 4 s" is already 3 s, as Spotify's clients and librespot
  do it (`plans/done/previous-restarts-past-three-seconds.md`); kept.

The Settings window's read-only list of these is the next PR.

## Verification

- Build, unit tests (the step's clamping).
- Run the Debug build: ⌘↑ / ⌘↓ move the bar's slider; ⌃⌘S hides and shows the sidebar; the
  menus list both.
