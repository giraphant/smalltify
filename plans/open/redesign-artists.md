# Redesign: Künstler

Status: **Open**, planned 2026-10-21. Tenth of the stacked redesign PRs
Components: `Spotifly/Views/ArtistDetailView.swift`, `Spotifly/Views/LoggedInToolbars.swift`,
`Spotifly/Views/Components/AlbumCard.swift`, `Spotifly/*.lproj/Localizable.strings`
Found: 2026-10-21, `design_handoff_spotifly_macos/README.md` ("Playlists / Alben / Künstler"),
`design/native/Library.jsx` (`NArtists`)

## Summary

The artist page gets the detail header (round art, "Künstler", the name, Abspielen and a follow
toggle) and a "Diskografie" grid with a segmented picker for Alben, Singles & EPs and
Compilations; the toolbar gets Share and a menu.

## Problem

- The artist page centres a 200 pt photo over the name, then lists albums five at a time with
  "show all"; singles and compilations are mixed in with the albums.
- Its toolbar is a share button that copies the link, and a follow or unfollow button.

## Solution

### API

Nothing new. `queryArtistDiscographyAll`, which the page already reads with `limit: 100`,
returns every release with its `type`, kept as `Album.albumType`. Measured in the web player on
2026-10-21 for Green Day: 81 releases, typed `ALBUM` (27), `SINGLE` (48), `EP` (1) and
`COMPILATION` (7); `queryArtistDiscographyOverview` counts them as albums 26, singles 48,
compilations 7, so the web player files EPs under singles, as the handoff's "Singles & EPs" does.

What the handoff leaves out stays out: no top tracks, listeners or followers. Its genre tags
are not shown either: neither artist operation the app reads returns genres.

### Artist page

- `DetailHeader`: round 132 pt art, "Künstler", the name, Abspielen (the artist's context,
  as Spotify's clients play it) and a bordered toggle "Folge ich" / "Folgen". Unfollowing keeps
  its confirmation, and the page stays, as an album's does.
- "Diskografie" (`SectionHeader`) with a segmented `Picker`: Alben, Singles & EPs (singles and
  EPs), Compilations; a `LazyVGrid` (adaptive, min 150 pt) of the shared `AlbumCard` with the
  release year as its subtitle. A group with nothing in it says so.

### Toolbar

Share and a menu: Abspielen, Folgen / Nicht mehr folgen, Link kopieren, through the builder
albums and playlists use, which learns to leave out "Als Nächstes spielen". The old
`ShareToolbarButton`, which copied the link and was the artist page's last user, goes.

## Verification

- Build, unit tests.
- Run the Debug build: an artist with all three kinds (Green Day), switch the groups, open a
  release, Abspielen (then pause), follow and unfollow an artist not followed before, Share.
