# UI performance notes

Trailhound optimizes frame time in a few hot paths. Use this when profiling regressions.

## Vehicle pairing editor

- Edits use `VehicleEditorDraft` and persist on **Save** only (no SwiftData writes per keystroke).
- Visual chrome matches the rest of the app (`glassListChrome()` / `glassRow()`); draft keeps keyboard work off the model layer.
- Optional vehicle photos are 256 px JPEG/PNG thumbs on disk (`VehiclePhotoStore`); SwiftData stores only `photoFileName`. Decode/resize runs off the main actor; list rows use a memory cache hit when scrolling.
- Identity surfaces (pairing rows, recording capsule, trip/stats vehicle filters, trip-detail picker) reuse `VehicleAvatarView` + `VehiclePhotoStore.prefetch` so thumbs are warm before scroll/chips appear.
- Recording road animation (`RecordingCarAnimationView` in TrailhoundShared) accepts a **pre-decoded** `UIImage?` plus optional `systemImage` from the app. Shared never opens photo files; `TimelineView` / `drawingGroup` must not do per-frame I/O.

## Trips list scroll (recording card)

- Trips list hides in-progress recordings with an `endedAt != nil` predicate. Do not add ad-hoc SwiftData schema fields without a versioned migration plan.
- Card frame for stop credits is kept inside `ActiveTripView` (not propagated to `TripListView` on every scroll frame).
- Road + exhaust animation uses `RecordingCarAnimationView`; `TimelineView` only runs while recording, unpaused, and the card is on-screen.

## Active recording card

- GPS and persistence still run at full rate; on-screen stats use `RecordingDisplaySampler` (~4 Hz / 250 ms).
- The recording card no longer shows a live mini-map (only the car animation + stats).
- Stop credits still use `LiveBreadcrumbCanvas` briefly.
- The road animation pauses when another tab is selected or the card scrolls off-screen (`isRecordingCardInViewport`).
- `TimelineView` runs only while the road animation is active (paused / off-screen = static frame).
- **Live follow map** (`LiveFollowMapView` + `LiveFollowMapKitView`): `CADisplayLink` drives `LiveFollowCamera`. The same `lastLocation` is not re-ingested every frame (that reset the dead-reckon clock and snapped at ~1 Hz). Published position eases toward a predicted fix; heading uses a time constant. `LiveFollowSession.camera` is observation-ignored so 60 fps ticks do not rebuild SwiftUI. Camera writes use `map.camera` inside `CATransaction` (actions disabled). Follow tiles stay `.flat` with pitch for 3D feel — realistic elevation remeshes on heading and hitch. Breadcrumb polylines update incrementally via `RouteDisplayPath` (max 1500). `ScreenIdleLock` keeps the display awake only while the cover is open. Start / pause / trip-stop pins render on the live map. While the cover is open, the card’s road `TimelineView` stays paused (`!showLiveFollowMap`).

### Observation isolation

The card sits above a 40-row `List`, so anything that invalidates its body invalidates it during scrolling too. Two rules:

- **Live counters may only be read inside `ActiveTripLiveStats` or `RecordingCardAccessibilityLabel` — never in the card's body.** Reading `displayElapsedTime`, `displaySpeedMps` or `displayDistanceMeters` from an `@Observable` service in the body subscribes the whole card to the 4 Hz sampler. The VoiceOver label used to do exactly this; the text now comes from the pure `RecordingAccessibility.summary` and is applied through a `ViewModifier`, whose own body absorbs the dependency.
- **No `context.fetch` in a view body.** The vehicle picker resolved the active vehicle with `VehicleResolver.resolveActiveVehicle(in:)`, hitting the store on every pass. Views pass their existing `@Query` array to `resolveActiveVehicle(from:)` instead.

### Scroll invalidation

- The recording card's frame is only needed when Stop or live-follow is pressed, so it lives in `RecordingCardAnchorBox`, a reference box outside the dependency graph. It was previously `@State` with a 12 pt threshold, which a fast scroll clears every frame — so the card was rebuilt every frame.
- The filter bar's `.global` frame preference is only installed while `endCredits != nil`. Otherwise the preference chain ran on every scroll frame for an animation that was not playing.
- `TripListView` computes `visibleTrips` and `firstTripID` once per body pass. `completedTrips` used to be re-filtered inside every row, making the list quadratic in trip count.

### Backgrounds

