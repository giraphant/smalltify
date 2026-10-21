# On a HomePod, the player can stop answering pause and seek

Status: **Open**, 2026-10-21. A likely cause is addressed in #220 (`airplay/stalls`): the output
writes 30 s ahead, as far as the player reads, instead of 10 s. Checked on this Mac only; not yet
on a HomePod, which needs the AirPlay picker and so an unlocked screen.
Components: `Spotifly/AudioOutput.swift`
Found: 2026-10-21, rerunning #219's checks on the Küche HomePod: a seek took 18 s, and the app
crashed when it landed (the crash is fixed on #219, 10a9e89).

## Summary

On a HomePod the player now and then ran its buffer empty about 5 s after a seek, with 10 s
written ahead of what was heard, and paused itself; the output played it again at once. Twice,
some time after such a stall, the player stopped controlling the item: `pause()` set its rate to
0 while the item's clock ran on at rate 1, the HomePod went on playing, and every seek stayed
unfinished until the next one replaced it. Pause from the app or another device did nothing; only
quitting the app stopped the sound. Writing as far ahead as the player reads should keep it from
stalling; whether that also keeps it out of the stuck state is not known yet.

## Problem

### What was seen

Times are UTC. Diagnostics logged around each seek the item's time, its timebase rate, the
player's rate and status, `isPlaybackBufferEmpty`, and once a second while a seek was in flight.

- **Stalls after seeks.** In about twenty seeks on the HomePod, two were followed about 5 s later
  by the player pausing itself with an empty buffer (20:44:07 → 20:44:12.99 and 20:48:41 →
  20:48:46.55): `player rate 0, timebase rate 0, bufferEmpty 1`. The output played it again 100 ms
  later. Four minutes of playback without seeks had no stall.
- **Stuck seeks.** At 20:55:25, six and a half minutes after the second stall, a seek began with
  the player playing (`player rate 1, timebase rate 1`). `pause()` set the player's rate to 0, but
  the timebase kept rate 1, and the item's time ran on: 717 s at the seek, 828 s a minute after
  the last of eight more seeks, none of which finished. Each was "superseded" by the next, 7 s
  later. A pause from the web player at 20:58:12 left the HomePod playing at the same level
  (−48.6 dB at the Mac's microphone, −52.3 dB before). Quitting the app silenced it.
- **The crash**, earlier: a stall at 20:30:04, a seek at 20:30:09 that finished at 20:30:28. The
  item had played on through what was written ahead into the new run, the pipeline had taken the
  next track over gaplessly, and the late seek moved the playhead back 8 s, behind that track's
  start; the pipeline trapped converting the negative position.
- On this Mac, through the LG display, no seek ever took longer than 60 ms, and no stall followed
  one.

### What it points to

The probe measured the player reading up to 30 s ahead of what is heard here, and 25 s on the
HomePod. Over AirPlay the Mac sends ahead of what the receiver plays, so after a seek, when the
receiver's buffer refills, the player's read position can run into the end of what the output has
written while the audible playhead is only 5 s in. That fits the stalls coming about 5 s after a
seek, with `bufferEmpty`, and only on the HomePod.

What puts the player into the stuck state is not established. Both times it followed a stall the
output had answered with `playImmediately(atRate: 1)` on an empty buffer, but one such stall
(20:44:12) was followed by seeks that worked. No public API reports or repairs the state.

## Solution

On `airplay/stalls`:

- `enqueue` keeps 30 s written ahead of the playhead instead of 10 s, which makes the starvation
  rule (feed up to 30 s while the player stands still or waits) and its resume stamp unnecessary:
  both are gone.
- The stream keeps a minute of audio behind the player's reads instead of 8 MB (24 s), so it still
  reaches back past what plays, now 30 s behind what is written.
- A seek still in flight after 2 s is logged, with the item's rate: "Seek N not done after 2 s;
  the item plays at rate 1.0" is the stuck state.

### Tried and dropped

- **`automaticallyWaitsToMinimizeStalling = true`**, so the player would wait out a stall instead
  of pausing and being restarted. It never started: it waits for a rate of incoming data, and the
  output writes as the playhead moves, so after the first 30 s nothing more came. A preferred
  forward buffer of 5 s did not change that. The comment at the setting says so.

### If it comes back

Next to try, in this order: play a stalled player again only once its buffer is no longer empty;
on a seek that is not done after 2 s while the item plays, set the rate to 1 and pause again, to
put the player's rate and the item's back in step.

## Verification

- Build, unit tests.
- This Mac, through a Connect handover from the web player (the screen was locked): eight seeks in
  27–37 ms, none logged as not done; a pause and resume, 10.10 s of audio between them in 10.08 s;
  a gapless track change one 250 ms tick after it was due.
- **Not done: the HomePod.** Route Spotifly to it, keep it quiet, and seek twenty times or more,
  a few seconds apart, then pause and check it stops. Pass: no "not done after 2 s", no "Paused
  by itself" other than in the same millisecond as a "Seek to … done" (that one is the seek's own
  pause, read late), and every pause silent.
