# Stats tab

Product layout and the performance contract for Trailhound’s Stats tab. Colors stay on `TrailhoundBrandColors` / `StatsChartTheme`. No extra fetch on tab open.

## Card language

One chrome (`StatsCard.swift`):

| Span | Use |
|---|---|
| **Half** | Goal ring + stepper, beside hero numbers (distance, duration, expenses — or trips when expense MoM is hidden) |
| **Full** | Filter, nested summary tiles, each chart pager, year awards |
| **Nested tile** | Remaining summary metrics inside the summary card; frost fill, radius 16 — not a second glass card |

List rows use a **clear** background. The card is `glassCard` only (one `Material`). Mixing `glassListRow` / `GlassRowPosition.first` with a floating chart card is forbidden.

## Filter card

The filter row is still one full-width `glassCard` — no extra fetch, no `GeometryReader`. Layout:

- **Period chips** keep the same compact expanding capsules (Last 7 days / Month / Custom). Light theme paints unselected chips as frosted white and the selected chip as a white pill with deep-blue text; dark stays brand-blue. Month stepper and custom start/end dates stay on the same card.
- **Category, vehicle, place, travel** are equal selection fields: title, one-line truncated value, chevron. Long names do not wrap onto neighbouring fields. Vehicle keeps its avatar. Active fields use a brand stroke in dark and a white stroke in light.
- **Two columns** at standard Dynamic Type; **one column** at accessibility sizes. Each field’s tap target is at least 44 pt.
- **Clear All** appears only when something is not the default. It clears category / vehicle / place / travel, sets the period back to Last 7 days, and restores the default month and custom dates. Reduce Motion skips the reveal animation.

VoiceOver reads each field’s title and current value. Identifiers: `stats.filters.card`, `stats.filters.clear`, `stats.filters.period.{week|month|custom}`, `stats.filters.{category|vehicle|place|journal}`.

## Summary skeleton

Filter changes can move tiles between the hero and the summary grid (trips vs expenses). Until `StatsSnapshotLoader` returns, the summary card shows packed nested-tile skeletons (`StatsSummaryTileSkeleton`) at the destination count — no empty grid holes, no extra fetch. Reduce Motion keeps the bars static. VoiceOver reads **Loading summary**.

Previous-period values from comparison live on the hero and on tiles that have a `StatsPeriodCompareRow` (trips, distance, duration, expenses, estimated fuel). The old spreadsheet strip is not a separate card.

Logged vehicle expenses (Capsule bars, not Swift Charts) is its **own** full-width card, with a `?` that explains the sum. Vehicle donut charts stay in the following pager card. Both still use the same cost snapshot — no extra fetch.

## What stays deferred

- `StatsSnapshotLoader` / `VehicleCostSnapshotLoader` on `@ModelActor`. Fetch window remains `selected ∪ previous ∪ goalMonth`.
- `StatsDeferredChart` / `StatsDeferredContent` + `isPageActive` — only the visible pager slide mounts Swift Charts.
- `StatsYearAwardsLoader` must **not** start in Stats `onAppear`. Wait for the first snapshot, then idle ~300 ms unless the awards **row** has appeared. Year path = rollups + expenses only.

See [PERFORMANCE.md](PERFORMANCE.md) Stats tab section.