- `AtmosphericBackground` draws its three glows as `RadialGradient`s rather than `Circle().blur(radius:)`. Every frosted row above them was resampling those blur passes.
- The glows are wider than the screen, so they must stay in an `.overlay` rather than being `ZStack` siblings. As siblings they stretched the layout of every container that puts this behind its content (`ContentView.mainTabs`, `glassListChrome`), pushing toolbar buttons off-screen.
- `TripMapSnapshotCache` resolves its cache directory once and does all disk reads, JPEG decodes and writes off the main actor. `cachedImage(for:)` is a memory-only lookup and is safe to call while scrolling.

## Route rendering

Recorded points are stored at full resolution and are **never** reduced on disk. Post-processing used to replace a finished trip's points with a Douglas-Peucker subset (a 1922-point drive came back as 143), which both destroyed user data and made maps and speed charts look broken. `TripPostProcessorTests` guards against that regressing.

All drawing goes through `RouteDisplayPath`, a pure read-path transform:

- **Display budget.** At most `maxDisplayPoints` (1500) points reach MapKit or `Canvas`, so cost is independent of trip length. Decimation uses a 3 m meter-based tolerance and always keeps both ends.
- **Decimation never fabricates a gap.** After Douglas-Peucker, points are re-inserted wherever a surviving chord would exceed `baseChordLimitMeters` (450 m).
- **Adaptive chord limit, measured locally.** Densely recorded stretches keep the 450 m limit, so a tunnel or signal loss still breaks the line instead of inventing a straight path. Stretches whose stored points are already a simplified polyline (median spacing above 60 m — only legacy trips damaged by the old post-processor) get no distance cap, since Douglas-Peucker guarantees those chords are geometrically accurate. Implausible-speed teleports still break either way, via `RecordingMovementPolicy`.

  The density is judged over a sliding window of `densityWindowRadius` (12) spacings on each side, not over the whole route. A merged trip mixes both kinds, and a single route-wide median let the dense leg outvote the sparse one: every one of the legacy leg's chords then read as a gap, and because `split` drops runs shorter than two points, the entire leg disappeared from the map. `testMergedSparseAndDenseLegsAreJudgedSeparately` covers this.
- **One sub-path per piece.** `TripShareCardRenderer` and `TripMapSnapshotCache` used to stroke a single `UIBezierPath` through every point, bridging real gaps with a false straight line. Each drawable piece is now its own sub-path.
- `speedSegmentCache` still caches speed-colored segments per trip, keyed on the recorded point count, and also carries the display point count.

## Speed chart

`SpeedChartSeries` builds the plotted series, following the same pure-builder pattern as `RouteDisplayPath`. The gap threshold that breaks the chart line is `max(90 s, 6 × median sample interval)` rather than a fixed 90 s, which used to split the chart on sparsely sampled legacy trips.

- **Bucket averaging, not striding.** `maxDrivingSamples` (600) bounds the cost of drawing a long trip. Striding to that budget kept whichever readings happened to land on the stride, including lone spikes, and discarded the neighbours that would have balanced them; the line looked far more jagged than the drive was. Buckets average instead, and a 3-sample moving median runs first to drop single-reading spikes.
- **Buckets never span a real gap.** The series is split into runs at recording gaps before the budget is shared out, so a stop cannot be averaged away by the driving either side of it.
- **Standstills draw as zero.** The recorder writes no points while the car sits at a light, and because the x axis is time that read as missing data rather than as "not moving". When the fixes either side of a gap are within `parkedDriftMeters` (60 m), the gap is filled with zero samples spaced at half the break threshold, so the line dips to zero and comes back. Beyond `maximumDrawnStopSeconds` (45 min) it is a merged trip's seam rather than a pause, so the series still does not invent hours of zero samples. The canvas and share card then drop the stroke to the baseline and run along it (`SpeedChartSeries.strokePoints`), so a merge seam or lost-signal gap is a valley at zero rather than a dashed hole.
- **Axis scaled from plotted data only.** `speedChartMaxKmh` no longer blends in `trip.maxSpeedMps`. One phantom stored maximum pinned the axis at 200 km/h and squashed a whole drive into the bottom third of the chart.
- The built series is cached per trip alongside `speedSegmentCache`, since axis scale, samples and median interval each read it.

## Speed accuracy

`Trip.maxSpeedMps` is written only by the recorder and is never rewritten by a migration, so trips recorded before speeds were vetted still carry their stored value on disk. Reads handle it in two ways, split by what the surface can afford:

