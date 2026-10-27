# Metallic Renewed UI specification

## Authority and implementation boundary

Primary visual authority: the screenshot set attached to M2 (including repeated Home, Appearance, Downloads and Settings captures). These were reviewed in M2. The following records their visual direction alongside the user's textual specification; it does not claim native screenshot matching. Do not invent pixel measurements, color hex values, font sizes or screenshot fidelity. Read `METALLIC_RENEWED_PROGRESS.md` first for scope, existing actions, protected modules and baseline.

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


## M2 reference interpretation and implemented foundation

The supplied captures show wide wallpaper composition, restrained dark neutral translucent surfaces, thin low-contrast outlines, rounded panels, pill navigation with a distinct filled selected segment, SF Symbols, and readable main/supporting text hierarchy. Home includes both empty and selected-instance states; Appearance distinguishes UI Blur/Panel Opacity from wallpaper; Downloads uses a category rail and quiet rows; Settings uses a rail plus grouped panels. These compositions guide subsequent milestones and are not implemented wholesale in M2. Exact colors, point sizes, radii and spacing cannot be reliably inferred from scaled screenshots alone. No new gradients/neon/dashboard layout is introduced.

Implemented APIs in existing `UIKit+GlassSurface.h`: `AmeUIAccentColor` delegates to `AmeThemeTintColor` (existing accent preference/default); semantic primary/secondary/tertiary text, disabled, destructive, panel tint, border, selection-fill and overlay-contrast helpers; `AmeUIResolvedColor` for host-trait CGColors; `AmeUIHairlineWidth`; `AmeUIFont` roles and bounded `AmeUINavigationFont`. Existing card radius helpers and true native material resolver remain the surface foundation. Spacing tokens are conservative implementation defaults, not reference measurements. Font role users must enable adjustsFontForContentSizeCategory on their labels; navigation explicitly refreshes its capped font on content-size changes.

Applied now: existing shared glass button has a quiet material/semantic border instead of permanent glow, optional primary/secondary/subtle/navigation/destructive roles, highlighted/disabled/selected appearance and opt-in busy presentation. Existing bottom actions use secondary role. Navigation adopts semantic foreground/selection, restrained animation/Reduce Motion and selected accessibility state. No new target/action route, product control or preference key exists. Full settings/slider design, screen cards and wallpaper layouts remain planned.

Theme auto/light/dark and notification/window flow remain unchanged. Glass defaults/migration, existing material availability detection and native fallback remain unchanged. No wallpaper dimming or slider values are inferred from panel styles. The new contrast token is a foreground decoration resource, not a wallpaper preference. Current material integration does not implement the reference's blur-zero behavior or change existing intensity/opacity ranges; resolve that separately in M3 using existing functionality.

Existing fixed 60/76 navigation geometry and 36-point bottom actions remain; 44-point touch-size token is guidance for later adaptive layouts, not a claim that every current control meets it. iPhone/wide-screen/large-type/VoiceOver/keyboard/rotation/contrast acceptance remains PENDING. No build/visual/device result supersedes M1's BLOCKED state.


## M3 implemented appearance subset / compatibility

Existing Background Settings now has Interface Glass controls (effect mode, Panel Opacity, UI Blur and a scoped Reset to Recommended), existing wallpaper selection/clear/restore, existing glass style/highlights, and independent Wallpaper Blur/Dimming controls. New sliders use M2 semantic typography/colors, Auto Layout and 44-point touch height, with live percentages/accessibility values and no cell reload while tracking. This is not the complete new Appearance destination; original System/Light/Dark remains in main Settings.

UI Blur represents native material visibility, never an arbitrary blur radius. `background_interface_blur_intensity_v1` seeds the old panel alpha once; `background_blur_intensity` remains wallpaper material strength. `background_wallpaper_dimming_v1` seeds the old strength once, then independently controls a restrained black overlay (gentler in Light); no more Dark-mode white labelColor overlay. Panel Opacity retains its 0.1–1 range/default and adjusts only backdrop tint (maximum 0.22 tint alpha in Blur mode). Text/icons/control alpha are not used for panel opacity. Explicit zero UI Blur removes visible material but keeps tint/text; Translucent mode disables that slider without discarding its stored value.

Native glass capability detection/fallback/migrations remain unchanged. One reusable material per managed surface; only explicit style changes replace its effect. Wallpaper material is separate standard UIKit thin material, skipped by interface-style refresh. Images/video remain aspect-fill; existing default composition is retained. Custom wallpaper controls are disabled with no custom media. New keys live only in the existing manager's NSUserDefaults store; see progress for exact migration, ranges and fallback values.

