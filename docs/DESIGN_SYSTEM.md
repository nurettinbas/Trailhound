# Design system — Liquid Glass

Trailhound’s shell is a saturated atmosphere gradient with frosted glass cards. Settings → Appearance includes a **20-color palette**. One hue is stored; Light uses a vivid wash of that hue with **white type**, and Dark uses a deep shade of the same color. Default is **Sky**.

## Tokens

| Token | Light | Dark |
|---|---|---|
| Atmosphere | Selected `ShellPalette` light triplet (Sky default `#7DBCF5` → `#4F9BE6` → `#2E73C9`) | Selected `ShellPalette` dark triplet (Sky default navy) |
| Panel fill | white 0.10 + palette tint 0.22 + 1 pt white rim 0.22 | `ultraThinMaterial` + palette tint |
| Chrome / chips | white 0.08; selected tint fill + white type | palette tint selected pill |
| Native glass tint | palette tint 0.18 (not milky white) | n/a (legacy material) |
| Text | white / white 0.74 | `.primary` / `.secondary` |
| Control tint | white on the colored shell | palette tint |
| Tab selection | palette tint icon + iOS 26 pill; unselected dark ink on the white floating bar | palette tint; unselected secondary |
| Semantics | `#FF6B6B` / `#FFB35C` / `#7BE495` / `#FF7A7A` | system red / orange / green |
| Recording / live follow | Selected palette glow + tint on the card, follow path, and vehicle puck | Same hue, dark shade |
| Pause chip (live follow) | Opaque orange (`TrailhoundBrandColors.paused`) + white type — never glass + hierarchical white | Same |
| Stop / unread badge / live-map close | Opaque system red `#FF3B30` (`GlassSemantic.notificationBadge`) — never glass-tinted, never palette | Same |

Source of truth: `ShellPalette.swift`, `GlassPalette.swift`, `GlassStyle.swift`. Sky tokens stay mirrored on `TrailhoundBrandColors.atmosphere*` for brand marks.

Palette hues: Sky, Ocean, Teal, Mint, Forest, Lime, Gold, Sunset, Orange, Coral, Rose, Pink, Magenta, Purple, Violet, Indigo, Slate, Graphite, Sand, Ember. Stored in the App Group as `shellPalette`.

The Home Screen icon follows the same hue. **Sky** is the primary Liquid Glass `Trailhound.icon` (light fill + dark navy appearance) plus `Trailhound.appiconset` for iOS 17/18. Every other palette is an alternate Icon Composer file `AppIcons/AppIcon<Name>.icon` with the same light/dark fills — not an `.appiconset`. Xcode 26 flags alternate PNG catalogs as an unassigned Dark `[1d]` child. `AppIconSync` calls `setAlternateIconName` when Appearance changes; iOS always shows a system confirmation. Home Screen light/dark still follows the iPhone appearance, not the in-app Light/Dark picker. In-app brand marks and the share-card raster use the same fill (`homeScreenIconFill`: light tint / dark mid) on `TrailhoundLogo`. Rebuild icons with `scripts/export_alternate_app_icons.py`.

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

- Increased Contrast raises Light panel fill to 0.32. It does not darken the pastel atmosphere.
- Reduce Transparency uses `GlassEngine.solid`.
- Reduce Motion skips chip morph and sheen animation.
- VoiceOver labels are unchanged. Palette swatches use `settings.shellPalette.<id>`.

## Code map

| File | Role |
|---|---|
| `ShellPalette.swift` | 20 hues, Light/Dark triplets, tint, chrome, luminance |
| `GlassEngine.swift` | Resolve native / material / solid |
| `GlassPalette.swift` | Light tokens + scheme-aware text / semantics |
| `GlassEnvironment.swift` | `.onGlassShell()`, `.glassAccentForeground()`, `shellPalette` env |
| `GlassControls.swift` | Toggle tint, section header/footer, nav circle icon |
| `GlassButtonStyles.swift` | `.trailhoundProminentButton()` / `.trailhoundGlassButton()` / `.trailhoundDestructiveButton()` |
| `GlassStyle.swift` | Atmosphere, surfaces, chips, list chrome |
| `TrailhoundTabBarCompact.swift` | Palette selected-tab tint (system floating-bar width) |
| `AppIconSync.swift` | Palette → alternate Home Screen icon |
| `TrailhoundBrandMark.swift` | In-app / share-card logo recolored to `homeScreenIconFill` |
