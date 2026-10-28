# Metallic Renewed — UI refinement tracker

Single source of truth for this eight-milestone refinement program. Read this first in future refinement sessions; earlier M0–M6 evidence remains in the three existing continuity documents. Do not repeat those audits. Only this document is changed in Milestone 01. No automatic commit, push or PR.

## Baseline and evidence

- Verified locally on 2026-10-28: clean initial working tree, HEAD `1ef8f21ffe7faff5e3d1ea42a50087d0bf088ec1`, detached (`git branch --show-current` empty). Latest commit: `docs: record master verification blocked gate`.
- Target: `feat/renewed-uikit-home`. User confirms actual remote feature branch matches this HEAD; remote state was NOT queried in this milestone. Older local branch pointer is `c7118550`; leave it alone. No checkout/reset/rebase/merge/branch deletion or force-push.
- Protected historical reference: `fe379d4f3723764ec0a8b6a6728368ac3492c4d8`, `baseline/alpha-1.2-fe379d4`. Refinement starting source is the detached HEAD above; cumulative earlier UI/compiler work must remain intact.
- Working-build provenance: **UNVERIFIED** for exact source-to-installed-binary identity. User reports Minecraft Java 26.2 reached its main menu on an A16 iPad/iPadOS 27.2. This is real-device user evidence, not an agent-executed regression test or proof of all controls/JIT paths.
- Existing progress, UI specification and test matrix are present; relevant M3–M6 implementation/acceptance sections reviewed. M1 full native validation remains BLOCKED in saved evidence; M3 legacy appearance coverage PARTIAL; M4–M6 visual/runtime acceptance remains pending. No Actions inspection or build here.

## Protected boundaries

ZERO engine or behavioral changes. Preserve JIT/pairing/activation, Java/JVM arguments and launch, Minecraft/bootstrap, Metal/Metallum/ANGLE/MobileGlues/shaders, authentication/sessions, downloads/installers/modloaders/version management, settings keys/defaults/serialization/persistence/effects, signing/entitlements/identifiers, dependencies/framework binaries/submodules, build configuration/scripts/workflows.

Mixed UIKit files can contain protected implementation: especially DownloadViewController.m, LauncherNewsViewController.m and LauncherPreferencesViewController.m. A filename is not permission to edit every method. Keep LauncherRightPanelViewController.m, JavaLauncher.m, utils.m implementation and backend stores untouched. Stop and report if a presentation fix depends on protected changes. No API/network-policy work, installs, builds or external workflows in this milestone.

## Approved requirements

| ID | Contract to retain throughout implementation |
| --- | --- |
| R01 | ONE shared small centered floating Liquid Glass toolbar; same five destinations/order/icons/design on every supported device; subtle selection, optical alignment, adjacent profile/avatar, safe areas and accessible hit targets. Never a giant full-width pill or a different iPhone navigation system. Retain original routing and AI access. |
| R02 | Home retains central Launch/Instance and Status cards and every launch/account/version/status action. Remove only the two marked unwanted lower visual sections after exact screenshot identification; retain underlying features and saved customization. Fix visible localization keys and refine spacing/type/materials. |
| R03 | Redesign Downloads presentation: investigate white label/overlay and header/avatar overlap; balance categories/search/filters/rows at compact and wide widths. Preserve all seven categories and real install/download/progress actions. Shared navigation remains R01. |
| R04 | Visually regroup ALL Settings options, including offscreen options, in readable restrained-width sections. Preserve every selector/control/binding/key/default/storage/action/enable condition. No replacement settings implementation or decorative dead controls. |
| R05 | Distinct Metallic identity, restrained native Liquid Glass, subtle depth/highlights, readable wallpaper contrast; avoid muddy overlays/excess blur. Smooth interruptible feedback, low rendering cost, Reduce Motion and accessibility. |
| R06 | Adaptive safe-area layouts, iPhone/iPad sizes, portrait/landscape and resizable windows where supported, live size changes and Dynamic Type. No clipping, lost actions or broken scroll. Aim for 44×44-point hit regions even with compact visible icons. Existing orientation policy is a recorded dependency, not permission to change it. |

