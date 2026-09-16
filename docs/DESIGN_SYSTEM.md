# Design system — Liquid Glass

Trailhound’s shell is a saturated atmosphere gradient with frosted glass cards. Settings → Appearance includes a **20-color palette**. One hue is stored; Light uses a vivid wash of that hue with **white type**, and Dark uses a deep shade of the same color. Default is **Sky**.

## Tokens

| Token | Light | Dark |
|---|---|---|
| Atmosphere | Selected `ShellPalette` light triplet (Sky default `#7DBCF5` → `#4F9BE6` → `#2E73C9`) | Selected `ShellPalette` dark triplet (Sky default navy) |
| Panel fill | Atmosphere mid + light same-hue mix (~0.22, 0.34 Increased Contrast) + white frost 0.03 + white rim 0.28 — not chrome | `ultraThinMaterial` + palette tint |
| Chrome / chips | Selected = mid-family fill + white type; unselected = frost + white | palette tint selected pill |
| Native glass tint | mid mixed 0.42 toward bottom, opacity 0.50 (0.62 Increased Contrast) behind content — not ice, not chrome. Native rim 0.10. Clip the **plate** to the card, never the labels (corner type must not be sliced) | n/a (legacy material) |
| Text | white / white 0.88 / white 0.70 | `.primary` / `.secondary` |
| Solid / Reduce Transparency | Opaque mid mixed slightly toward bottom — never system grouped white, never chrome plate | system grouped + tint |
| Field wells | mid-family tint 0.18 + thin white rim 0.42 (0.56 Increased Contrast), 1 pt — `.glassInputField()` / `.glassInputWell()`. Change `LightGlassPalette.fieldRimOpacity` to restyle every Light input. | white 0.10 fill, **no** rim |
| Control tint | white on the colored shell | palette tint |
| Compact DatePicker | `.glassDatePicker()` — Light labels are white (`glassControlScheme`); never system black compact ink | same, palette tint |
| Menu Picker | `.glassMenuPicker()` — Light value + chevron are white (`GlassControlTint.control`); never system accent blue | same, palette tint |
| Row disclosure `>` | Palette chrome (`GlassControlTint.disclosure` / `GlassDisclosureChevron`) — not tertiary gray | `.secondary` |
| Tab selection | Custom `TrailhoundFloatingTabBar` + `.glassTabBar()` (Capsule `.clear` glass). Unselected glyphs **white**, selected icon + title **black** (Dark selected keeps vivid palette tint). Not the system `UITabBar`. | Dark: white unselected, palette selected |
| Nav toolbar | System iOS 26 **clear** item platters (dock-like — not `.regular` milk, not a dark-scheme smoky plate, not a white `.tint` wash) + `tintColor` glyphs (`GlassToolbarSymbol` / `Title` / `Cluster`). Do **not** force `toolbarColorScheme(.light)` or white `.tint` — both paint an extra plate. `.glassNavigationChrome()` hides the bar background **and** the iOS 26 top/bottom scroll-edge blur. Map screens also use `.glassMapTopEdgeHidden()`. Form/list, Trip/Travel detail, and Vehicles detail (same metrics as the Trips cluster). Custom back still hides the system chevron; `NavigationInteractivePopEnabler` restores edge-swipe pop (Vehicles blocks it only while the editor has unsaved edits). | Dark item platters; glyphs use the dark `tintColor` |
| Overlay collapse | 44pt Liquid Glass circle (`GlassToolbarCollapseButton` / `GlassNavCircleIcon` / `.glassCircleChrome()`): native `glassEffect(.regular.interactive())` in `Circle()` in Light **and** Dark — same chrome as the Trip/Travel toolbar back circle. Stats expand collapse, Year recap Share/Close. | Same |
| Map overlay | Do not add extra live `glassEffect` hosts on the map beyond the Stats collapse circle. | Grouped solid + palette tint glyphs |
| Overlay toolbar | Same 44pt Liquid Glass circle as overlay collapse (Year recap Share/Close). | Same |
| Overlay chrome | `GlassToolbarControlBackground` Material / solid — never native `glassEffect` (camera, photo grid, delete / merge confirm). Keyboard accessory Place name / OK chips use the same API `frozen: true`; palette and Light/Dark come from `FieldKeyboardAccessoryHost`. Dark solid also washes palette tint 0.22 so chips are not a system gray plate. | Same |
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

Light cards, Stats full/half cards, grouped list rows (`glassRow`), and Badges gallery cells use native `glassEffect` **behind** the content so the atmosphere shows through as colored glass — not a milky white plate and not a frost over type. Clip/mask the **plate** to the card; do **not** clip labels (corner type such as Name must stay whole). Nested tiles, field wells, and unselected chips stay frost fills (not a second glass host). Pin with `allowsNative: false` or `frozen:` for camera, map overlays, share rasters, and the Badges **expand morph** plate. Budget: at most eight native glass hosts on screen; if Stats/Trips/gallery scroll drops below ~58 fps, pin that surface. `GlassChipGroup` still batches chip hosts; do **not** wrap a `List` or a row of `glassChrome` tiles in `GlassEffectContainer` (that milks the labels).

