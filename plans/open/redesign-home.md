# Redesign: Startseite

Status: **Open**, planned 2026-10-21. Fifth of the stacked redesign PRs
Components: `Spotifly/Views/StartpageView.swift`, `Spotifly/Store/Services/HomeService.swift`,
`Spotifly/Store/AppStore.swift`, `Spotifly/PartnerAPI/PathfinderHome.swift`,
`Spotifly/PartnerAPI/PathfinderTopContent.swift` (new), `Spotifly/PartnerAPI/PathfinderOperations.swift`,
`Spotifly/PartnerAPI/PartnerAPI.swift`, `Spotifly/PartnerAPI/PathfinderEntities.swift`,
`Spotifly/Views/LoggedInView.swift`, `Spotifly/*.lproj/Localizable.strings`
Found: 2026-10-21, `design_handoff_spotifly_macos/README.md` ("Startseite"), `design/native/Screens.jsx`
(`NHome`)

## Summary

The start page becomes the handoff's four sections: Zuletzt gehört, Deine Top-Titel with a
4 Wochen / 6 Monate / 1 Jahr picker, Deine Top-Künstler, and Deine Playlists with "Alle
anzeigen". Top tracks and artists come from pathfinder's `userTopContent`, which the web
player's profile page uses; the rest is already loaded.

## Problem

The page draws whatever shelves Spotify's `home` sends (a greeting, "Für llralphj", mixes,
radio, …). The handoff asks for four fixed sections. `StartpageView` dropped fixed sections
once because "none of which exist on the client APIs" — top tracks and artists do exist there,
measured below.

## Solution

### API (measured 2026-10-21 in the web player, Chrome)

- **Top tracks and artists:** `userTopContent`, persisted query
  `61b7353d3625780022dbc63d459eb64cd609e7e5e2a820f9160d65030efe2e15`, variables
  `{includeTopArtists, topArtistsInput: {offset, limit, sortBy: "AFFINITY", timeRange},
  includeTopTracks, topTracksInput: {…}}`. `timeRange` takes `SHORT_TERM`, `MID_TERM` and
  `LONG_TERM` (200); `MEDIUM_TERM`, `MEDIUM`, `MID` and `SIX_MONTHS` are refused with 400
  "invalid input value … AffinityTimeRange!". The three ranges returned different lists. A top
  track is a pathfinder `Track` with `uri`, `name`, `albumOfTrack {name, uri, coverArt}`,
  `artists.items[] {profile.name, uri}`, `duration.totalMilliseconds` — and **no `id`**, so
  `Track(pathfinder:)` takes the id from the uri, as `PathfinderAlbum` already does. A top
  artist is `{profile.name, uri, visuals.avatarImage}`, the shape `PathfinderArtist` decodes.
  Captured responses become the decoding test's fixture.
- **Zuletzt gehört:** the `home` response the app already loads has a section typed
  `HomeRecentlyPlayedSectionData` ("Zuletzt") holding one list of the 20 contexts last played,
  names and covers included, in the `List` entries the app already decodes. It is kept apart
  from the other shelves by that typename. (spclient's `recently-played/v3` returns the same
  contexts as bare uris, which would need hydrating one by one.)
- **Deine Playlists:** the library's playlists, `AppStore.userPlaylistIds`, loaded at login.

### Layout

`ScrollView` with 28 pt insets:

1. "Zuletzt gehört": horizontal `LazyHStack` of 150 pt cards.
2. "Deine Top-Titel" with a segmented `Picker` in its header; an adaptive `LazyVGrid`
   (min 260 pt) of rows: rank, 36 pt cover, title over artist, a separator. A double-click
   plays the top tracks from that one, as a list.
3. "Deine Top-Künstler": round 130 pt artist cards in a row (medium term).
4. "Deine Playlists": the first nine library playlists as cards, and a `.link` button "Alle
   anzeigen" that opens Playlists.

The toolbar gets Refresh (⌘R does the same already), reloading `home` and the top content.
Spotify's other shelves (mixes, radio, "Für …") are no longer shown, as the handoff has it.

## Verification

- Unit test: `userTopContent` decodes the captured response into tracks with ids from their
  uris, and artists.
- Build, unit tests.
- Run the Debug build and screenshot the page; switch the range picker and see the list change;
  double-click a top track and see it play; "Alle anzeigen" opens Playlists.