## Actual UI ownership and preservation map

All paths below are relative to `ios-app/Natives/` unless specified. These are source-level findings, not runtime PASS claims.

| Area | Actual owners | Binding / boundary to preserve |
| --- | --- | --- |
| Shared navigation | HomeTopNavView.h/.m; AmeRootTabController.m | `onSelect`, `AMEPrimaryDestination`, `AMETabForPrimaryDestination`, root `setSelectedIndex:`. Visible Home/Instances/Downloads/Appearance/Settings maps to internal 0/3/1/sheet/4. Internal AI=2 remains Tools → AI. Keep stacks, containment, instant transitions, floating Done and own-exit semantics. |
| Profile/account chrome | LauncherNewsViewController.m; HomeActionPanelView.m | Existing Home avatar/account presentation and `showAccountManagerModal`; overview action 3 forwards there. Root currently owns topNav + Tools, not a verified universal avatar owner. Shared adjacent avatar must forward the established account route without moving auth ownership; exact cross-page binding needs Milestone 02 review. |
| Home | LauncherNewsViewController.m; HomeCustomizeViewController.m | Overview `renewedOverviewAction:`: 0 launch, 1 choose version, 2 Downloads via `fix2PushTab`, 3 account, 4 version/Instances shortcut, 5 task center. Keep HomeTileConfig, `ameHomeCardLayout`, saved ordering/visibility/sizes, long-press/drag/resize/save/Done. |
| Launch/status | LauncherNewsViewController.m, existing contained LauncherRightPanelViewController | `norightLaunchTapped` guards canonical `launchButton.enabled`, editing, target and dispatch-pending state, then sends ONE native touch-up action. Never force enabled or bypass launch gating. Keep `AmeRightPanelStateNotification` / request-state bridge, profile/account notifications and lifecycle. No new JIT predicate. |
| Instances/profile routes | VersionManagerViewController.m; existing ProfileSettingsViewController | `PLProfiles.current.selectedProfileName`, native persistence/SelectedProfileChanged; `editProfile:` selects intended profile before push. Keep deletion/directory safeguards and async size cache. These functions are protected from behavioral redesign. |
| Downloads | DownloadViewController.m: `ModernAssetCell`, sidebar/search/category/list UI; DownloadTasksViewController.m | Seven native indices: 0 Versions, 1 Mods, 2 Shaders, 3 Resource Packs, 4 Data Packs, 5 Modpacks, 6 Worlds; displayed rail order 0/1/2/5/3/4/6. Retain `switchToTab:animated:`, search delegates, `versionFilterChanged:`/`applyVersionFilter`, `showFilterOptions`, `showGameVersionPicker`, `showModLoaderPicker`, `showSortOptions`, `resetFilters`, provider callbacks, original row/button handlers and `openImportModpackView`. |
| Download safety | Same controller + existing DownloadTaskManager/DownloadTaskItem | Keep one-time `targetProfileName` snapshot/explicit target, original paths/provider restrictions, task/KVO/progress lifecycle, reuse icon cancellation and stale target removal. Sidebar must exist before search constraints; initial `switchToTab:initialTab animated:NO`. No installer/JIT method changes. Historical M6 matrix records 140 protected bodies unchanged; not re-executed here. |
| Settings definitions | LauncherPreferencesViewController.h/.m | Subclass of `PLPrefTableViewController`. Keep complete section/item definitions, custom actions, warning/enable conditions, `getPreference`/`setPreference` blocks. General route composes section.key and calls `getPrefObject`/`setPrefObject`; backend/defaults remain protected. |
| Settings control binding | PLPrefTableViewController.h/.m; PLPreferences.h/.m (backend read-only) | Native `sliderMoved:`, `switchChanged:`, text and picker callbacks invoke the supplied blocks. Preserve item identity if presentation grouping changes; row-index remapping is CAUTION. Special stores: launcher language routes to language screen/NSUserDefaults, AI to AiSettings, glass to existing style/manager APIs. Never consolidate stores or change notifications. |
| Appearance/glass | BackgroundSettingsViewController.m; BackgroundManager.h/.m; AMEGlassStyle.h; UIKit+GlassSurface.h; BottomActionBarView.m | Existing opacity/interface blur/wallpaper blur/dimming/style/highlight callbacks call current manager/setters and notification paths. Preserve NSUserDefaults appearance values, explicit zero handling, reset scope, material fallback, wallpaper/video lifecycle. UI blur, panel tint, wallpaper blur and dimming remain distinct; no new appearance preferences. System/Light/Dark remains in Settings; Appearance currently opens Background Settings sheet. |
| Localization | utils.h/.m `localize`; LauncherLanguageViewController; bundle language resources | Inspected resolver: effective language → English → UIKit → key. `comment` is not used as fallback text, so `localize(key, EnglishText)` does not guarantee English fallback. Resolver is in protected mixed utils.m: do not change it. No Localizable.strings/.lproj translation files were found in this local ios-app tree during targeted inspection; expected resource lookup uses bundle `<code>.lproj`. Exact translation source/provenance is UNVERIFIED. Prefer approved UI/resource-only fixes after ownership is established; do not invent a path or silently replace localization behavior. |

