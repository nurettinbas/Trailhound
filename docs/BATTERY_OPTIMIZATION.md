# Battery optimization notes

## Applied strategies

1. **Idle:** `LocationService` is off when not recording (Shortcuts automation does not keep GPS listening inside the app).
2. **While recording:** `startTracking()` — navigation accuracy, 5 m filter.
3. **Geocoding:** Only at trip start/end; pending offline, retry when network returns.
4. **Polyline:** Douglas–Peucker simplification at 1000+ points (display path only).
5. **Timer:** 1 s elapsed timer only during an active recording.
6. **Recording animation:** 15 FPS in Low Power Mode; respects `reduceMotion`.

## Verify with Instruments

1. Connect a physical iPhone.
2. Xcode → Product → Profile → Energy Log.
3. Scenarios: 30 min drive recording, background, Shortcuts start/stop.
4. Goal: Location Services must not stay on continuously outside recording.

## Background work audit

- Auto start/stop: **Shortcuts Personal Automations** (Bluetooth / CarPlay / Wi‑Fi). No in-app Bluetooth audio-route listener.
- Live Activity: only while recording.

## Pre–TestFlight checklist

- [ ] 2+ hour real drive: battery drain acceptable
- [ ] GPS stops when recording ends
- [ ] Shortcuts automation: recording starts on car connect, stops on disconnect
- [ ] No continuous GPS in background when idle