- **Trip detail** (points already loaded) derives the honest value with `TripSpeedSummary.maxSpeedMps`: the largest speed that three consecutive samples all reach. Bogus peaks are one sample wide, so requiring a peak to last is enough to reject them.
- **Trip rows, statistics and rollups** must never touch `trip.sortedPoints` — that is the scroll jank fixed earlier — so they only vet the stored value with `believableStoredMaxSpeedMps`. A value above `maximumRecordedSpeedMps` (50 m/s) counts as no reading, and every one of those surfaces already handles nil. Showing nothing beats showing a number the car never reached.

At the source, `RecordingMovementPolicy.trustedGPSSpeedMps` gates Core Location's speed on `speedAccuracy`, horizontal accuracy (65 m), fix age (5 s) and the 50 m/s ceiling, with an acceleration check against the last accepted speed. **Only the speed is discarded; the position is always stored** — tightening the position gate would drop points in tunnels and bring back the broken-looking routes. Rejections are logged with which gate fired.

## Trip detail reveal

`TripDetailRevealPolicy` controls the opening route animation. First open always draws (~12 ticks) unless Reduce Motion; same-session reopen stays instant via `TripDetailRevealSession`. Display point count no longer gates animation.

| Condition | Behavior |
|-------------|----------|
| First open, motion OK | ~12 ticks, single solid polyline while drawing; speed colors + white casing when settled |
| Reduce Motion | Instant reveal (full route + casing) |
| Same process, trip already revealed | Instant reveal |

During ticks MapKit sees one growing fallback stroke — not up to 60 speed-colored overlays — so long/twisty display paths stay smooth.

**Layout (no MapKit resize).** The map stays full-screen. The frosted details panel is a fixed-height overlay with its own atmospheric wash — panel height never applies `padding` to the Map. The card is not user-resizable (no grabber drag / detents). Camera fit still uses `MapFitContext` insets so the route sits in the visible gap above the panel; refit runs on open (and in-place expand/collapse), not on overlay scroll. `TripDetailMapLayer` is `Equatable` and excludes panel height so sheet motion does not rebuild overlays.

**In-place map expand (no sheet).** Toolbar fullscreen is not a second MapKit instance or SwiftUI `.sheet`. `isMapExpanded` slides the existing panel off-screen (`offset` + `opacity`; frame height stays put) and refits the shared `mapCameraBox` on the same beat — `TrailhoundMotion.mapExpand` (1.40s) / `mapCollapse` (1.10s). Do not reintroduce a deferred `scheduleMapRefit` (280ms) on this path; panel and camera must share one curve. Apply the fitted `MKCoordinateRegion` via `MapCameraPosition.region` — do not convert through `MapCamera` + `cameraDistance` (that altitude fudge zooms in and clips the route). Expanded edge padding must clear nav + style picker on top and tab-bar + speed chips on the bottom. Read tab-bar height from the key window (`safeArea.bottom + 49`); `GeometryReader` under `.ignoresSafeArea(.bottom)` reports 0 and buries the chips. When expanded, chrome bottom inset is that tab-bar height so the legend sits on the bar, not under it. Glass stays `frozen` for the transition duration. Style picker fades in after ~750ms expand only. Reduce Motion snaps both directions. Elevation stays `.flat`; expand must not toggle route/pin/stop reveal inputs.

**First paint.** Opening never faults `trip.sortedPoints` on the first frame. The speed chart builds from `displayPieces` (≤1500). Trim steppers wait for a deferred `recordedPointCount`. Heavy form content mounts after `panelRisen`. Original GPS rows are never deleted by these paths — `RouteDisplayPath` / `TripRoutePathCache` remain read-only transforms. List rows do **not** prewarm route paths (that faulted GPS on every scroll recycle). Warmth comes from stop/merge `prewarm` plus detail’s async `path(...)` (memory → disk → build).

Signature open order (first open, motion OK): muted map veil → `mapClear` → frosted panel `sheetRise` → camera refit into the visible gap → start pin → route ticks (single stroke) → end pin + speed colors + casing. The settle veil is a lightweight SwiftUI overlay (not a MapKit style switch). Elevation stays `.flat` for the whole screen (same hitch reason as live follow). Camera fit uses `MapFitContext.detailOverlay(panelFraction:)` so the route sits in the strip above the overlay panel — full-screen MapKit no longer gets physical bottom padding.

While the in-place expand/collapse runs, panel glass uses a solid fill (`glassChrome(frozen:)`) so Material does not resample the live map every frame.

## Share card

