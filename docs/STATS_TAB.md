# Stats tab

Product layout and the performance contract for Trailhound’s Stats tab. Chrome follows the selected **shell palette** (`GlassContrast` / `StatsChartTheme`) — not a fixed brand-blue skin. No extra fetch on tab open.

## Card language

One chrome (`StatsCard.swift`):

| Span | Use |
|---|---|
| **Half** | Goal ring + stepper, beside hero numbers (distance, duration, expenses — or trips when expense MoM is hidden) |
| **Full** | Filter, premium (year recap, badges, frequent routes, month forecast), nested summary tiles, each chart pager, year awards |
| **Nested tile** | Remaining summary metrics inside the summary card; palette-tinted frost fill, radius 16 — not a second glass card |
| **Nested panel** | Same frost fill as nested tiles, variable height (`.statsNestedPanel()`). Forecast expand uses this — never a grouped `List` plate |

List rows use a **clear** background. The card is `glassCard` only (one `Material`). Mixing `glassListRow` / `GlassRowPosition.first` with a floating chart card is forbidden. Swift Charts axis ticks and Y-axis units (`km`, hours, currency) use `StatsChartTheme.axisLabelInk` / `.chartStatsYAxisUnit` so they stay white on Light — never the Charts default primary (black).

## Premium cards

Inserted **after** the by-category chart pager (and before year awards). Same `.statsFullCard()` chrome as the rest of the tab. They do **not** replace year awards.

| Card | Role |
|---|---|
| **Year recap** | Compact poster hub when the year has trips: intro Canvas fills the card edge-to-edge, year chip at the top-left, km/trips at the bottom-left, Play chip at the bottom-right (never truncates; whole card opens the story). Accessibility sizes stack teaser + copy + chip. Idle teaser motion is 8 fps only while the row is on-screen, the scene is active, and Reduce Motion / Low Power / UI tests are off. Full-screen cinematic story: palette Canvas fills the cover with **looping** motion (road dashes, needle sway, window twinkle). Pages **push** like Instagram (tap left ~⅓ of the **full screen including edges** to go back, tap the rest to go forward — no Next). Segment bars are full-width and sit **tucked under the Dynamic Island / status bar** like Instagram (window top + 8 pt; chrome ignores SwiftUI’s top inset so it is not double-spaced); Close and Share sit under them on the trailing edge and stay tappable. Overlay copy settles up. The badges page sits the 3D medals **inside the glowing orbs** (shared layout so Canvas halo and medal share a frame; 3+2 for five, second row centered, no overlap). Story pages add Canvas sparkles (stronger around each orb). Unlocks from that year first, otherwise your current medals. The last page is a year wrap — receding road + brand — not a slogan. Its segment fills like the others, then the story dismisses (tap forward also closes). Share captures the **visible page** (frozen scene + copy, 9:16), not a leftover km poster. Reduce Motion, hold-to-pause, background, and UI tests freeze the story. January uses the previous calendar year; other months are YTD. Corridor counts are year-scoped. Estimated driving fuel and logged expenses are separate lines, never summed. Cover is frozen at open. Autoplay once in December/January. Settings → **Play year recap** opens the same story any time. Unfiltered year, independent of Stats chips. Empty years show a static teaser + copy — no Play, no idle motion. |
| **Badges** | Horizontal strip shows **unlocked medals only** (centered when they fit, scroll if they overflow). Locked tiers stay in the gallery, **unlocked first** then catalog order. The compact card uses a plain `GlassToolbarSymbol` (glyph only). After expand, collapse is `GlassNavCircleIcon` (frozen circle plate). That control grows the card into the gallery. Gallery cells are compact equal-size **glass** cards (primary/secondary glass ink, not faint hierarchical white). Compact 2 columns, Regular 3, accessibility Dynamic Type 1 column. Medals use 3D chrome (`AchievementMedalChrome`); km is silver / gold / **teal platinum** / **lavender diamond** (100 / 1,000 / 10,000 / 100,000 km) and the four km medals stay listed even before earlier km unlocks; other families keep enamel hues. Locked medals keep the full chrome and overlay `AchievementMedalLockOverlay`; progress uses km vs counts. Unlocked first-trip flag waves from the pole (`AchievementFlagWaveEffect`) — not a pulse of the disc. Distance medals run the two path nodes along the S (`AchievementDistancePathGlyph`) with a different choreography per km metal (convoy / rendezvous / patrol / bloom). Night medals bob the moon and stars together and sparkle (`AchievementNightSkyGlyph`). Compact strip and gallery share one 12 fps idle clock so motion still runs in the Stats `List` (TabView clears SwiftUI animation). Share is unlocked-only. Reduce Motion skips the morph and idle glyph motion. Newly unlocked badges play a glass overlay (family medal motion, 3 s each, then the next unseen badge). A Stats refresh appends new unlocks; it does not reset the card on screen. Tap skips to the next. |
| **Frequent routes** | Top corridor + MapKit snapshot thumbnail framed on that corridor (not a regional overview). Same compact glyph / expanded circle as Badges — the card grows into the full-screen arcs/heatmap (40-corridor cap), not a bottom sheet. Expanded camera starts on the featured corridor; tapping another arc zooms to it. Privacy-safe home/work labels. |
| **Month cost forecast** | Projected month-end total. Driving fuel estimate + installments + other expenses; **logged pump fuel is a separate line** and is never double-counted into the hero total. Hub is a Recap-style **poster**: sparkline fills the card edge-to-edge (`statsFullCard(contentInset: 0)`), year-chip title + hero amount overlay, trend/confidence as one caption line (not a yellow pill), palette `StatsSegmentBar` on a frost track. Same compact expand glyph as Badges / Frequent routes (top-trailing). Expand matches Badges: `AtmosphericBackground` + frozen `glassCard`, not a clear sheet over Statistics. The card grows into a taller sparkline poster (`posterExpandedHeight`), composition bar + `StatsSegmentSwatch` legend, and frost breakdown rows (`.statsNestedPanel()`), not a grouped `List`. Collapse is `GlassNavCircleIcon`. Independent of the comparison **Logged vehicle expenses** card. Motion is one-shot (number, bar grow-in, trend settle, entrance glint); no `TimelineView` on the Stats list. Reduce Motion and UI tests freeze it. |

