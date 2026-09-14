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
| Row disclosure `>` | Palette chrome (`GlassControlTint.disclosure` / `GlassDisclosureChevron`) — not tertiary gray | `.secondary` |
| Tab selection | palette tint icon + iOS 26 pill; Light capsule = system glass + mid-family tint 0.28; unselected dark ink | palette tint; unselected secondary |
| Nav toolbar | System iOS 26 platter + `tintColor` glyphs (`GlassToolbarSymbol` / `Title` / `Cluster`). `onGlassShell` white tint is overridden so icons stay visible on the platter. Form/list, Trip/Travel detail, and Vehicles detail (same metrics as the Trips cluster). Custom back still hides the system chevron; `NavigationInteractivePopEnabler` restores edge-swipe pop (Vehicles blocks it only while the editor has unsaved edits). | Same platter recipe; glyphs use the dark `tintColor` |
| Map overlay | Frozen 44pt circle (`GlassNavCircleIcon` / `GlassToolbarSampling.frozenControl`): opaque white + mid-family tint 0.28 (`GlassContrast.toolbarLightFill`) + `tintColor` glyphs — never the dark solid panel, never live Material / `glassEffect` over MapKit. Stats expand collapse (Badges, Frequent routes, month forecast). | Grouped solid + palette tint glyphs |
| Overlay toolbar | Same 44pt `frozenControl` plate as map overlay (Year recap story Share/Close). Not live Material over the story Canvas. | Same grouped solid |
| Overlay chrome | `GlassToolbarControlBackground` Material / solid — never native `glassEffect` (camera, photo grid, delete confirm) | Same |
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

This is a color and glass-layer change. Spacing, padding, radii, fonts, minHeights, grids, animations, and accessibility identifiers stay put. Tab switches use `TrailhoundMotion.tabSwitch`. Never put `animation = nil` on `TabView` — it pauses `TimelineView.animation` (recap, onboarding). List-hosted motion (recording road, Start hound, steering-wheel badge) uses `TrailhoundDisplayLinkTicker`, not `TimelineView`. Recap / onboarding clocks use `TrailhoundIndependentClock.periodic`. The Stats filter card (`stats.filters.*`) is the shape reference. Form/list **and** Trip/Travel detail nav items use system toolbar metrics (the Trips cluster) instead of custom circles. Overlay collapse and story Share/Close use the 44pt frozen circle (`frozenControl` / `GlassNavCircleIcon`). Compact `.frozen` 36pt stays available for a smaller map chip.

## Accessibility

- Body copy on Light glass is white. Do **not** darken cards to force a WCAG 4.5:1 composite — that turns Forest/Gold into olive plates. Increased Contrast raises mid-family tint and rim, not white frost.
- Reduce Transparency uses `GlassEngine.solid` with opaque mid-family fill, not system grouped white and not chrome.
- Reduce Motion skips chip morph, sheen, card-press scale, forecast glint, segment-bar grow-in, recap hub idle, Play-chip pulse, badge flag-wave, distance path-node travel, and night sky bob.
- VoiceOver labels are unchanged. Palette swatches use `settings.shellPalette.<id>`.
- System exceptions stay system: `.alert`, Mail, share sheet, keyboard, Lock Screen widget, Live Activity. Light floating tab bar keeps system glass with a one-step mid-family tint.
- Legitimate blacks stay black: map vignette/dimming, delete/merge scrims, shadows, camera/crop stage. Semantic Stop/unread remains solid red.

## Code map