- One `MKMapSnapshotter` + compose per share; preview sheet then system share sheet.
- Path prep (`TripShareRoutePrep`: privacy clip → decimate → chart series → `SpeedColoredSegmentBuilder`) runs off the main actor; points are faulted once before the hop. Map strokes and the speed chart share the same clipped samples.
- Preparing overlay is glass chrome (same pattern as Settings export) — do not drive multi-second prep through `ToastPresenter`.
- Brand logo is drawn into the raster at compose time; no ActivityKit / widget images.

## Recording cold-open

- `TripListView` arms `coldOpenArmed` for manual, Shortcuts, and widget deep-link starts; `ActiveTripView.playEntranceReveal` must stay wired to that flag.
- Road `TimelineView` remains gated (recording, unpaused, on-screen, LPM 12 FPS). Do not reintroduce a live mini-map on the card.

## Shortcuts guide wizard

- At most one live `OnboardingHeroScene` `TimelineView` (prereq / handoff pages only); pause when backgrounded or Reduce Motion.
- Step-complete uses `SoftPulseRing` + haptics — not a continuous road loop while paging.

## Derived trip fields (schema V10)

Stats, the trip list and search all used to answer questions by faulting in a trip's whole `points`
relationship — reading a start coordinate or a night-driving share pulled every GPS row for that
trip into memory. `Trip` now stores those answers directly:

| Field | Replaces |
|-------|----------|
| `nightDistanceMeters` / `trackedDistanceMeters` | walking every GPS segment in `nightDrivingRatio` |
| `startLatitude` / `startLongitude` / `endLatitude` / `endLongitude` | `sortedPoints.first` / `.last` |
| `searchIndex` | the per-keystroke scan over route summary, label, note, addresses and place names |

All of them are optional and additive, so existing rows open as `nil` and nothing a user recorded is
touched. Rules for working with them:

- **`TripDerivedMetrics` is the only place that computes them.** It is called wherever a trip's
  points or dates change: `TripRecordingService.stopRecording`, `TripRecoveryService.finalizeOrphan`,
  `TripMergeService.merge`, `TripPostProcessor.process` (after geocoding, so addresses reach the
  search index) and `TripDetailView.saveEdits` (which also covers the GPS trim).
- **Every read path falls back.** `Trip.startCoordinate`, `TripListViewModel.matchesSearch` and
  `StatsViewModel.nightDrivingRatio` use the stored value when present and the old point-walking
  behaviour when it is `nil`, so a partly backfilled library is never wrong, only slower.
- **`TripDerivedBackfillService` fills in old trips** at launch. The work happens on the
  `TripDerivedBackfiller` `@ModelActor`, off the main thread, 25 trips at a time, saving each batch
  and calling `invalidatePointCaches()` between them. It is idempotent and resumes from where an
  interrupted run stopped.

`nightDrivingRatio`'s fallback loop is also cheaper than it was: `StatsViewModel.approximateDistanceMeters`
uses an equirectangular approximation instead of allocating two `CLLocation`s per segment, and the
UTC offset is resolved once per trip instead of calling `Calendar.component(.hour:)` per point.

## Trip list

- Filter uses `debouncedSearchText` (250 ms) so typing does not re-filter the full list every keypress.
- **The list has no `@Query` for trips.** It pages through the store via `TripListPage`, fetching
  `pageLimit + 1` rows so it can tell whether another page exists without a second count query.
  `ModelContext.didSave` stands in for the change tracking `@Query` would have provided, via the
  `onStoreSave` modifier — see "Reacting to saves" below.
- What the store can answer exactly — completed-only, category, a date lower bound,
  favorite-place name (start or end), and `searchIndex` matching — lives in the `#Predicate`.
  Place + full search + category in one macro overloads the type checker, so place-active
  predicates keep place/vehicle/category/date in SQLite and re-apply search in memory over the
  page. What the store still cannot answer exactly — date-section boundaries that move with the
  wall clock, plus the legacy search scan for trips still awaiting a `searchIndex` — is also
  refined in memory.