**Year awards** stay last after the premium section (deferred loader). Recap and awards can both be on screen — recap is the story; awards are the medal grid. Locked medals use the same full-color disc + `AchievementMedalLockOverlay` as Badges — not a washed-out fill.

Premium loaders (`MonthCostForecastLoader`, `YearRecapSnapshotLoader`, achievement/route aggregates) run after the first snapshot path, not as an extra fetch on tab open for the comparison snapshot.

Deep links `trailhound://stats/goal|forecast|recap|routes|achievements` open this tab and the matching expand/cover. A badge unlock writes an inbox row and a local banner (skipped if Stats is already selected — the overlay is enough). In January, a local notification plus inbox row opens last year’s recap when that year has trips and `recap.seen.{year}` is unset (1 Jan 09:00, with catch-up if the app opens later in January). Watching the story or December–January autoplay marks it seen so the push does not repeat.

See [PERFORMANCE.md](PERFORMANCE.md) Premium derived caches (schema V21).

## Filter card

The filter row is still one full-width `glassCard` — no extra fetch, no `GeometryReader`. Layout:

- **Period chips** keep the same compact expanding capsules (Last 7 days / Month / Custom). Light selected chips are a mid-family wash with white type; unselected chips are frost plus white. Dark uses the selected palette tint. Month stepper and custom start/end dates stay on the same card.
- **Category, vehicle, place, travel** are equal selection fields: title, one-line truncated value, chevron. Long names do not wrap onto neighbouring fields. Vehicle keeps its avatar. Active fields use a brand stroke in dark and a white stroke in light.
- **Two columns** at standard Dynamic Type; **one column** at accessibility sizes. Each field’s tap target is at least 44 pt.
- **Clear All** appears only when something is not the default. It clears category / vehicle / place / travel, sets the period back to Last 7 days, and restores the default month and custom dates. Reduce Motion skips the reveal animation.

VoiceOver reads each field’s title and current value. Identifiers: `stats.filters.card`, `stats.filters.clear`, `stats.filters.period.{week|month|custom}`, `stats.filters.{category|vehicle|place|journal}`.

## Summary skeleton

Filter changes can move tiles between the hero and the summary grid (trips vs expenses). Until `StatsSnapshotLoader` returns, the summary card shows packed nested-tile skeletons (`StatsSummaryTileSkeleton`) at the destination count — no empty grid holes, no extra fetch. Reduce Motion keeps the bars static. VoiceOver reads **Loading summary**.

Previous-period values from comparison live on the hero and on tiles that have a `StatsPeriodCompareRow` (trips, distance, duration, expenses, estimated fuel). The old spreadsheet strip is not a separate card.

Logged vehicle expenses (Capsule bars, not Swift Charts) is its **own** full-width card, with a `?` that explains the sum. Each vehicle uses the donut `sliceColor` (stable per vehicle id) and `StatsShareBar` scaled to the top spend — not identical bucket-green fills. Vehicle donut charts stay in the following pager card. Both still use the same cost snapshot — no extra fetch.

## What stays deferred

- `StatsSnapshotLoader` / `VehicleCostSnapshotLoader` on `@ModelActor`. Fetch window remains `selected ∪ previous ∪ goalMonth`.
- `StatsDeferredChart` / `StatsDeferredContent` + `isPageActive` — only the visible pager slide mounts Swift Charts.
- `StatsYearAwardsLoader` must **not** start in Stats `onAppear`. Wait for the first snapshot, then idle ~300 ms unless the awards **row** has appeared. Year path = rollups + expenses only.

See [PERFORMANCE.md](PERFORMANCE.md) Stats tab section.
