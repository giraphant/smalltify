# Smalltify 界面重设计：实现交接

The app's current UI is being rebuilt to this design. The window framework is in place on
branch `ui/rebuild`: navigation, sidebar, toolbar, banner and toast, the shared components,
and placeholder pages. Each module below replaces its placeholders.

## The design

- `boards/*.png`: the 14 boards, rendered from the design file.
- `source/*.html`: each board's markup and logic, readable as text. Labels, copy, states and
  interactions are exact here; the CSS is not a spec.
- `Smalltify 界面重设计.html`: the original file; it opens in a browser.
- `../SMALLTIFY-DESIGN-BRIEF.md`: the feature brief the design answers. It says what the Web
  API and Soloist can and cannot do. Do not build anything listed under 做不到的.

**Fidelity:** layout, hierarchy, copy, states and behavior follow the boards. Visual detail
comes from the system: native SwiftUI controls, system materials, fonts and selection.
Where the HTML imitates a control, use the real control. The one brand value is the accent,
`#1DB954`, already the app's `AccentColor`. The UI is Chinese.

## Modules

| Module | Boards | Owns (may create and edit) |
|---|---|---|
| W1 文库列表页 | 01 | `UI/Pages/PlaylistsPage.swift`, `AlbumsPage.swift`, `ArtistsPage.swift`, `LikedSongsPage.swift`; `Debug/FixtureData+Library.swift`; `SpotiflyTests/LibraryPagesTests.swift` |
| W2 详情页 | 05, 06, 07 | `UI/Pages/AlbumPage.swift`, `PlaylistPage.swift`, `ArtistPage.swift`; new `UI/Components/DetailHero.swift`; new `Spotifly/Smalltify/LibraryWrites.swift`; `Debug/FixtureData+Detail.swift`; `SpotiflyTests/DetailPagesTests.swift` |
| W3 搜索与首页 | 02, 03 | `UI/Pages/SearchPage.swift`, `StartPage.swift`; `Debug/FixtureData+Discover.swift`; `SpotiflyTests/DiscoverPagesTests.swift` |
| W4 播放器 | 04, 08, 09, 14 | everything in `UI/Player/`; `SoloistController.swift`, `SoloistSnapshot.swift`, `SpotifyConnectController.swift`, `OfficialConnect*.swift`; in `SmalltifyModel.swift` only the bodies of `play(_:in:)` and `enqueue(_:)`; in `UI/Shell/SmalltifyCommands.swift` only the 播放 menu; `Debug/FixtureData+Player.swift`; `SpotiflyTests/PlayerTests.swift` |
| W5 设置与输入 | 10, 11 (paste-link part), 12 (shortcuts) | everything in `UI/Settings/`; `PlaylistShortcuts.swift`, `SavedPlaylist.swift`; `Debug/FixtureData+Settings.swift`; `SpotiflyTests/SettingsTests.swift` |

Everything else is shared, and the coordinator owns it: `SmalltifyModel.swift` (apart from
the two function bodies above), `Navigation.swift`, `Notices.swift`, `PagedLoader.swift`,
`CatalogItem.swift`, `CatalogArtist.swift`, `OfficialWebAPI.swift`, `UI/Shell/*`,
`UI/Components/*` (apart from new files a module creates), `Debug/DebugFixtures.swift`,
`Debug/FixtureData.swift`, `SpotiflyApp.swift`.
**If you need a change in a shared file, ask the coordinator.** Do not edit it yourself.
Five modules merge into one branch, and a shared file edited twice conflicts.

## How the framework works

- **Pages** are views in `UI/Pages`, one per `Destination` case. `DestinationView` maps
  them. A page reads the model with `@Environment(SmalltifyModel.self)`, and sets its own
  `.navigationTitle` and `.navigationSubtitle`. The toolbar shows them, as in the boards.
- **Navigation:** `model.navigator.go(.album(item))`, or `model.open(item)`,
  `model.open(artist)` and `model.open(albumRef)`. Back and forward are the navigator's.
  An album or playlist page may be given a stub item (uri and name only). It loads the rest.
