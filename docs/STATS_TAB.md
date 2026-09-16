# Stats tab

Product layout and the performance contract for Trailhound’s Stats tab. Chrome follows the selected **shell palette** (`GlassContrast` / `StatsChartTheme`) — not a fixed brand-blue skin. No extra fetch on tab open.

## Card language

One chrome (`StatsCard.swift`):

| Span | Use |
|---|---|
| **Half** | Goal ring + stepper, beside hero numbers (distance, duration, expenses — or trips when expense MoM is hidden) |
| **Full** | Filter, nested summary tiles, each chart pager, logged vehicle expenses |
| **Nested tile** | Remaining summary metrics inside the summary card; palette-tinted frost fill, radius 16 — not a second glass card |
| **Nested panel** | Same frost fill as nested tiles, variable height (`.statsNestedPanel()`) |

List rows use a **clear** background. The card is `glassCard` only (native Light `glassEffect` behind content). Mixing `glassListRow` / `GlassRowPosition.first` with a floating chart card is forbidden. Swift Charts axis ticks and Y-axis units (`km`, hours, currency) use `StatsChartTheme.axisLabelInk` / `.chartStatsYAxisUnit` so they stay white on Light — never the Charts default primary (black).

Year recap, badges, frequent routes, month forecast, and year awards live on the [Recap tab](YEAR_TAB.md).

Deep link `trailhound://stats/goal` opens this tab. Recap / forecast / routes / achievements URLs open Recap.

See [PERFORMANCE.md](PERFORMANCE.md) Stats tab section.

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

Estimated fuel on the summary tile and the daily dual Avg / Est. chart is the GPS-adjusted `dynamicFuelCost` (see [Fuel estimation](FUEL_ESTIMATION.md)). After a formula change, launch backfill rewrites stored trip values first; daily rollups rebuild only when that walk has finished. Avg fuel, month forecast, and year recap stay on catalog `estimatedFuelCost`.

When the filter is a single fuel unit, Stats also shows estimated volume (litres or kWh), distance-weighted L/100 or kWh/100 km, and driving efficiency. Petrol and electric in the same filter are not added together.

Logged vehicle expenses (Capsule bars, not Swift Charts) is its **own** full-width card, with a `?` that explains the sum. Each vehicle uses the donut `sliceColor` (stable per vehicle id) and `StatsShareBar` scaled to the top spend — not identical bucket-green fills. Vehicle donut charts stay in the following pager card. Both still use the same cost snapshot — no extra fetch.

## What stays deferred

- `StatsSnapshotLoader` / `VehicleCostSnapshotLoader` on `@ModelActor`. Fetch window remains `selected ∪ previous ∪ goalMonth`.
- `StatsDeferredChart` / `StatsDeferredContent` + `isPageActive` — only the visible pager slide mounts Swift Charts.

See [PERFORMANCE.md](PERFORMANCE.md) Stats tab section.