## Bug / dependency register

| ID | Finding | Evidence / next decision |
| --- | --- | --- |
| B01 | Oversized/navigation composition and avatar overlap | Root currently stretches topNav between safe leading and Tools trailing constraints; Home has separate account chrome. R01 needs coordinated UI-only geometry and account route review, not a second root. Current coupled bar/reservation = 60/76 points. |
| B02 | Two unwanted Home lower sections | User request retained; precise marked screenshot/section identities UNVERIFIED. Do not guess which configurable features to hide or alter saved visibility values. |
| B03 | Visible untranslated keys | User-reported; key-return fallback source-confirmed. Exact offending strings/locale and available translations need screenshot identification; no global resolver edits. |
| B04 | Downloads white floating label/overlay | User-reported; root cause UNVERIFIED. Inspect screenshot, then smallest owning label/background/popover/material subtree. No speculative overlay removal. |
| B05 | Cramped Downloads / overlap / large Settings presentation | User-reported design targets; adaptive constraints/control grouping need targeted later review and device validation. Task-center visual gap and legacy appearance consumers remain open. |
| B06 | Portrait requirement conflicts with current landscape policy | Root, Home and Downloads `supportedInterfaceOrientations` explicitly return landscape. Do not change masks, Info.plist or runtime/game orientation behavior under layout-only scope. Report dependency and obtain explicit scope decision before enabling portrait. Supported-width layout work can proceed separately. |
| B07 | Exact binary/source provenance and native validation | User's working main-menu evidence preserved; no exact-source IPA/native execution verified here. Do not call static checks physical validation. |

## Risk classification for later work

- **SAFE:** colors/type/spacing, restrained card materials using existing helpers, content max-width, label wrapping, accessibility names/traits and constraints within existing presentation ownership. Still require visual/interaction checks.
- **CAUTION:** shared nav/profile placement, coordinated 60/76 reservation changes, category/row/control regrouping, Home visual-section removal, localization display fixes, reuse and hit-area adjustments. Retain all native handlers/targets/stores, route identities, saved layouts, lifecycle and selector behavior. Approval for each implementation milestone required.
- **BLOCKED:** any requested fix requiring engine/auth/install/storage/default/signing/build/dependency changes; modifying global localization implementation inside protected utils.m; enabling portrait through orientation-policy changes without explicit scope approval. Escalate exact dependency rather than widen scope.

## Eight-milestone roadmap