Reset to Recommended resets only interface effect/opacity/material visibility, retaining wallpaper and all other settings. Existing wallpaper restore retains its historical combined reset; clear keeps UI values. Live appearance uses one coalesced notification path; new value changes do not reload slider cells. Existing M2 busy/highlighted/disabled button appearance remains presentation-only.

Coverage limit: legacy system bars/toolbars/search-field and separate chip consumers are not fully converted. Runtime parity, exact screenshot matching, live slider smoothness, media lifecycle, translations, accessibility and restart persistence remain PENDING. M1 native build stays BLOCKED. No change to global navigation, game engine or gameplay preferences.


## M4 Home source implementation

A scrolling supplementary overview restores the reference's welcome → selected-instance/empty hero plus My Metallic → Your Instances hierarchy above existing configurable tiles. Existing HomeLogo becomes a small static branding mark; existing root pill/account panel remain. Primary hero has real profile/version/account data, canonical launch caption/state, choose/manage actions and discovery empty state. Status shows bundle version, configured Minecraft ID, explicitly labeled Java preference, and real JIT/download reports. Up to three saved-profile previews lead to actual selection; See All opens original Instances management. Missing metadata is not replaced by fake game data. Saved profiles do not establish installation/runtime compatibility.

M2 semantic fonts/colors/buttons and M3 panel surfaces/tint are reused. Wide/compact/accessibility text adaptation uses one self-sizing header and existing collection scrolling; no new controller or navigation store. Breakpoints/margins are implementation choices, not pixel-exact screenshot measurements. Neutral surfaces and single visible hero launch replace the central bobbing-logo presentation. The native launch title may differ from the reference's Play Now to preserve real precondition/error state.

Existing tile customization remains unchanged underneath. Overview hero/status are fixed context outside the saved tile editor; all saved tile visibility/order/size/title/icon/color/shortcut data remain intact, including the optional duplicate profile tile. Global tab order/AI migration and original account/JAR/version tool chrome are intentionally not redesigned here. Existing landscape masks remain unchanged; narrower-width layouts are implemented but portrait policy is not unlocked. Native screenshot fidelity and iPhone/iPad layout/interaction remain PENDING; M1 BLOCKED and M3 legacy coverage PARTIAL.


## M5 implemented Instances and navigation subset

Instances now presents a scrolling title/count/New Instance overview, quiet directory rail and adaptive saved-profile cards. Cards use existing M2 typography/semantic colors and M3 native managed surfaces, clear inner fills, restrained hairline/selected borders and a selected checkmark. Real profile name/version, loader icon, cached isolation and last-played metadata are retained; no installed-state, runtime or performance assertions. More is a real profile action sheet, with selection/edit/delete and original safeguards. Tapping a card retains the native select-then-edit flow. Directory/create/management and renderer/graphics options remain existing native functionality; zero profiles no longer hides directories.

Card layout uses available width: compact one column, wider two/three, accessibility one. The self-sizing overview and section headers scroll; no fixed header consumes the viewport at large text sizes. Font-derived row height, semantic colors, 44-point actions, VoiceOver selected/custom-action state and Reduce Motion feedback are implemented. These are implementation values, not measured screenshot dimensions; native self-sizing, truncation, accessibility and visual comparison remain PENDING.

Visible pill: **Home | Instances | Downloads | Appearance | Settings**. Stable internal slots remain Home=0, Downloads=1, AI=2, Instances=3, Settings=4. Header-only named routes translate visible destinations; selectedIndex remains internal for legacy callers. Compact/large-type pill uses symbols with full accessible labels, unchanged 60/76-point coupled geometry. Adjacent native Tools menu opens actual AI; AI highlights Tools instead of a wrong primary item. Real UIKit ownership, zero-duration tab animator, stacks, floating Done and Home reset remain intact.

Appearance temporarily opens the functional BackgroundSettings sheet over the current selected tab (retains that tab's highlight/return path). Wallpaper, native glass, UI Blur, Panel Opacity and scoped Reset to Recommended are real M3 controls. System/Light/Dark remains in original Settings. A complete reference-matched consolidated Appearance destination and global legacy-chrome coverage remain later work. No second store or placeholder destination.

No new M5 screenshot or native render was available. Appearance follows the established reference direction, with no claim of pixel-accurate Instances fidelity. M1 build BLOCKED; M3 and M4 remain PARTIAL, M5 runtime acceptance PENDING. Next: Downloads UI customization using existing download state/actions.

M5 public-selector review: both the Instances overview and existing Home global header now call `NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:elementKind:alignment:`. The Home change is exactly one factory-selector correction; native SDK/type checking remains BLOCKED.
