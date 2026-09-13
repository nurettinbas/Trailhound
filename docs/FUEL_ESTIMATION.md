# Fuel estimation

Trailhound shows two fuel figures. Neither is a pump reading.

| Label | Stored field | What it is |
|---|---|---|
| **Avg fuel** | `Trip.estimatedFuelCost` | Catalog cost: `distance × C₀ / 100 × unit price` |
| **Est. fuel** | `Trip.dynamicFuelCost` | The same `C₀`, adjusted by this trip’s GPS speed / load / short traffic idle |

`C₀` is the vehicle (or trip-snapshot) consumption in L/100 km or kWh/100 km. Unit price is per litre or per kWh.

## What GPS can and cannot do

The app does **not** have vehicle mass, drag area, engine displacement, road grade, cabin HVAC, or whether the engine was running. Published microscopic models such as VT-CPFM need separate city **and** highway ratings plus road-load data; EPA MOVES needs source parameters and operating-mode rates.

So estimated fuel does **not** claim vehicle-specific scientific accuracy. It uses:

1. **Absolute baseline** — `km × C₀ / 100`. This is the only vehicle-specific magnitude.
2. **Relative GPS factor** — a dimensionless correction from the cleaned speed trace, using fleet-average curves. Confidence shrinks toward `1.0` (pure catalog) when the trace is sparse, teleports, or disagrees with stored distance. An unusable trace **is** the catalog baseline, not zero.

## Motion cleanup

Shared moving / merge-gap thresholds live in `TripMotionThresholds` (also used by `TripSpeedProfile`):

- Below 5 km/h is a stop for classification.
- Gaps longer than 45 minutes are merge seams: no fuel, no stop time.
- Dense GPS-confirmed stops are scored as **consecutive runs**. The first ten minutes use the conservative combustion-idle assumption in full; longer runs continue at 35% because they may be a queue but engine-on evidence weakens.
- Sparse low-speed intervals are not discarded at a fixed cutoff. Their idle support falls smoothly with duration and rises when valid movement bounds both sides: a five-to-six-minute light/queue still contributes, while a 20-minute two-point hole contributes very little.
- A map **Stop** pin is **not** treated as engine-off. Auto-detected parking is written after two minutes below 2 km/h, and the recorder drops stationary GPS, so that pin is the same hole as a traffic queue. Idle uses GPS evidence, not the pin.
- Acceleration uses a 3-sample median then Δv/Δt, only for 0.8–15 s intervals, clamped at ±3.5 m/s². Sparse samples cruise at `a = 0`.

Stop **duration** on trip detail can still exceed the idle-weighted duration used for fuel. Estimated fuel counts observed traffic conservatively, but discounts weakly supported parking/GPS gaps. The Est. fuel help tip says so.

## Relative curves (facts vs assumptions)

**Facts used as shape, not as this car’s litres:**

- Oak Ridge / DOE 74-vehicle study: fuel economy typically falls above ~50 mph, with average drops of 12.4 %, 14 %, and 15.4 % on the 50→60→70→80 mph steps ([DOE Fact 982](https://www.energy.gov/cmei/vehicles/fact-982-june-19-2017-slow-down-save-fuel-fuel-economy-decreases-about-14-when)).
- Aerodynamic force scales about with `v²`, power with `v³` ([TNO road load](https://www.tno.nl/media/1971/road_load_determination_passenger_cars_tno_r10237.pdf)).
- Argonne Autonomie: petrol, diesel, and hybrid speed curves differ ([AFDC 10312](https://afdc.energy.gov/data/10312)).
- EPA MOVES uses VSP to **classify** operating modes, not as a Trailhound litre integrator ([MOVES3 LD report](https://www.epa.gov/sites/default/files/2020-11/documents/420r20019.pdf)).
- VT-CPFM calibration needs city+highway ratings ([Park et al. 2013](https://doi.org/10.1260/2046-0430.2.4.317)) — Trailhound does not have those, so it does not run VT-CPFM.

**Assumptions (documented, not measured for this vehicle):**

- A single combined `C₀` is treated as an EPA-like 55 % urban / 45 % highway mix so the GPS factor has a reference of `1.0`.
- Petrol/diesel idle uses a conservative ~0.6 L/h at the 7.5 L/100 reference, scaled with `C₀`, only while GPS supports a short in-trip stop.
- Hybrids get almost no idle (engine-off is unknown) and a bounded regen credit.
- EVs get **no** combustion idle and no invented HVAC; speed enters through rolling + aero; regen cannot exceed traction energy already counted.
- 140 km/h is **outside** the ORNL 80 mph data; the model only keeps the directional `v²` rise there.

The trip factor is clamped to about 0.45–2.2× so a bad trace cannot report multiples of average consumption.

## Where it is written and read

Written (never touches `estimatedFuelCost` or GPS points):

- trip end, edit save, merge, orphan finalize → `TripDerivedMetrics.recomputeFuel`
- launch backfill → `TripDerivedBackfillService` (`trailhound.derived.dynamicFuelVersion`, currently **5**)
- opening a completed trip also rewrites that trip’s stored Est. fuel so the detail screen is not waiting on launch backfill

Read:

- Trip detail Est. fuel tile
- Stats totals, trends, daily Avg/Est. bars
- `TripDailyRollup.dynamicFuelCost` (rebuild version **13** after this model)
- CSV/JSON export `dynamicFuelCost`

**Not** used by month cost forecast, year recap, travel-journal totals, or widgets — those stay on avg fuel.

If a fuel-formula refresh is interrupted, the rollup version is **not** written, so the next launch finishes fuel then rebuilds Stats totals.

Deleted or missing vehicles: use the trip’s consumption/price snapshot when present. Otherwise fall back to the vehicle record if it still exists, then Settings / 7.5 L/100 km petrol. There is no stored fuel-type field on `Trip`, so an EV whose vehicle was deleted and that has no snapshot uses the petrol curves with the global defaults.

## Schema / user data

No new `@Model` properties. Existing SwiftData stores keep trips, points, and avg-fuel snapshots. Only recomputable `dynamicFuelCost` (and the daily rollup copy) change.