| Milestone | Status | Evidence / handoff |
| --- | --- | --- |
| 01 — Baseline protection, UI mapping and progress tracking. | DONE | Read-only baseline/UI binding inspection; only this tracker added; final source/HEAD/whitespace checks recorded below. |
| 02 — Shared compact navigation and adjacent profile control. | DONE | Source implementation and local checks complete; native/device acceptance PENDING. See Milestone 02 record below. |
| 03 — Home layout redesign and action preservation. | TODO | Needs exact marked lower-section identities; no destructive layout preference changes. |
| 04 — Downloads adaptive redesign and white-overlay investigation. | TODO | Diagnose actual white overlay first; protect mixed-file installer bodies. |
| 05 — Complete Settings presentation redesign and binding preservation. | TODO | Inventory every existing option/control binding before visual grouping; keep all offscreen options. |
| 06 — Interaction, navigation and settings persistence integrity checks. | TODO | Trace retained callbacks; device persistence checks remain pending until executed. |
| 07 — Localization, Liquid Glass refinement and responsive layout validation. | TODO | Resolve locale/resource ownership and portrait scope; compare actual renders. |
| 08 — Final source audit, native build verification and real-device regression testing. | TODO | Separate approved build task/toolchain prerequisites and physical test evidence required. No build authorization inferred from this roadmap. |

## Milestone 01 validation and exact continuation

- Executed: `git status --short`, `git rev-parse HEAD`, `git branch --show-current`, `git log -1 --oneline`, `git diff --check`; initial tree clean/detached as above. Read existing relevant continuity sections and inspected actual route/control/fallback symbols. No full audit, API call, dependency install, build, workflow dispatch or device test.
- Final validation: HEAD/local branch unchanged; no tracked diff, application/protected/settings/build files unchanged. Only this new tracker exists. Repository ignore rules ignore docs, so normal `git status --short` is empty; `git status --short --ignored -- docs/METALLIC_RENEWED_UI_REFINEMENT_TRACKER.md` shows `!! docs/METALLIC_RENEWED_UI_REFINEMENT_TRACKER.md`. Tracker remains unstaged for review; no ignore rule changed. Whitespace checked separately for the ignored new file.
- Milestone 01 completed preparation without source edits. Milestone 02 subsequently authorized and implemented as recorded below.
- Exact next milestone: **02 — Shared compact navigation and adjacent profile control.** Wait for explicit authorization. Read this tracker, inspect only HomeTopNavView/AmeRootTabController/Home account presentation and dependent 60/76 reservations, propose/implement only approved presentation changes while retaining routes. No checkout/reset of the stale local branch. Portrait-policy and screenshot identity dependencies remain open; do not infer permission to change behavior.
- At every later milestone append concise changed paths, actual checks, unresolved bugs and next action here. Mark DONE only with evidence; physical tests stay PENDING until performed. Do not erase prior milestones or duplicate broad audits.


## Milestone 02 — implementation record (2026-10-28)

Status: **DONE for source implementation/local checks; native and device acceptance PENDING.** No Milestone 03 work performed. Starting HEAD unchanged at `1ef8f21ffe7faff5e3d1ea42a50087d0bf088ec1`.

Changed paths (only these six UI files and this tracker):

- `ios-app/Natives/HomeTopNavView.m`: one icon-only 228×52-point intrinsic capsule, five nonoverlapping 44×44 targets, consistent 20-point medium SF Symbols. Quiet UIView selection fill instead of a second material layer; existing glass resolver/appearance manager and selected-index mapping retained. Selection remains visible at UI Blur zero. Increased-contrast notification added to existing refresh loop; Reduce Motion selection behavior preserved. Accessible names use local English fallback when localization returns a raw key; no global resolver change.
- `ios-app/Natives/AmeRootTabController.h/.m`: compact centered layout group inside unchanged 60/76-point reservation; layout-guide slot aligns the actual existing profile panel. Panel is adopted once into root presentation ownership, remains owned/data-updated by Home and does not change controller containment. Existing menus/routes reused; the separate ellipsis button is replaced by profile long-press → Tools → AI and a VoiceOver “Tools: AI” custom action. Actual AI selection updates menu check state; no false primary highlight. No extra controller, tab or profile database.
- `ios-app/Natives/LauncherNewsViewController.m`: import and one `viewWillAppear` adoption call; existing standalone panel placement remains fallback. Guard Home-only bring-to-front after reparenting. Other methods (including launch, account, state, customization and persistence) byte-identical to starting HEAD.
- `ios-app/Natives/HomeActionPanelView.h/.m`: small presentation-only `onWillExpand` hook ensures existing Home owner is visible before opening controls from another tab. Retains original avatar → `toggleTapped` → `setExpanded:` and name/login → original callbacks → `showAccountManagerModal`. Home reset is used only when returning from another tab/nested Home stack. Actual avatar/fallback, expansion/status chips and updates remain the original panel. Phone avatar hit area raised from 38 to 44 points; VoiceOver activation uses existing expansion API; tap respects Reduce Motion. No account/auth implementation change. These additions are required for shared ownership/accessibility, not a Home redesign.