## Shape is not restyled

This is a color and glass-layer change. Spacing, padding, radii, fonts, minHeights, grids, animations, and accessibility identifiers stay put. Tab switches use `TrailhoundMotion.tabSwitch`. Never put `animation = nil` on `TabView` — it pauses `TimelineView.animation` (recap, onboarding). List-hosted motion (recording road, Start hound, steering-wheel badge) uses `TrailhoundDisplayLinkTicker`, not `TimelineView`. Recap / onboarding clocks use `TrailhoundIndependentClock.periodic`. The Stats filter card (`stats.filters.*`) is the shape reference. Form/list **and** Trip/Travel detail nav items use system toolbar metrics (the Trips cluster) instead of custom circles. Stats expand collapse and Year recap Share/Close are 44pt Liquid Glass circles (`GlassToolbarCollapseButton` / `GlassNavCircleIcon` / `.glassCircleChrome()`). Compact `.frozen` 36pt stays available for a smaller map chip.

## Accessibility

- Body copy on Light glass is white. Do **not** darken cards to force a WCAG 4.5:1 composite — that turns Forest/Gold into olive plates. Increased Contrast raises mid-family tint and rim, not white frost.
- Reduce Transparency uses `GlassEngine.solid` with opaque mid-family fill, not system grouped white and not chrome.
- Reduce Motion skips chip morph, sheen, card-press scale, forecast glint, segment-bar grow-in, recap hub idle, Play-chip pulse, badge flag-wave, distance path-node travel, and night sky bob.
- VoiceOver labels are unchanged. Palette swatches use `settings.shellPalette.<id>`.
- System exceptions stay system: `.alert`, Mail, share sheet, keyboard, Lock Screen widget, Live Activity. The CarPlay Dashboard Live Activity must not paint an opaque fill or `activityBackgroundTint` — CarPlay supplies the same Liquid Glass as Now Playing. Light floating tab bar is `.glassTabBar()` (Capsule `.clear`); selected icon + title are black, unselected glyphs are white. The system `UITabBar` stays hidden.
- Legitimate blacks stay black: map vignette/dimming, delete/merge scrims, shadows, camera/crop stage. Semantic Stop/unread remains solid red.

## Code map