- The list previously filtered entirely in memory to avoid `#Predicate` on `@Model` key paths, which
  warned under `SWIFT_STRICT_CONCURRENCY = complete` ("KeyPath<Trip, …> does not conform to
  Sendable"). That is a Swift 5 language-mode gap rather than a SwiftData limitation: key path
  literals only infer `Sendable` under SE-0418, which Swift 6 enables by default. The project opts
  in with `SWIFT_UPCOMING_FEATURE_INFER_SENDABLE_FROM_CAPTURES`, so `#Predicate` and
  `SortDescriptor` over `@Model` key paths are warning-free. **Keep that setting on** — dropping it
  brings back a warning at every predicate in `TripListPage`, `StatsView`, `TripRollupService` and
  `TripDerivedBackfillService`.
- **The load-more trigger is a footer section, not the last row.** A page whose rows are all
  removed by the in-memory pass would otherwise dead-end with nothing left to trigger the next one.
- Aggregates that need more than the loaded pages have their own queries: `fetchCount` for
  "are there any trips", a week-scoped fetch for the summary line, a `fetchLimit = 1` descriptor for
  the newest trip behind the post-stop morph, and a fetch by ID for merge (a selection made before
  scrolling may include trips no longer resident).
- `TripDateGrouping.groupedSections` runs once per load into `@State`, not once per body pass.

## Inactive tabs

- Stats, Pairing, Settings, and Dev Log views mount only while their tab is selected (Trips stays mounted for the recording card).

## Stats tab

- Chart aggregations build into a `StatsDisplaySnapshot` on filter/store changes, not on every scroll frame.
- Each chart is its own `List` row; `StatsDeferredChart` / `StatsDeferredContent` mount Swift Charts after the row appears (placeholder keeps layout stable).
- **Nothing in the body computes an aggregation.** Goal distance lives on the snapshot as
  `goalDistanceMeters` and is always the **goal calendar month's** total (not the week/custom
  window). Week → current month; month filter → selected month; custom → month of the range end.
- The goal ring is monthly only. `AppSettings` stores a live `monthlyDistanceGoalMeters` plus a
  `"yyyy-MM"` dictionary of frozen targets. The stepper edits only the in-progress month; past
  months show the locked value (or the live fallback when no history exists) and hide the stepper.
- `StatsViewModel.stats(includeNightRatio:)` lets callers that only need distance and duration skip
  the expensive part. The trip list's week summary and the widget sync in `TripStore` both pass `false`.
- **The tab has no `@Query` for trips either.** Fetching happens inside `StatsSnapshotLoader`, which
  loads `selected ∪ previous ∪ goalMonth` so a week view still has the full current month for the ring
  without pulling the whole library.
- **Aggregation runs on a `@ModelActor`.** `StatsSnapshotLoader` owns its own `ModelContext`, maps
  trips/rollups to `TripStatsRow`, and builds the snapshot there. `StatsView` only `await`s the
  result onto the main actor. A plain `Task { }` inside the view is *not* enough — SwiftUI views are
  `@MainActor`, so that task would inherit the main actor and still block the UI.
- Filter changes are debounced (~120 ms) after the first load, and the loader keeps an 8-entry
  request cache cleared whenever `storeVersion` bumps, so week ↔ month ↔ back is instant.
- Category, vehicle, and favorite-place filters scope **summary and chart series** together.
  The monthly goal ring stays unfiltered. Place filter forces the trip fetch path (daily rollups
  have no place dimension); without a place filter the 92-day rollup path is unchanged.
- **Pager charts mount lazily per slide.** `StatsDeferredChart` / `StatsDeferredContent` take an
  `isPageActive` flag tied to the pager selection, so a `TabView` with five daily slides does not
  build all five Swift Charts when the section first appears — only the visible page (after the row
  scrolls into view). Vehicle cost charts use the same pattern via `VehicleCostSnapshotLoader`.

## Reacting to saves

Dropping `@Query` from the trip list and the stats tab also dropped the change tracking that came
with it, so both reload on `ModelContext.didSave` through the `onStoreSave` modifier. Two things
about that notification make a plain `onReceive` wrong:

- **It is delivered on whichever thread performed the save.** `TripDerivedBackfiller` and
  `TripRollupRebuilder` save from their own `@ModelActor`, so a plain handler mutates SwiftUI state
  off the main thread and trips "Publishing changes from background threads is not allowed".
  `onStoreSave` hops to the main thread when it did not start there.
- **It cannot simply be `receive(on: .main)` either.** That defers *every* reload by a runloop turn,
  including the main-thread save that a deletion performs. For that one turn the view still holds
  the deleted model in its own fetched array, and rendering a row from it is a crash rather than a
  glitch. So saves already on the main thread run the handler synchronously.

## Daily rollups (schema V11+)

`TripDailyRollup` pre-aggregates one row per (day, category, vehicle). A period's cost then scales
with the number of days it covers rather than the number of trips in it, which is what makes a
six-figure library viable.