- **Loading:** `model.pagedLoader("<destination.key>/<name>", url:)` gives a `PagedLoader`,
  kept in `model.pages` so back and forward show it at once. ⌘R refreshes every loader whose
  key starts with the page's `Destination.key`. Call `loader.loadIfNeeded()` in `.task`.
  For one-off objects (an album's details), write a small `@Observable` loader of your own
  conforming to `Refreshable`. Store it the same way: `model.pages.loader(key) { ... }`.
  Failures go to `model.report(_:)`, which turns expired logins and rate limits into the
  banner. A page shows its own load failure with `PageFailureView`.
- **States:** `LoadedContent(loader:)` covers signed out, first load, failure and empty
  before your content shows. `SignedOutView`, `PageFailureView`, `LoadingRows` and
  `LoaderFooter` are there for pages that compose their own.
- **Track lists:** `TrackList` (`UI/Components/TrackList.swift`) is the one list of tracks.
  It handles columns, sorting, filter, selection, double-click and Return to play, the
  context menu (`TrackMenu`), the playing indicator, and loading more. Its `header` scrolls
  with the rows, which is where a detail page's header goes.
- **Cards:** `CatalogCard`, `CatalogGrid`, `CatalogShelf` and `PageSection`
  (`UI/Components/Cards.swift`). Artists are round.
- **Artwork:** `CoverArt(item:size:)` and `CoverArt(artist:size:)`. It picks an image size
  for the display and caches it.
- **Artist and album names:** `ArtistLinks(artists:fallback:)` and `AlbumLink`. Each name is
  a link the window routes. They show in secondary color, as the boards do.
- **Playback:** `model.play(uri:)` plays a whole item. `model.play(track, in: context)`
  plays a track within an album, playlist or the collection. `model.enqueue(track)` adds it
  to the queue and shows a toast. Toasts: `model.notices.toast("已存到常用歌单")`.
- **Web API:** `model.api.get(url)` for reads. `OfficialWebAPI.apiURL(path:query:)` builds
  urls. `model.api.send(method:path:query:body:)` does library writes. Every request is
  logged by `OfficialWebAPI`. Send `market=from_token` where an endpoint takes it. The token
  carries the scopes in `OfficialWebAPI.scopes`.
- **Names:** the upstream app's views are still compiled (`Spotifly/Views`, `Spotifly/Store`).
  Do not use them, and avoid their type names: `Route`, `TrackRow`, `CardGrid`,
  `UserProfile`, `HomePage`, `Artwork`, `DetailHeader` and others. `DetailHeader` is the
  one exception. It is generic and may be reused.

## Checking your work

Build and test (simulator warnings in the output are harmless):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -quiet -project Spotifly.xcodeproj -scheme Spotifly -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Spotifly.xcodeproj -scheme Spotifly -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO test -only-testing:SpotiflyTests
```

Three tests fail on `main` already: `KeymasterCallbackTests` "both bundled pages link back…"
and the two `LocalizationTests` "every English string…" and "every key the code names…".
Any other failure is yours.

**Fixture mode:** run the Debug build against canned responses, then look at it. It never
touches the account, the Keychain or Soloist. **Never run the app outside fixture mode.**
That would read the user's real credentials and start their player.

```bash
APP=build/DerivedData-Debug/Build/Products/Debug/Spotifly.app/Contents/MacOS/Spotifly
SMALLTIFY_FIXTURES=1 SMALLTIFY_ROUTE=album:潮汐电台 SMALLTIFY_SNAPSHOT=/tmp/album.png "$APP"
```

- `SMALLTIFY_ROUTE`: `home`, `liked`, `playlists`, `albums`, `artists`, `search:<q>`,
  `album:<name>`, `playlist:<name>`, `artist:<name>`. Names come from `FixtureData`, e.g.
  `album:潮汐电台`, `playlist:海边的周末` (someone else's: its tracks answer 403),
  `artist:马洛·韦尔`, `search:无结果` (empty results).
- `SMALLTIFY_DARK=1` for dark mode; `SMALLTIFY_INSPECTOR=1` opens 正在播放.
- `SMALLTIFY_OPEN=<name,…>` is for your code to read with `DebugFixtures.opens("<name>")`.
  Use it to open a popover, sheet or window at launch, so it shows in the snapshot.
- The snapshot writes the main window to the path, and other windows (popovers, sheets,
  settings, mini player) beside it as `<path>.1.png` and so on. The app then quits.
  `SMALLTIFY_DUMP=1` prints every table and its row count.
- **Known limits:** the sidebar's rows do not draw in snapshots, because its material is not
  captured. They are there: `SMALLTIFY_DUMP=1` shows 9 rows. The snapshot window is never key,
  so prominent buttons draw in their inactive gray instead of the accent green. Snapshot runs
  are invisible on screen, so they do not interrupt the user.
- Add the endpoints your pages need in your `FixtureData+<Area>.swift`. The shared catalog
  (artists, albums, tracks, playlists) and helpers (`page`, `ok`, `images`) are in
  `FixtureData.swift`.

Compare each snapshot with its board, in light and dark mode.