| File | Role |
|---|---|
| `ShellPalette.swift` / `GlassContrast.swift` | 20 hues, Light/Dark triplets, mid-family glass tint (not chrome plates) |
| `GlassEngine.swift` | Resolve native / material / solid |
| `GlassPalette.swift` | Light tokens + scheme-aware text / semantics |
| `GlassEnvironment.swift` | `.onGlassShell()`, ink hierarchy, `.glassDisclosureInk()`, `shellPalette` env |
| `GlassControls.swift` | Toggle tint, section header/footer, `GlassDisclosureChevron`, `.glassDatePicker()`, `.glassMenuPicker()`, toolbar symbol/title/cluster, `GlassToolbarCollapseButton` (44pt Liquid Glass circle) |
| `NavigationInteractivePopEnabler.swift` | Edge-swipe pop when the system back button is hidden; `disabled` blocks pop while a vehicle editor has unsaved edits |
| `GlassButtonStyles.swift` | `.trailhoundProminentButton()` / `.trailhoundCompactProminentButton()` / `.trailhoundGlassButton()` / `.trailhoundDestructiveButton()` / `.trailhoundCardPress()` |
| `GlassStyle.swift` | Atmosphere, surfaces, chips, list chrome, `.glassNestedChoice(isSelected:)` (frost fill inside a card — not a second Material), `.glassInputField()` / `.glassInputWell()` (Light white input rim), `.glassCircleChrome()` (44pt overlay collapse), `.glassTabBar()` (floating Capsule `.clear` glass), `.glassEffectGrouping()` (chips only — not Lists), `.glassNavigationChrome()` (no full-width scroll-edge plate), `GlassToolbarControlBackground` (overlay / keyboard accessory chips) |
| `KeyboardDismiss.swift` | Field keyboard accessory: centered title + OK. `UIHostingController` gets `shellPalette` + `preferredColorScheme`; chips are `GlassToolbarControlBackground` (frozen). |
| `DeleteConfirmPresenter.swift` | Root glass confirm + blocking progress (`deleteConfirmHost`). Destructive delete (red capsule, trash) vs prominent merge (palette capsule + white rim, merge glyph). Progress is large `ProgressView` + `.glassCard`, black 0.25 scrim — not a list overlay. |
| `StatsCard.swift` | Stats full/half cards (native Light `glassEffect`), nested tiles, `.statsNestedPanel()` (variable-height frost in expand overlays), `.statsFrostChip()`, `StatsSegmentBar` / `StatsSegmentSwatch` / `StatsShareBar` (vehicle-compare share of top spend, donut slice fill), overlay `posterHeight` / `posterExpandedHeight`. Recap and month-forecast posters use `contentInset: 0` plus `.statsPosterOverlayPadding()` so artwork fills the card. Forecast sparkline uses `.statsPosterSparklineVeil()` so hero copy reads. |
| `TrailhoundMotion.swift` | `.numericTextAnimation`, `.glassEntranceGlint` (alias `.photoEntranceGlint`), `tabSwitch` |
| `TrailhoundIndependentClock` | Periodic `TimelineView` clocks for recap / onboarding (not inside a `List`) — not `TimelineView.animation` |
| `TrailhoundDisplayLinkTicker` | `CADisplayLink` host for List cells (recording road, Start hound, steering-wheel, stop-credits). Keep it **outside** `.drawingGroup`. |
| `TrailhoundTabBarCompact.swift` | `TrailhoundFloatingTabBar` (white unselected, black selected in Light) + hide system `UITabBar` |
| `AppIconSync.swift` | Palette → alternate Home Screen icon; coalesced public API call |
| `TrailhoundBrandMark.swift` | In-app / share-card logo recolored to `homeScreenIconFill` |
| `RecapShareRenderer.swift` | Year recap Share PNG is `ImageRenderer` of the visible story page (`RecapPageScene` + copy), 9:16. Not a separate Core Graphics poster. |
| `AchievementShareRenderer.swift` | Badge Share PNG is `ImageRenderer` of a frozen 9:16 poster (atmosphere, brand, glass plate, 3D medal + copy). Rasterize on export / after gallery settle — not in the idle-clock `body`. |
| `AchievementTheme.swift` | 3D medal chrome (`AchievementMedalChrome`). Km medals are metal (100 silver, 1,000 gold, 10,000 **teal platinum**, 100,000 **lavender diamond**). Glyphs are **white** on every disc (including silver/gold). Every other family has a unique hue (≥18° apart), unique SF icon per ID, and unique idle (`AchievementFamilyIdleEffect`) — no shared pulse. Enamel ladders shift hue +8° per tier so rungs are not clones. Cards stay glass. Locked medals dim the disc under an opaque family glyph; the lock is a small opaque rim badge (`AchievementMedalLockOverlay`), not a translucent film over the icon. First-trip flag waves; distance S-path choreography (clock-snapped on a fixed side so List insert does not vibrate 100 / 1,000 km nodes); night owl moon+stars; 24h hourglass pours 180° on X; trips wheel sways ±20° (not a full spin); 100 km one-trip car stays on the disc and rides a hill (nose follows the slope; never fades). Stats and Year in review share this overlay. |
| `PermissionBanner.swift` | `LocationPermissionBadge` / `NotificationPermissionBadge` share `PermissionStatusCapsule` (opaque status pill, intrinsic single-line width — never hyphenates in the Vehicles toolbar) |
| `StatsChartTheme.swift` | Chart fills, bar radius, axis chrome. Tick labels and Y-axis units (`km`, `h`, currency) use `axisLabelInk` / `.chartStatsYAxisUnit` — never unstyled `.chartYAxisLabel` (black on Light). Forecast sparkline uses `chartStatsSparklineFill(maxValue:)` (Y headroom + 12pt plot padding) so the peak is not clipped. |

## Buttons

| Intent | API |
|---|---|
| Primary (forms, sheets) | `.trailhoundProminentButton()` |
| Compact in-card CTA | `.trailhoundCompactProminentButton()` — intrinsic tint capsule, ~32 pt visual, 44 pt hit; **never truncates** |
| Secondary on glass | `.trailhoundGlassButton()` |
| Destructive / Stop | `.trailhoundDestructiveButton()` |
| Overlay Share / Close | `GlassNavCircleIcon` — same 44pt Liquid Glass circle |
| Collapse / exit-fullscreen | `GlassToolbarCollapseButton` — 44pt Liquid Glass circle (`.glassCircleChrome()`) |
| Whole card press | `.trailhoundCardPress()` |
| Glass confirm (delete) | `DeleteConfirmPresenter` role `.destructive` — red capsule, `trash.circle.fill`. Same 48 pt pair as Cancel. |
| Glass confirm (merge) | role `.prominent` — palette fill + white rim (same recipe as Light prominent), `arrow.triangle.merge`. Never a system `.alert`. |
| Blocking progress (merge) | Same root host: large `ProgressView` + `L10n.tripsMergeProgress` on `.glassCard`. Black 0.25 scrim. Do not put this overlay on `TripListView`. |

## Nested fills

| Intent | API |
|---|---|
| Choice / instruction tile inside a glass card | `.glassNestedChoice(isSelected:)` — selected = chip mid-family fill + white type; unselected = nested frost tint. Not `statsNestedTile`, not a second Material. Pair with `.trailhoundCardPress()` when tappable. |
| Tile on atmosphere (trip fuel factors) | `.glassChrome` — same native plate as duration/distance cards. Not nested fill. |
| Travel journal selected trip | `.glassChrome(enabled:)` — same native plate as the trip list. Not a white wash. |
| Text field | `.glassInputField()` — frost well + Light white rim (`LightGlassPalette.fieldRimOpacity`). Dark: fill only. |
| Search / custom input well | `.glassInputWell()` — same rim as text fields; caller supplies padding. Not `glassField` (that is fill-only, used by stepper chips). |
