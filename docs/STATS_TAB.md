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

Previous-period values from comparison live on the hero and on tiles that have a `StatsPeriodCompareRow` (trips, distance, duration, expenses, estimated fuel). The old spreadsheet strip is not a separate card.

Logged vehicle expenses (Capsule bars, not Swift Charts) is its **own** full-width card, with a `?` that explains the sum. Vehicle donut charts stay in the following pager card. Both still use the same cost snapshot — no extra fetch.

## What stays deferred

- `StatsSnapshotLoader` / `VehicleCostSnapshotLoader` on `@ModelActor`. Fetch window remains `selected ∪ previous ∪ goalMonth`.
- `StatsDeferredChart` / `StatsDeferredContent` + `isPageActive` — only the visible pager slide mounts Swift Charts.
- `StatsYearAwardsLoader` must **not** start in Stats `onAppear`. Wait for the first snapshot, then idle ~300 ms unless the awards **row** has appeared. Year path = rollups + expenses only.

See [PERFORMANCE.md](PERFORMANCE.md) Stats tab section.
