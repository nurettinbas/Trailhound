# Trailhound

[![iOS Tests](https://github.com/nurettinbas/Trailhound/actions/workflows/ios-tests.yml/badge.svg)](https://github.com/nurettinbas/Trailhound/actions/workflows/ios-tests.yml)

**Privacy-first trip recorder for iOS** — track drives with GPS, estimate fuel cost, and keep every mile on your device. No account, no cloud, no third-party SDKs.

Trailhound is a native SwiftUI app built with SwiftData. It records routes locally, works offline, and can start/stop automatically via **Shortcuts Personal Automations** (Bluetooth, CarPlay, or Wi‑Fi) — or manually from the app, widget, Live Activity, and Siri.

[English](#features) · [Türkçe](#özellikler)

---

## Features

### Recording
- Manual start/stop, pause/resume
- **Shortcuts auto-start / auto-stop**: Personal Automations run Trailhound’s *Start trip* / *End trip* actions when you connect to or leave the car (Bluetooth, CarPlay, or Wi‑Fi). Setup guide lives under the **Pairing** tab
- Vehicle profiles with fuel/EV cost per trip
- **Vehicle avatar photos**: choose Library or Camera, then an in-app ~70% gallery/camera overlay and frame the crop before save (shown in recording / Live Activity)
- Siri Shortcuts: *Start trip*, *Pause trip*, *Resume trip*, *End trip*
- Widget + Live Activity controls
- Optional confirmation before widget/shortcut/deep-link recording start

### Privacy & data
- All trips stored locally with **SwiftData** (file protection on store)
- Offline-first recording; geocoding retries when online
- Home/work saved places with privacy radius (route clipping)
- Optional Face ID app lock (device passcode required)
- Configurable auto-delete (30/90/365 days)
- Export: JSON, CSV, GPX, KML, monthly business PDF

### Maps & analytics
- MapKit route polylines with speed-colored segments
- Trip stops (dwell detection), route thumbnails
- Swift Charts stats, trends, monthly goals
- Frequent routes, category filters, trip merge/split

### Vehicle care & costs
- **Reminders** — inspection, insurance, comprehensive cover, service due dates with local push (30/7/1 days for service; 7/1 for insurance)
- **Expenses** — log fuel, service, insurance, and other vehicle costs separately from reminders
- One vehicle detail screen under **Vehicles**: profile → reminders → expenses; cost charts live on **Stats**
- Overdue care shown as an in-app banner (no push spam)

### Organization
- Personal / business categories (+ custom)
- Vehicle management (petrol, diesel, hybrid, EV)
- In-app notifications inbox
- Turkish & English UI (Localizable.xcstrings)

---

## Platform support

| Platform | Minimum version | Status |
|----------|-----------------|--------|
| **iPhone (iOS)** | **17.0** | ✅ Primary target |
| **iPadOS** | 17.0 | ⚠️ Runs as iPhone app (not optimized for iPad) |
| **Widget + Live Activity** | iOS 17.0+ | ✅ Home Screen & Lock Screen |
| **Siri / Shortcuts** | iOS 17.0+ | ✅ App Intents + Personal Automations |
| **macOS / visionOS / tvOS** | — | ❌ Not supported |

### Why iOS 17?

Trailhound uses **SwiftData**, **App Intents**, **Live Activities**, and modern **WidgetKit** APIs that require iOS 17. The project does not build for iOS 16 or earlier.

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
3. For hands-free start/stop: create Personal Automations (Bluetooth / CarPlay / Wi‑Fi connect & disconnect) that run those actions

**English Siri examples:** *“Start trip in Trailhound”*, *“Pause trip in Trailhound”*

**Turkish Siri examples:** *“Trailhound yolculuğu başlat”*, *“Trailhound yolculuğu duraklat”*, *“Trailhound yolculuğu sürdür”*, *“Trailhound yolculuğu bitir”*

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
├── Utilities/        # L10n, PDF reports, migrations
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
- [TestFlight release checklist](docs/TESTFLIGHT_RELEASE.md)
- [Vehicle care & expenses](docs/VEHICLE_CARE_PLAN.md) — reminders vs costs, UI layout, notification rules

---

## Özellikler (Türkçe)

Trailhound, yolculuklarınızı **yalnızca cihazınızda** kaydeden gizlilik odaklı bir sürüş günlüğüdür.

- GPS ile rota ve mesafe takibi
- **Kısayollar otomasyonu** ile otomatik başlat-bitir (Bluetooth / CarPlay / Wi‑Fi; Pairing sekmesindeki rehber)
- Siri: *Yolculuğu başlat*, *duraklat*, *sürdür*, *bitir*
- Widget ve Live Activity
- İş/kişisel kategori, yakıt/EV maliyet tahmini
- **Araç avatar fotoğrafı**: Galeri veya Kamera seçimi → uygulama içi ~%70 overlay → kadraj; kayıt / Live Activity’de görünür
- **Araç bakım & hatırlatmalar** — vize, sigorta, kasko, bakım vadeleri + yerel bildirim
- **Araç harcamaları** — yakıt, bakım, sigorta vb. gider kaydı (hatırlatmadan ayrı); maliyet grafikleri Stats’te
- JSON, CSV, GPX, KML, aylık iş PDF export
- Türkçe ve İngilizce arayüz

### Platform desteği

| Platform | Minimum sürüm | Durum |
|----------|---------------|-------|
| **iPhone (iOS)** | **17.0** | ✅ Ana hedef |
| **iPadOS** | 17.0 | ⚠️ iPhone uygulaması olarak çalışır |
| **Widget + Live Activity** | iOS 17.0+ | ✅ Ana ekran ve kilit ekranı |
| **Siri / Kısayollar** | iOS 17.0+ | ✅ App Intents + Kişisel Otomasyonlar |
| **macOS / visionOS / tvOS** | — | ❌ Desteklenmiyor |

**iOS 17 zorunlu** — SwiftData, App Intents ve Live Activity bu sürümü gerektirir. iOS 16 ve altı desteklenmez.

Gerçek sürüş, arka plan kaydı ve Kısayollar otomasyonları için **fiziksel iPhone** önerilir.

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
