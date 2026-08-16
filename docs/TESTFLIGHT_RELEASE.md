# TestFlight and App Store release checklist

## Prerequisites

- Apple Developer Program membership
- App icon (1024×1024)
- Privacy policy URL (location data stays on device)

## Automated tests (CI / local)

- [ ] `./scripts/run_tests.sh` green (unit + UI smoke)
- [ ] GitHub Actions `iOS Tests` workflow green

## Xcode setup

1. Bundle ID: `com.trailhound.app`
2. Widget: `com.trailhound.app.widget`
3. Signing: Automatic + select Team
4. Capabilities: App Groups, Background Modes (location)

## App Store Connect

1. Create a new app
2. Include privacy manifest: `PrivacyInfo.xcprivacy`
3. Location usage description: trip recording
4. Screenshots: list, detail map, stats, settings

## TestFlight

1. Archive → Distribute → App Store Connect
2. Internal testing group
3. Complete the **physical device** checklist below (not automatable in CI)

## Physical device test checklist

These items are also mirrored in code as `DeviceTestChecklist` (`DeviceTestChecklistTests`).

- [ ] **30+ min real drive** — distance and duration advance
- [ ] **Background** — background the app, wait 5 min: recording continues
- [ ] **Shortcuts auto-start** — recording starts when connecting to the car (Bluetooth / CarPlay / Wi‑Fi automation)
- [ ] **Shortcuts auto-stop** — recording stops when leaving the car
- [ ] **Orphan recovery** — force-quit → reopen → orphan banner / recovery
- [ ] **Map** — detail map route looks realistic (does not cross water)

Optional smoke:

- [ ] **Manual recording** — start / pause / end from the app
- [ ] **Live follow map** — recording card map button → heading follow → pan then recenter → pause/stop from the map
- [ ] **Live follow map feel** — vehicle mark sits at screen center; chevron + puck faces travel direction; 3D/2D toggle changes pitch/buildings
- [ ] **Widget / Siri** — start / stop recording via widget or Siri shortcut
- [ ] **Export** — JSON, CSV, GPX, or KML

## Vehicle care & expenses (V13)

- [ ] **Schema upgrade** — open with an existing store; no trip/vehicle loss
- [ ] **Add due date** — service (30/7/1) and insurance/casco (7/1) reminders are scheduled
- [ ] **Overdue banner** — red warning above Trips; dismiss lasts until next day
- [ ] **Add expense** — amount + category; Stats → Vehicle costs chart updates
- [ ] **Delete vehicle** — schedule/expense cascade + care notifications cancelled
- [ ] **Recording scroll** — Trips scrolling stays smooth while a trip is active (no banner regression)

## Installments (V14)

- [ ] **Schema upgrade** — existing one-shot expenses stay one-shot; no trip/vehicle/expense loss
- [ ] **Six installments** — add a 1 200 expense as 6; list shows this month’s 200 + Upcoming for the rest
- [ ] **Stats month** — current month Vehicle costs shows only that month’s share
- [ ] **Edit plan** — change total or count from any slice; all siblings update
- [ ] **Delete** — delete one installment vs delete entire plan

## Auto-record with Shortcuts

- Auto start/stop is set up via **Shortcuts Personal Automations** (guide under the Pairing tab).
- In-app Bluetooth audio-route matching was removed; no extra Bluetooth entitlement is required.
- Location + background location mode are used only during an active recording.

## Release order (summary)

1. Automated tests green
2. Upload TestFlight internal build
3. Physical device checklist (core 6 items)
4. Archive → App Store Connect
