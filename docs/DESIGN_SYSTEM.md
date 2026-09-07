# Design system — Liquid Glass

Trailhound’s shell is a saturated atmosphere gradient with frosted glass cards. Settings → Appearance includes a **20-color palette**. One hue is stored; Light uses a vivid wash of that hue with **white type**, and Dark uses a deep shade of the same color. Default is **Sky**.

## Tokens

| Token | Light | Dark |
|---|---|---|
| Atmosphere | Selected `ShellPalette` light triplet (Sky default `#7DBCF5` → `#4F9BE6` → `#2E73C9`) | Selected `ShellPalette` dark triplet (Sky default navy) |
| Panel fill | Atmosphere mid + light same-hue mix (~0.22, 0.34 Increased Contrast) + white frost 0.03 + white rim 0.28 — not chrome | `ultraThinMaterial` + palette tint |
| Chrome / chips | Selected = mid-family fill + white type; unselected = frost + white | palette tint selected pill |
| Native glass tint | same mid-family hue 0.16 (0.26 Increased Contrast) | n/a (legacy material) |
| Text | white / white 0.88 / white 0.70 | `.primary` / `.secondary` |
| Solid / Reduce Transparency | Opaque mid mixed slightly toward bottom — never system grouped white, never chrome plate | system grouped + tint |
| Field wells | mid-family tint 0.18 | white 0.10 |
| Control tint | white on the colored shell | palette tint |
| Tab selection | palette tint icon + iOS 26 pill; Light capsule = system glass + mid-family tint 0.28; unselected dark ink | palette tint; unselected secondary |
| Semantics | `#FF6B6B` / `#FFB35C` / `#7BE495` / `#FF7A7A` | system red / orange / green |
| Recording / live follow | Selected palette glow + tint on the card, follow path, and vehicle puck | Same hue, dark shade |
| Pause chip (live follow) | Opaque orange (`TrailhoundBrandColors.paused`) + white type — never glass + hierarchical white | Same |
| Stop / unread badge / live-map close | Opaque system red `#FF3B30` (`GlassSemantic.notificationBadge`) — never glass-tinted, never palette | Same |

Source of truth: `ShellPalette.swift`, `GlassPalette.swift`, `GlassStyle.swift`. Sky tokens stay mirrored on `TrailhoundBrandColors.atmosphere*` for brand marks.

Palette hues: Sky, Ocean, Teal, Mint, Forest, Lime, Gold, Sunset, Orange, Coral, Rose, Pink, Magenta, Purple, Violet, Indigo, Slate, Graphite, Sand, Ember. Stored in the App Group as `shellPalette`.

The Home Screen icon follows the same hue. **Sky** is the primary Liquid Glass `Trailhound.icon` (light fill + dark navy appearance) plus `Trailhound.appiconset` for iOS 17/18. Every other palette is an alternate Icon Composer file `AppIcons/AppIcon<Name>.icon` with the same light/dark fills — not an `.appiconset`. Xcode 26 flags alternate PNG catalogs as an unassigned Dark `[1d]` child. `AppIconSync` coalesces repeated palette updates, synchronizes the UIKit window to the selected Appearance, then calls the public `setAlternateIconName` API. iOS presents the single required confirmation. Home Screen light/dark still follows the iPhone appearance, not the in-app Light/Dark picker. In-app brand marks and the share-card raster use the same fill (`homeScreenIconFill`: light tint / dark mid) on `TrailhoundLogo`. Rebuild icons with `scripts/export_alternate_app_icons.py`.

## Engine

`GlassEngineResolver` picks one renderer:

1. Reduce Transparency or `frozen` → **solid** fill (no Material resampling of a live map).
2. Dark → **material** (legacy).
3. Light + iOS 26+ + `allowsNative` → **native** (`glassEffect` + `GlassEffectContainer`).
4. Otherwise → **material**.

List rows always pass `allowsNative: false`. Native glass is reserved for standalone cards, chips, chrome, and buttons. Budget: at most eight native glass hosts on screen.

## Shape is not restyled

This is a color and glass-layer change. Spacing, padding, radii, fonts, minHeights, grids, animations, and accessibility identifiers stay put. The Stats filter card (`stats.filters.*`) is the shape reference.

## Accessibility

- Body copy on Light glass is white. Do **not** darken cards to force a WCAG 4.5:1 composite — that turns Forest/Gold into olive plates. Increased Contrast raises mid-family tint and rim, not white frost.
- Reduce Transparency uses `GlassEngine.solid` with opaque mid-family fill, not system grouped white and not chrome.
- Reduce Motion skips chip morph and sheen animation.
- VoiceOver labels are unchanged. Palette swatches use `settings.shellPalette.<id>`.
- System exceptions stay system: `.alert`, Mail, share sheet, keyboard, Lock Screen widget, Live Activity. Light floating tab bar keeps system glass with a one-step mid-family tint.
- Legitimate blacks stay black: map vignette/dimming, delete/merge scrims, shadows, camera/crop stage. Semantic Stop/unread remains solid red.

## Code map

| File | Role |
|---|---|
| `ShellPalette.swift` / `GlassContrast.swift` | 20 hues, Light/Dark triplets, mid-family glass tint (not chrome plates) |
| `GlassEngine.swift` | Resolve native / material / solid |
| `GlassPalette.swift` | Light tokens + scheme-aware text / semantics |
| `GlassEnvironment.swift` | `.onGlassShell()`, `.glassPrimaryInk()` / `.glassSecondaryInk()` / `.glassTertiaryInk()`, `.glassAccentForeground()`, `shellPalette` env |
| `GlassControls.swift` | Toggle tint, section header/footer, nav circle icon |
| `GlassButtonStyles.swift` | `.trailhoundProminentButton()` / `.trailhoundGlassButton()` / `.trailhoundDestructiveButton()` |
| `GlassStyle.swift` | Atmosphere, surfaces, chips, list chrome |
| `TrailhoundTabBarCompact.swift` | Palette selected-tab tint (system floating-bar width) |
| `AppIconSync.swift` | Palette → alternate Home Screen icon; coalesced public API call |
| `TrailhoundBrandMark.swift` | In-app / share-card logo recolored to `homeScreenIconFill` |
