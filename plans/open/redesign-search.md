# Redesign: Suchen

Status: **Open**, planned 2026-10-21. Sixth of the stacked redesign PRs
Components: `Spotifly/Views/SearchResultsView.swift`, `Spotifly/Views/SearchAllTracksView.swift` (goes),
`Spotifly/Views/SearchHomeView.swift` (new), `Spotifly/Views/LoggedInContentRouterView.swift`,
`Spotifly/Views/LoggedInView.swift`, `Spotifly/Views/SidebarView.swift`, `Spotifly/Models/Route.swift`,
`Spotifly/ViewModels/NavigationCoordinator.swift`, `Spotifly/Store/Services/SearchService.swift`,
`Spotifly/Store/AppStore.swift`, `Spotifly/PartnerAPI/PartnerAPI.swift`, `SpotiflyTests/NavigationCoordinatorTests.swift`
Found: 2026-10-21, `design_handoff_spotifly_macos/README.md` ("Suchen"), `design/native/Screens.jsx` (`NSearchScreen`)

## Summary

"Suchen" becomes a sidebar item with a page of its own: recent searches while the field is
empty, and with a query, a segmented scope — Alle, Songs, Künstler, Alben, Playlists — over the
results, where a single scope pages further with "Mehr laden".

## Problem

Search is a toolbar field whose results page appears as a sidebar row only once there are
results. There are no recent searches, no scopes, and "show all" exists for tracks alone, as a
page of its own; the other kinds stop at the first 20.

## Solution

### API

The four pathfinder searches (`searchTracks`, `searchAlbums`, `searchArtists`,
`searchPlaylists`) already take `offset` and `limit` in `PathfinderSearchVariables`; the app
always sent offset 0. "Mehr laden" sends the next offset for the scope shown. Podcasts are left
out of the scopes: the app has no page that opens a show or an episode, and the handoff's own
prototype shows none for it either.

### Navigation

- `NavigationItem.searchResults` is always in the sidebar, titled "Suchen". Selecting it reopens
  the last search, as today, or the search page with no query.
- `Route.showsAllTracks` becomes `Route.searchScope` (`all`, `tracks`, `artists`, `albums`,
  `playlists`): a scope is a step in the history, as the old all-tracks page was and as the web
  player's search tabs are. `showAllSearchTracks()` becomes `showSearchScope(_:)`.
- Emptying the field goes to the search page instead of the start page.

### Page

- No query: `Form(.grouped)` with Section "Letzte Suchen" (footer "Wird nur auf diesem Mac
  gespeichert."), each row a button that searches it again and a remove button; "Verlauf
  löschen" below. No history: `ContentUnavailableView("Keine letzten Suchen")`. The toolbar field
  takes focus when the page opens.
- A query: the segmented scope picker, then per kind a heading and its results — five per kind
  under Alle, all loaded ones under a single scope with "Mehr laden" at the end. Songs are rows
  (`TrackRow`, double-click plays radio, as today), the others cards (artists round 120 pt,
  albums and playlists 140 pt with "year · artist" / "von owner"). Nothing found:
  `ContentUnavailableView("Keine Ergebnisse für „…“")`.
- Recent searches are kept by `SearchService` in `UserDefaults` (ten, newest first, a repeat moved
  to the top), added when a search succeeds.

## Verification

- Unit tests: the coordinator's history tests moved to scopes; recent searches' order and cap.
- Build, unit tests.
- Run the Debug build: open Suchen (field focused, recent searches), search, switch scopes, load
  more albums, go back through the scopes, clear the history.
