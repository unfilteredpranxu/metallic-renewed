# Metallic Renewed UI specification

## Authority and implementation boundary

Primary visual authority: the user's six screenshots, which are NOT attached in the current conversation. The following is the user's textual design specification and source-informed implementation plan, not a screenshot-verified design. Do not invent pixel measurements, color hex values, font sizes or screenshot fidelity. Read `METALLIC_RENEWED_PROGRESS.md` first for scope, existing actions, protected modules and baseline.

Same application, same engine and same functionality; customize existing UIKit. Keep existing SwiftUI components when working. M0 implements no redesign.

## Visual system (planned)

- Premium native Apple appearance, clean and minimal. Cohesive Liquid Glass, rounded translucent cards, readable borders, restrained animation, SF Symbols and elegant typography. Avoid generic dashboard styling.
- Colors: use semantic colors and existing accent/text/card preferences; exact reference palette UNKNOWN. Validate contrast over bright/dark wallpapers in all themes.
- Typography: use native text styles and scalable readable hierarchy; preserve localization and accessibility. Exact reference font metrics UNKNOWN.
- Spacing: consistent grouping, comfortable touch areas and safe-area-aware margins; reference spacing/radii UNKNOWN. Existing navigation geometry is coupled (see progress); do not casually resize it.
- Cards/navigation: selected state and hierarchy must be clear, motion restrained and hit testing correct. Native child containment and transition safeguards remain mandatory.
- Wallpaper: full-screen presentation with readable foreground; preserve existing image/video/default paths and migration. Wallpaper blur/dimming must remain distinct from UI panel opacity in design intent; existing implementation shares blur refresh, so independent control semantics are not yet established.
- Theme: System/Light/Dark map to existing auto/light/dark values; persist and apply without account reset.
- Glass/blur/opacity: use actual UIKit materials and supported fallbacks. Reuse existing style, intensity and opacity keys/setters; no inert controls. Distinguish absent defaults from valid zero. Reset to Recommended is planned; do not reuse a destructive wallpaper/settings reset blindly.

## Destinations

| Destination | Desired UI | Verified existing capability / integration boundary |
| --- | --- | --- |
| Home | Metallic branding, centered pill navigation, welcome heading, large selected-instance card, Play Now, account/profile information, right-side My Metallic status, Minecraft/Java/JIT/download status, instance cards, See All and useful empty states | `LauncherNewsViewController`, `HomeTopNavView`, hidden child right-panel state/action bridge exist. Reuse launch/version/account callbacks from progress. Exact See All/Java-status presentation wiring needs confirmation; never simulate state |
| Instances | Native responsive cards, real selection, useful empty state and existing management routes | `VersionManagerViewController` and saved `PLProfiles` selection exist; preserve all management functionality and isolation behavior |
| Downloads | Sidebar categories, search, version filters, sorting, real actions/progress/errors | `DownloadViewController` catalogue and `DownloadTasksViewController` task centre exist; retain existing data/actions rather than recreate installation logic |
| Appearance | System/Light/Dark, Interface Glass, UI Blur, UI Panel Opacity, Reset to Recommended, wallpaper and existing launch-intro settings | Settings theme + glass helpers and `BackgroundSettingsViewController` already provide appearance controls; dedicated root destination is planned. Exact launch-intro callback/key UNKNOWN; confirm before exposing. Recommended reset semantics need definition |
| Settings | Keep every current switch, slider, picker, save action and advanced option accessible | `LauncherPreferencesViewController` generic preference mapping exists. Engine preferences and enable conditions must not change |

Current root order is Home / Downloads / AI / Instances / Settings. Desired primary order is Home / Instances / Downloads / Appearance / Settings. A later UI milestone must map all numeric tab consumers and preserve AI access and navigation stacks before rearrangement. No replacement controller architecture is approved.

## Device adaptation and verification

Support iPhone/iPad, compact/wide widths, supported portrait/landscape, safe areas, keyboard, sheets and anchored popovers. Avoid clipping, double insets and invisible interactive overlays. Dynamic Type, VoiceOver, meaningful labels, contrast, touch comfort and reduced-motion behavior require device review. Do not optimize for a single iPad screenshot at the expense of iPhone.

Existing source layout values are recorded in progress as compatibility constraints, not reference measurements. All visual, functional and persistence acceptance checks remain PENDING until executed; see `METALLIC_RENEWED_TEST_MATRIX.md`.