- It is **derived data**. `Trip` remains the only source of truth, and the table can be regenerated
  from it at any time.
- `TripRollupService` maintains it as deltas at the same write sites that compute derived metrics,
  plus the deletion paths (`TripListView.deleteTrip`, `TripCleanupService`, and the legs consumed by
  a merge). An edit uses `snapshot(of:)` before the change and `update(_:from:)` after, so a trip
  that moved to another day, category or vehicle leaves its old bucket cleanly. A bucket that drops
  to zero trips is deleted rather than left as a zeroed row with a stale `maxSpeedMps`.
- Schema **V15** adds cruise / stop totals on each rollup (`stopDurationSeconds`,
  `cruiseWeightSeconds`, `cruiseSpeedProduct`) fed from matching derived fields on `Trip`. Cruise
  is moving average (metres while moving / moving time); period cruise is the duration-weighted
  mean of each trip's cruise.
  `rebuildVersion` 3 regenerates existing installs after the upgrade; later bumps refresh
  cruise / stop after formula fixes (v7: implied-speed stops; v8: most-common speed on
  rollups, schema V17). `TripDerivedBackfillService.speedProfileVersion` is bumped with the
  same formula so already-filled trips are rewritten.
- `rebuildIfNeeded` builds the table on the first launch that has it (after the derived backfill, on
  which it depends). Settings → Maintenance → *Rebuild statistics cache* runs `rebuildAll` on demand
  if the deltas ever drift. Both go through the `TripRollupRebuilder` `@ModelActor`, since a rebuild
  has to visit every trip and must not do that on the main thread.
- Reads go through the **same** aggregation as trips: `TripStatsRow.init(rollup:)` turns a bucket
  into one synthetic row carrying `tripCount`, which `StatsViewModel.stats` sums instead of counting
  rows. `StatsSnapshotLoader` switches to rollups only when the required window exceeds 92 days, since a week
  or a month holds few enough trips to read directly. The fetch window is
  `selected ∪ previous ∪ goalMonth`; a single calendar month still stays under the threshold.

## Memory

`Trip.sortedPointsCache` is a `@Transient` array of materialised `TripPoint`s, so anything that
touches `sortedPoints` keeps those rows alive until it is cleared. It is now released at the three
places that used to leak it across a browsing session:

- `TripDetailView.onDisappear` — the detail map is the only screen that needs full resolution.
- `TripMapSnapshotCache` — once the decimated coordinates are extracted, the renderer needs nothing
  else, so scrolling the list no longer accumulates every row's GPS history.
- `TripDerivedBackfillService` — between batches, so a backfill over a large library stays flat.

## Signposts

`PerformanceSignposts` wraps the two paths that historically blocked the main thread. Profile with
Instruments → os_signpost, subsystem `com.trailhound.app`, category `Performance`:

- `StatsSnapshotBuild` — one interval per snapshot rebuild.
- `NightDistanceWalk` — appears only for trips that have not been backfilled yet. Seeing these
  steadily in a warmed-up app means the backfill is not completing.

## Profiling checklist

1. Instruments → Time Profiler + Core Animation on device.
2. Pairing → edit vehicle name with keyboard — should feel smooth vs list screens.
3. Start recording, scroll trip list, switch tabs — CPU should drop on non-Trips tabs.
4. Open a long trip detail — first frame must not hitch on GPS fault; map stays full-screen while the panel rises. Short trips may run map-clear + panel rise + route ticks; medium/long trips settle instantly. The details card stays at a fixed height (scroll inside; no grabber resize). Toolbar fullscreen must expand in place (panel recedes + camera opens together) — no second map sheet, no black flash.
5. Stats tab with many trips — scroll through charts; rows below the fold should appear after placeholders, without blocking the summary header.
6. Record a long drive (thousands of points), then open its detail, list thumbnail, and share card — the route must draw as one continuous line except at genuine GPS gaps.
7. With 30+ trips, start recording and scroll the trip list past the card and back. Temporarily add `Self._printChanges()` to `recordingCard`: expect zero lines while idle and zero while scrolling. In Instruments, neither `context.fetch` nor `Data(contentsOf:)` should appear on the main thread.
8. Seed a few thousand trips, then switch to Stats. In the os_signpost instrument, `StatsSnapshotBuild` should stay well under a frame and `NightDistanceWalk` should stop appearing once the backfill finishes. Scroll the trip list to the bottom repeatedly: each page should load without a visible stall, and memory should stay flat rather than climbing with every screen of thumbnails.
