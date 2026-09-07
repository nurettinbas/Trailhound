# TestFlight and App Store release checklist

## Prerequisites

- Apple Developer Program membership
- App icon (1024×1024)
- Privacy policy URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/PRIVACY.md`
- Support URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/SUPPORT.md`

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
5. Privacy Policy URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/PRIVACY.md`
6. Support URL: `https://github.com/nurettinbas/Trailhound/blob/main/docs/SUPPORT.md`
7. App Privacy (nutrition label), aligned with `docs/PRIVACY.md`:
   - Precise Location — not linked, not used for tracking, App Functionality (on-device recording)
   - If declaring the optional report flow: Customer Support + Other Diagnostic Data, linked to the user via their email, App Functionality only, not tracking. Collection is user-initiated each time (Mail / share sheet). Do not also claim “we collect no data.”
8. App Review Notes: Report a problem opens system Mail or the share sheet only after the user confirms. There is no automatic upload, analytics, or tracking. The attachment has no coordinates, names, or photos. Reviewer devices without Apple Mail should use the share-sheet fallback.

## TestFlight

1. Archive → Distribute → App Store Connect
2. Internal testing group
3. Complete the **physical device** checklist below (not automatable in CI)

## Physical device test checklist

These items are also mirrored in code as `DeviceTestChecklist` (`DeviceTestChecklistTests`).

- [ ] **30+ min real drive** — distance and duration advance
- [ ] **Background** — background the app, wait 5 min: recording continues
- [ ] **Shortcuts auto-start** — recording starts when connecting to the car (Bluetooth / CarPlay / Wi‑Fi automation)
- [ ] **Shortcuts vehicle pick** — separate CarPlay vs Bluetooth automations assign different vehicles on Start trip
- [ ] **Shortcuts auto-stop** — recording stops when leaving the car
- [ ] **Orphan recovery** — force-quit → reopen → orphan banner / recovery
- [ ] **Map** — detail map route looks realistic (does not cross water)

Optional smoke:

- [ ] **Manual recording** — start / pause / end from the app
- [ ] **Live follow map** — recording card map button → heading follow → pan then recenter → **Show entire route** fits start + trail (north-up; vehicle photo + chevron still face travel) → pause: map and 2D/3D tools lock, vehicle stays put, Resume/Stop/close still work
- [ ] **Live follow map feel** — vehicle mark at screen center while following; single blue path appears immediately (no blank window); fills in behind you with no duplicate stroke, no 1 Hz “chunk” at the puck, and never draws ahead of the puck; pan keeps puck + trail updating
- [ ] **Live follow open at speed** — open while moving fast: curved vehicle→puck flight lands on the puck; blue path does not race ahead of a frozen camera during the fade
- [ ] **Live follow map stroke** — path thickness identical in 2D and 3D, and uniform end-to-end while panning a pitched (3D) camera; motion glides with no per-second stall/surge (camera, vehicle mark, and blue path together); camera pulls back at highway speed
- [ ] **Widget / Siri** — start / stop recording via widget or Siri shortcut
- [ ] **Export** — JSON, CSV, GPX, or KML
- [ ] **Report a problem** — Settings → About → Report a problem; confirm disclosure; Mail or share sheet attaches `trailhound-debug.txt`; no Dev Log tab

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

## Travel journal (V19)

- [ ] **Create travel** — Trips tab → Travels → create a journal, pick completed trips; map shows every member route
- [ ] **Suggestion chip** — away-from-home run appears as Suggested travel; Accept files trips, Dismiss does not nag the same fingerprint
- [ ] **Add to travel** — trip detail under the note; Move / Remove does not delete the trip

## Share card

- [ ] **Share from trip detail** — preview then system share; card + icon follow Appearance palette (not a fixed dark poster); home/work privacy radius clips the route (no raw GPS at saved places)

## Smart category (V20)

- [ ] **Suggestion** — Settings toggle on; a completed commute/work-hours trip shows a pending category on the list row; swipe accepts; nothing applies automatically

## Auto-record with Shortcuts

- Auto start/stop is set up via **Shortcuts** (guide under the Pairing tab): named Shortcut with **Vehicle**, then Personal Automation → **Run Shortcut**.
- On **Start trip**, set **Vehicle** in that named Shortcut (Personal Automations often hide the picker).
- In-app Bluetooth audio-route matching was removed; no extra Bluetooth entitlement is required.
- Location + background location mode are used only during an active recording.

## Release order (summary)

1. Automated tests green
2. Upload TestFlight internal build
3. Physical device checklist (core 6 items)
4. Archive → App Store Connect
