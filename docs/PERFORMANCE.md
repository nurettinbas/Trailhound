# UI performance notes

Trailhound optimizes frame time in a few hot paths. Use this when profiling regressions.

## Vehicle pairing editor

- Edits use `VehicleEditorDraft` and persist on **Save** only (no SwiftData writes per keystroke).
- Visual chrome matches the rest of the app (`glassListChrome()` / `glassRow()`); draft keeps keyboard work off the model layer.

## Trips list scroll (recording card)

- Trips list hides in-progress recordings with `endedAt == nil` (in-memory filter). Do not add ad-hoc SwiftData schema fields without a versioned migration plan.
- Card frame for stop credits is kept inside `ActiveTripView` (not propagated to `TripListView` on every scroll frame).
- Road + exhaust animation uses `RecordingCarAnimationView`; `TimelineView` only runs while recording, unpaused, and the card is on-screen.

## Active recording card

- GPS and persistence still run at full rate; on-screen stats use `RecordingDisplaySampler` (~4 Hz / 250 ms).
- The recording card no longer shows a live mini-map (only the car animation + stats).
- Stop credits still use `LiveBreadcrumbCanvas` briefly.
- The road animation pauses when another tab is selected or the card scrolls off-screen (`isRecordingCardInViewport`).
- `TimelineView` runs only while the road animation is active (paused / off-screen = static frame).
- List scroll avoids per-frame `@State` updates from filter landing geometry; recording-card anchor preferences are throttled.

## Trip detail reveal

`TripDetailRevealPolicy` controls the opening route animation:

| Point count | Behavior |
|-------------|----------|
| ≤ 300 | ~16 ticks, full map styling during reveal |
| 301–1500 | ~12 ticks, flat map + single polyline stroke during reveal |
| > 1500 | Instant reveal (no animation) |

Reduce Motion always uses instant reveal.

## Trip list search

- Filter uses `debouncedSearchText` (250 ms) so typing does not re-filter the full list every keypress.

## Inactive tabs

- Stats, Pairing, Settings, and Dev Log views mount only while their tab is selected (Trips stays mounted for the recording card).

## Profiling checklist

1. Instruments → Time Profiler + Core Animation on device.
2. Pairing → edit vehicle name with keyboard — should feel smooth vs list screens.
3. Start recording, scroll trip list, switch tabs — CPU should drop on non-Trips tabs.
4. Open a long trip detail — should not hitch for multi-second map reveal.