Preserved five destinations: Home=internal0, Instances=3, Downloads=1, Appearance=existing BackgroundSettings sheet, Settings=4. Internal AI=2 remains reachable through the Tools context menu/custom action. Mapping header, root controller factory, Home reset, floating Done, instant tab animator and orientation methods remain byte-identical. Appearance retains existing sheet/close/underlying-tab selection semantics; no independent shared-header copy added inside the sheet. Pixel fidelity and sheet-header visibility still need device review.

Geometry: 228-point capsule + 8-point gap + existing collapsed profile (46 phone / 56 pad) = 282/292 points, centered with ≥8-point safe-edge margins. Minimum safe width is therefore 298/308 points. Arithmetic checked at 320, 375 and wide layouts; no shrinking of touch regions. Exceptionally narrow safe widths below those minima cannot satisfy all controls/margins and remain an explicit constraint requiring a future scope decision; no hidden destination or alternate phone design added. Existing portrait restrictions unchanged; no portrait runtime-support claim. Current panel expansion sizing and localized/large-type expanded-panel layout are preserved, not redesigned, and require device testing.

Executed checks:

- `git diff --check` PASS; parser grammar/import/duplicate-method checks PASS for four .m and two .h files. Parser-only NS_ENUM, NS_ASSUME_NONNULL and nullability macro normalization used; not Apple SDK type-checking.
- Source comparison against starting HEAD: exact mapping header/factory/reset/Done/orientation/animator unchanged. All Home methods except two lifecycle presentation integrations unchanged. Existing avatar tap target, panel callbacks and account/launch methods retained. No new target/action added to five navigation controls; one context-menu interaction attached only during first panel adoption, no new observer registrations in root/Home.
- Changed-path allowlist PASS: only six UI files above, plus tracker. No settings key/default/storage/binding/backend, engine, installer, authentication, signing, dependency, workflow or orientation-policy modification.
- Header allocations are setup-only; no material creation in layout/scroll. Selector frame moves only for selection/size changes. Profile reparenting guarded against repeats. No network calls, builds or external workflows executed.
- Native Xcode/SDK compilation NOT RUN (Linux environment). Device tap/VoiceOver/large text/theme/wallpaper/blur/opacity/profile expansion/AI/sheet/rapid-navigation tests PENDING. Runtime containment/lifecycle correctness and screenshot fidelity are source-reviewed, not physically verified.

Tracker preservation: `.gitignore:17:/docs` ignores this file. Only this exact tracker is force-added to the index for review; application changes remain unstaged. No .gitignore changes, commit, push or PR. Staging does **not** preserve anything in remote history.

Last completed milestone: **02 source implementation**. Exact next milestone: **03 — Home layout redesign and action preservation**, only after explicit authorization and identification of the two marked lower sections. Before visual acceptance, compile these UI changes with the native SDK and test the shared header at narrow/wide widths, context menu/VoiceOver AI access, profile expansion from each tab, account return, safe areas, themes/material settings and rapid navigation. Resolve any header regression before broadening the UI work. Portrait-policy change still requires separate approval. Previous Milestone 01 handoff is historical; this paragraph is the current handoff.

M03 preflight checkpoint review: corrected an accidental comma expression in M02's HomeTopNavView content-size notification condition before committing. The observer list still includes Increase Contrast; only content-size changes refresh the hidden navigation label fonts. Six-file M02 scope retained. Local checkpoint authorized by M03; no remote publication.