| File | Role |
|---|---|
| `ShellPalette.swift` / `GlassContrast.swift` | 20 hues, Light/Dark triplets, mid-family glass tint (not chrome plates) |
| `GlassEngine.swift` | Resolve native / material / solid |
| `GlassPalette.swift` | Light tokens + scheme-aware text / semantics |
| `GlassEnvironment.swift` | `.onGlassShell()`, ink hierarchy, `.glassDisclosureInk()`, `shellPalette` env |
| `GlassControls.swift` | Toggle tint, section header/footer, `GlassDisclosureChevron`, toolbar symbol/title/cluster |
| `NavigationInteractivePopEnabler.swift` | Edge-swipe pop when the system back button is hidden; `disabled` blocks pop while a vehicle editor has unsaved edits |
| `GlassButtonStyles.swift` | `.trailhoundProminentButton()` / `.trailhoundCompactProminentButton()` / `.trailhoundGlassButton()` / `.trailhoundDestructiveButton()` / `.trailhoundCardPress()` |
| `GlassStyle.swift` | Atmosphere, surfaces, chips, list chrome, `.glassNestedChoice(isSelected:)` (frost fill inside a card — not a second Material) |
| `StatsCard.swift` | Stats full/half cards, nested tiles, `.statsNestedPanel()` (variable-height frost in expand overlays), `.statsFrostChip()`, `StatsSegmentBar` / `StatsSegmentSwatch` / `StatsShareBar` (vehicle-compare share of top spend, donut slice fill), overlay `posterHeight` / `posterExpandedHeight`. Recap and month-forecast posters use `contentInset: 0` plus `.statsPosterOverlayPadding()` so artwork fills the card. Forecast sparkline uses `.statsPosterSparklineVeil()` so hero copy reads. |
| `TrailhoundMotion.swift` | `.numericTextAnimation`, `.glassEntranceGlint` (alias `.photoEntranceGlint`), `tabSwitch` |
| `TrailhoundIndependentClock` | Periodic `TimelineView` clocks for recap / onboarding (not inside a `List`) — not `TimelineView.animation` |
| `TrailhoundDisplayLinkTicker` | `CADisplayLink` host for List cells (recording road, Start hound, steering-wheel, stop-credits). Keep it **outside** `.drawingGroup`. |
| `TrailhoundTabBarCompact.swift` | Palette selected-tab tint (system floating-bar width) |
| `AppIconSync.swift` | Palette → alternate Home Screen icon; coalesced public API call |
| `TrailhoundBrandMark.swift` | In-app / share-card logo recolored to `homeScreenIconFill` |
| `RecapShareRenderer.swift` | Year recap Share PNG is `ImageRenderer` of the visible story page (`RecapPageScene` + copy), 9:16. Not a separate Core Graphics poster. |
| `AchievementTheme.swift` | 3D medal chrome (`AchievementMedalChrome`). Km medals are metal (100 silver, 1,000 gold, 10,000 **teal platinum**, 100,000 **lavender diamond**). Glyphs are **white** on every disc (including silver/gold). Every other family has a unique hue (≥18° apart), unique SF icon per ID, and unique idle (`AchievementFamilyIdleEffect`) — no shared pulse. Enamel ladders shift hue +8° per tier so rungs are not clones. Cards stay glass. Locked medals dim the disc under an opaque family glyph; the lock is a small opaque rim badge (`AchievementMedalLockOverlay`), not a translucent film over the icon. First-trip flag waves; distance S-path choreography; night owl moon+stars; 24h hourglass pours 180° on X; trips wheel sways ±20° (not a full spin); 100 km one-trip car drives left→right and fades (not a reverse). Stats and Year in review share this overlay. |
| `PermissionBanner.swift` | `LocationPermissionBadge` / `NotificationPermissionBadge` share `PermissionStatusCapsule` (same opaque pill chrome as location status) |
| `StatsChartTheme.swift` | Chart fills, bar radius, axis chrome. Tick labels and Y-axis units (`km`, `h`, currency) use `axisLabelInk` / `.chartStatsYAxisUnit` — never unstyled `.chartYAxisLabel` (black on Light). Forecast sparkline uses `chartStatsSparklineFill(maxValue:)` (Y headroom + 12pt plot padding) so the peak is not clipped. |

## Buttons

| Intent | API |
|---|---|
| Primary (forms, sheets) | `.trailhoundProminentButton()` |
| Compact in-card CTA | `.trailhoundCompactProminentButton()` — intrinsic tint capsule, ~32 pt visual, 44 pt hit; **never truncates** |
| Secondary on glass | `.trailhoundGlassButton()` |
| Destructive / Stop | `.trailhoundDestructiveButton()` |
| Whole card press | `.trailhoundCardPress()` |

## Nested fills

| Intent | API |
|---|---|
| Choice / instruction tile inside a glass card | `.glassNestedChoice(isSelected:)` — selected = chip mid-family fill + white type; unselected = nested frost tint. Not `statsNestedTile`, not a second Material. Pair with `.trailhoundCardPress()` when tappable. |
