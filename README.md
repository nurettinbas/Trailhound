# Trailhound

[![iOS Tests](https://github.com/nurettinbas/Trailhound/actions/workflows/ios-tests.yml/badge.svg)](https://github.com/nurettinbas/Trailhound/actions/workflows/ios-tests.yml)

**Privacy-first trip recorder for iOS** — track drives with GPS, estimate fuel cost, and keep every mile on your device. No account, no cloud, no third-party SDKs.

Trailhound is a native SwiftUI app built with SwiftData. It records routes locally, works offline, and can start/stop automatically via **Shortcuts Personal Automations** (Bluetooth, CarPlay, or Wi‑Fi) — or manually from the app, widget, Live Activity, and Siri.

---

## Features

### Recording
- Manual start/stop, pause/resume
- **Shortcuts auto-start / auto-stop**: Create a named Shortcut per vehicle (*Start trip* + **Vehicle**), then a Personal Automation that **Run Shortcut**s it on Bluetooth / CarPlay / Wi‑Fi connect (automations often hide the Vehicle picker). Setup guide lives under the **Pairing** tab
- Vehicle profiles with fuel/EV cost per trip
- **Avg fuel**: catalog cost from `distance × consumption × price`, shown as currency · litres (or kWh) like Estimated fuel. Trip detail **Avg fuel calculate** (with ?) edits consumption and unit price; the live line is **Avg fuel estimate**. Defaults from the vehicle and Settings
- **Estimated fuel**: trip-specific cost from this drive’s speeds, stops, and acceleration (VSP + Willans), including idle time; shown next to Avg on trip detail and Stats, with a short help tip — not a pump reading
- **Vehicle avatar photos**: choose Library or Camera, then an in-app ~70% gallery/camera overlay and frame the crop before save (shown in recording / Live Activity)
- Siri Shortcuts: *Start trip*, *Pause trip*, *Resume trip*, *End trip*
- Widget + Live Activity controls
- **CarPlay Live Activity** (iOS 18+): while recording, the dashboard tile shows the vehicle icon plus duration, distance, and speed (same type size, shrink together when values get long; non-interactive; Lock Screen / Dynamic Island controls unchanged)
- Optional confirmation before widget/shortcut/deep-link recording start
- **Live follow map** (optional): Maps-style 3D/2D follow with the vehicle mark locked to screen center while following — the camera **and the blue trail** glide between GPS fixes (no 1 Hz hitch or chunky path updates) and **pull back as you speed up**; opening the map at speed keeps the curved vehicle→puck flight on the moving mark; a single blue traveled path fills in behind you at constant thickness in 2D and 3D; pan (including while paused) to look back at the start; **Show entire route** fits start + trail north-up while the vehicle photo and heading chevron still face the direction of travel; screen stays awake while open; start/pause pins on the map; pause/resume/stop stay available; road animation pauses while the map is open

### Privacy & data
- All trips stored locally with **SwiftData** (file protection on store)
- Offline-first recording; geocoding retries when online
- Home/work saved places with privacy radius (route clipping)
- Optional Face ID app lock (device passcode required)
- Optional blur of coordinates on export
- Configurable auto-delete (Never, or 30/90/365 days)
- Export: JSON, CSV, GPX, KML

### Maps & analytics
- MapKit route polylines with speed-colored segments
- Trip detail: full-screen map with a fixed details card (scroll to edit; toolbar expands the map in place)
- Trip summary cards pack left-to-right in a 3-column grid (no leftover empty slots mid-grid) and include **travel time** (moving minutes, excluding pauses) next to **duration**, **cruise speed** (average while moving — excludes stops), **most common** (mode of driving pace, not queue crawl) / **median** speeds, and **stop time** alongside average/max
- Trip stops (dwell detection), route thumbnails with vehicle photo/icon badge
- Swift Charts stats, trends, monthly distance goals — including daily **cruise speed**, **most common** speed, **stop time**, **night driving** share, and dual **avg / estimated** fuel charts
- **Stats comparison** (same tab, no extra load on open): one glass-card language — 2-up goal + hero numbers, nested summary tiles with previous-period lines, polarity-aware arrows, a **Logged vehicle expenses** card (sums Pairing expenses, not trip GPS fuel; `?` explains the source) with cost/km, swipeable chart pagers, and a deferred year-in-review card. An in-progress month compares against the same days last month. Place, journal, or category chips hide expense MoM and vehicle $/km (those filters have no expense dimension); the goal ring and year awards stay unfiltered
- Category filters, trip merge (select completed trips on the list; there is no split)
- **Share card** from trip detail — privacy-clipped route snapshot plus caption (same clip as maps)
- **Favorite place filter** on Trips and Stats (start or end matches a saved place); charts and summary follow the same filters independently per tab

### Vehicle care & costs
- **Reminders** — inspection, insurance, comprehensive cover, service due dates with staged local push + inbox (service: 30 days → 1 week → due day → one overdue; insurance: 1 week → due day → one overdue); mark done from the row (Done) to log cost and roll the next due date
- **Expenses** — log fuel, traffic insurance, casco, service, inspection, repair, accessory, and other costs separately from reminders; split a purchase into **monthly installments** (up to 24) so each month’s share appears on Stats in that month
- One vehicle detail screen under the **Pairing** tab: profile → reminders → expenses; cost charts live on **Stats**
- Overdue care also shown as an in-app banner; push fires once when overdue (no daily spam)

### Organization
- Personal / business categories (+ custom)
- **Smart category** (optional): suggests Personal or Business from frequent routes, Home/Work places, and weekday work hours; swipe the list row to accept — nothing is applied automatically
- **Travel journal** — Trips tab segment **Trips | Travels**; group completed drives under a Seyahat, all member routes on one map, optional suggestion chip, **Add to travel** on trip detail, Stats **Travel** filter. Deleting a journal unassigns trips; it does not delete them
- Vehicle management (petrol, diesel, hybrid, EV)
- In-app notifications inbox
- Turkish & English UI (Localizable.xcstrings)

---

## Platform support

| Platform | Minimum version | Status |
|----------|-----------------|--------|
| **iPhone (iOS)** | **17.0** | ✅ Primary target |
| **iPadOS** | 17.0 | ⚠️ Runs as iPhone app (not optimized for iPad) |
| **Widget (Home / Lock)** | iOS 17.0+ | ✅ Home Screen & Lock Screen widgets |
| **Live Activity + CarPlay tile** | iOS 18.0+ | ✅ Lock Screen, Dynamic Island, CarPlay Dashboard (icon + duration, distance, speed) |
| **Siri / Shortcuts** | iOS 17.0+ | ✅ App Intents + Personal Automations |
| **macOS / visionOS / tvOS** | — | ❌ Not supported |

### Why iOS 17?

Trailhound uses **SwiftData**, **App Intents**, **Live Activities**, and modern **WidgetKit** APIs that require iOS 17. The project does not build for iOS 16 or earlier. The **CarPlay Dashboard Live Activity** layout (vehicle icon plus duration, distance, and speed) needs **iOS 18** (`activityFamily.small`); on iOS 17 the Home Screen widgets still work, but the Live Activity presentation targets iOS 18+.

### Device & permissions

| Requirement | Used for |
|-------------|----------|
| GPS (Always / When In Use) | Route recording and background trips |
| Notifications | Trip started/ended alerts; vehicle care due reminders |
| Face ID (optional) | App lock |
| Shortcuts (system) | Auto-start/stop Personal Automations |

**Physical iPhone recommended** for real-world testing (GPS, background recording, Shortcuts automations). Simulator is fine for UI and basic location simulation.

---

## Requirements (development)

| | |
|---|---|
| **Xcode** | 15.0+ (iOS 17 SDK); CI uses **Xcode 26.5** on `macos-26` |
| **Swift** | 5.0 (strict concurrency enabled) |
| **iOS deployment target** | 17.0 |
| **Dependencies** | None (Apple frameworks only) |
| **Bundle IDs** | `com.trailhound.app` · `com.trailhound.app.widget` |
| **App Group** | `group.com.trailhound.app` |

---

## Getting started

```bash
git clone https://github.com/nurettinbas/Trailhound.git
cd Trailhound
open Trailhound.xcodeproj
```

1. Select an **iPhone** simulator or device
2. Update **Signing & Capabilities** with your Team (bundle ID: `com.trailhound.app`)
3. Ensure App Group `group.com.trailhound.app` is enabled for app + widget targets
4. Press **⌘R** to run

### Simulator quick test

1. Tap **Start** in the app
2. **Features → Location → Freeway Drive**
3. Stop after 1–2 minutes

### Automated tests

Run the full unit + UI smoke suite locally:

```bash
chmod +x scripts/run_tests.sh scripts/ci_pick_simulator.sh
DESTINATION="$(./scripts/ci_pick_simulator.sh)" ./scripts/run_tests.sh
```

Unit tests only (faster):

```bash
INCLUDE_UI_TESTS=0 ./scripts/run_tests.sh
```

UI tests only:

```bash
ONLY_UI_TESTS=1 ./scripts/run_tests.sh
```

Override the simulator destination if needed:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.5' ./scripts/run_tests.sh
```

CI runs the same script on every push and pull request to `main` via GitHub Actions (`.github/workflows/ios-tests.yml`).

### Siri Shortcuts & auto-recording

Requires **iOS 17+** and **Siri / Shortcuts** available. After first launch:

1. Open **Pairing** in Trailhound → follow **Auto-start with Shortcuts**
2. Or open **Shortcuts** → search **Trailhound** and add: **Start trip**, **Pause trip**, **Resume trip**, **End trip**
3. For hands-free start/stop: create a named Shortcut with **Start trip** + **Vehicle**, then a Personal Automation that uses **Run Shortcut** on Bluetooth / CarPlay / Wi‑Fi connect (and **End trip** on disconnect). Automations often hide the Vehicle picker if you add Start trip directly.

**Siri examples:** *“Start trip in Trailhound”*, *“Pause trip in Trailhound”* (Turkish phrases are also registered for TR Siri language)

> Siri language and system language can differ. Shortcuts list follows system language; voice phrases follow Siri language.
>
> In-app Bluetooth audio-route auto-start was removed. Auto-record now relies on Shortcuts Personal Automations (more reliable across iOS versions and CarPlay).

---

## Project structure

```
Trailhound/
├── App/              # App entry, runtime bootstrap, scene lifecycle
├── Models/           # SwiftData models (Trip, VehicleProfile, …)
├── Services/         # Location, recording, geocoding, export, pairing
├── Views/            # SwiftUI screens (incl. Pairing Shortcuts guide)
├── Intents/          # App Intents & Siri Shortcuts
├── Utilities/        # L10n, migrations
TrailhoundShared/        # App Group bridge (widget, Live Activity, deep links)
TrailhoundWidget/        # WidgetKit + Live Activity extension
TrailhoundTests/         # Unit + integration tests
TrailhoundUITests/       # UI smoke tests (XCUITest)
scripts/              # CI simulator pick + xcodebuild test runner
docs/                 # Battery, TestFlight, vehicle care notes
```

**Stack:** SwiftUI · SwiftData · MapKit · CoreLocation · App Intents · WidgetKit · ActivityKit

---

## Documentation

- [Battery optimization](docs/BATTERY_OPTIMIZATION.md)
- [UI performance notes](docs/PERFORMANCE.md) — live follow map camera, route drawing, trip-list scroll, Stats cards
- [Stats tab](docs/STATS_TAB.md) — card spans, nested tiles, deferred charts
- [Stats (wiki)](https://github.com/nurettinbas/Trailhound/wiki/Stats) — product layout and performance contract
- [Live follow map](https://github.com/nurettinbas/Trailhound/wiki/Live-Follow) — product flow and MapKit drawing (wiki)
- [TestFlight release checklist](docs/TESTFLIGHT_RELEASE.md)
- [Vehicle care & expenses](docs/VEHICLE_CARE_PLAN.md) — reminders vs costs, monthly installments, UI layout, notification rules
- [Travel journal](docs/TRAVEL_JOURNAL_PLAN.md) — Seyahat grouping, suggestion rules, schema V19

---

## Contributing

Issues and pull requests are welcome. Please open an issue before large changes.

---

## License

[MIT](LICENSE) — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with Swift · No analytics · No tracking · Your roads, your data.</sub>
</p>
