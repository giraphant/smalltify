# Redesign: Warteschlange

Status: **Open**, planned 2026-10-21. Eleventh of the stacked redesign PRs
Components: `Spotifly/Views/QueueListView.swift`, `Spotifly/Views/Components/TrackTable.swift`,
`Spotifly/*.lproj/Localizable.strings`, `Spotifly/*.lproj/Localizable.stringsdict`
Found: 2026-10-21, `design_handoff_spotifly_macos/README.md` ("Warteschlange"),
`design/native/Screens.jsx` (`NQueue`)

## Summary

The queue becomes the track table the other pages use, under a large "Warteschlange" title with
"N Titel · M ausstehend".

## Problem

The queue lists `TrackRow`s under a small material header, the one list left that is not the
redesign's table.

## Solution

### API

Nothing new: the rows are `PlayerModel.queueEntries`, as now, and a double-click plays a row
through `PlaybackViewModel.play(queueRow:)`.

**What the handoff asks for and the app has not got.** Its toolbar has "Alle in den
Offline-Cache laden" and its rows a "C" tag for a track in the offline cache. The app keeps no
offline cache (nothing in `SwiftLibrespot` writes audio to disk), so neither is built. The
handoff's "C" reads as the tag the queue already shows, the row's provider: Q for a track
queued by hand, C for one from the context, A for autoplay. That tag stays, now in the table.
The queue stays read-only plus append, as the handoff says.

### Page

- Header: "Warteschlange" in the large title style, then "N Titel · M ausstehend", then, as now,
  "Wird abgespielt von „X“ auf Y" with the context as a link.
- `TrackTable` with #, Titel, Dauer, not sortable: the numbers run over the whole queue, rows
  already played are dimmed, as `TrackRow` dimmed them, and each row carries its provider tag.
- The toolbar keeps Refresh and "Zum aktuellen Titel scrollen"; the table scrolls to the
  current row (`ScrollViewReader` on the table's row ids).
- `TrackTableRow` gains `isPast` and `tag`, which only the queue sets.

## Verification

- Build, unit tests.
- Run the Debug build with something queued: the counts, the tags, the dimmed rows, the
  current row in the accent colour, a double-click on a next row (then pause), scroll to
  current.
