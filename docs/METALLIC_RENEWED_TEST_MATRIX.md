# Metallic Renewed test matrix

M0 evidence date: 2026-10-27. Read progress before testing. PASS means only the stated check actually ran. Runtime tests below are PENDING, not inferred from source wiring. No IPA build or physical-device validation occurred in this task. Do not alter protected code/configuration to make a test pass. Use disposable test data for downloads/worlds; preserve user accounts and game files.

## Executed M0 checks

| Feature | Test procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| Repository/branch | Inspect origin, branch and HEAD | Requested repository and UI source baseline | Correct repository; feat/renewed-uikit-home at fe379d4 | PASS | git remote get-url origin; git branch --show-current; git rev-parse HEAD |
| Protected baseline | Read remote refs, fetch baseline comparison ref, compute merge-base | Both branches start at required full SHA | Both refs and merge-base fe379d4f3723764ec0a8b6a6728368ac3492c4d8 | PASS | git ls-remote; git fetch; git merge-base |
| UI source/action map | Targeted inspection of listed UIKit files/helpers | Real selectors and keys recorded, unknowns explicit | Map in progress; header-only GlassSurface; intro/See All UNKNOWN | PASS | Targeted rg/sed inspection; source evidence only |
| Documentation/engine gate | Validate three-doc allowlist; compare baseline tree against index and working tree; whitespace check | Only docs change; engine/framework/startup/signing/build zero diff | Only the three requested documents differ; all other tracked content equals protected baseline; whitespace clean | PASS | Executed allowlist assertions, git diff --exit-code baseline with only three docs excluded, git diff --cached --check |

## Runtime and build acceptance

Historical user report of original IPA gameplay is recorded in progress; it is not a new execution result. For every pending test, capture device/model/OS, app/source/build identity, steps, screenshot/log evidence and actual result when performed.

| Feature | Test procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| Home navigation | Open Home from every tab, nested page and modal; tap Home again | Existing Home resets correctly, dismisses/pops once, remains tappable | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Instances navigation | Open Instances and return repeatedly | Existing version manager, selection and all management routes remain reachable | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Downloads navigation | Open Downloads; switch every category then return Home | Real catalogue opens with working categories, no overlap | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Appearance destination | Once implemented, open Appearance from compact/wide navigation | Existing theme/glass/wallpaper actions are reachable; no fake settings | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Settings and AI access | Open Settings, every section/advanced option and existing AI route | All existing functionality remains available after any tab rearrangement | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Touch delivery / callbacks | Tap each card/button/menu/sheet control, including beneath glass and after modal dismissal; trace existing targets | Exactly one existing callback; no invisible overlay or disabled-hit-test regression | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Rapid navigation | Alternate tabs rapidly, repeat selected-tab taps, push/pop and dismiss during switching | No ghost page, duplicate presentation, stuck transition or competing handler | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Profile selection | Choose another profile via picker and Instances; terminate/reopen | PLProfiles selected profile and Home status agree; selection persists | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Play Now | With known working profile/account, tap Home launch; repeat in blocked/download/JIT states | Original launch action/guards run once with real disabled/busy/error state; no engine bypass | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| JIT display and lifecycle | Open Home, visit other tabs, background/return and return from StikDebug | Existing status refresh resumes through lifecycle/state bridge; no endless cached checking or hardcoded readiness | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Protected advanced options | Inspect Universal Script JIT, Always Attached JIT and Bypass dyld library validation | Existing keys, values, enable conditions and availability unchanged; do not change settings merely to test visual controls | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| System/Light/Dark | Switch each mode in Settings/Appearance; change system theme in System mode; restart | Live materials/text/window style and saved selection agree without account reset | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Wallpaper image/video | Choose valid image and video using existing pickers, cancel, return from background | Real media shown; cancel safe; video resumes as before; no nil write | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Wallpaper clearing/missing file | Clear background, restart; separately test a missing saved file on a disposable device profile | Safe default/migration, no crash or persistent invalid path | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Wallpaper persistence | Select media, terminate/reopen, change orientation | Selection retained; sizing correct; no accidental reset | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Glass and migration | Test fresh/legacy defaults and native/liquid style on supported/older OS | Missing keys use baseline migration/defaults; true UIKit materials/fallbacks render; legitimate values retained | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| UI Blur | Move slider through minimum/middle/maximum, navigate and restart | Actual existing material intensity changes and persists; no misleading inert slider | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Panel opacity | Move opacity slider, navigate and restart with/without wallpaper | Actual panels respond with baseline semantics and persistence; no unintended wallpaper dimming coupling | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Recommended reset | After explicit UI-only semantics are implemented, change appearance then reset | Only approved UI appearance defaults restored; accounts/profiles/engine settings preserved | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Settings persistence | For each changed setting test off/on/zero where valid, save/pick, terminate/reopen | Existing key/scope used; genuine value restores, no duplicate conflicting key | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Keyboard/sheets/popovers | Focus search/text inputs, open sheets/action menus and dismiss on phone/tablet | Keyboard does not hide primary actions; popovers anchored; safe areas and focus correct | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| iPhone/iPad widths | Exercise Home and all destinations on compact iPhone and wide iPad, including split widths if supported | No clipping/overlap; navigation, cards and primary taps usable | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Orientation/safe areas | Rotate each supported orientation with nested page/sheet open | One consistent inset, no duplicated constraints, Home/nav geometry aligned | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Download filtering/actions | Search, filter/sort, select version/profile and invoke real download on test data | Existing callbacks/provider results and correct target profile used; no decorative action | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Download progress/errors | Observe real queued/active/completed/failed tasks; cancel/retry when supported | Catalogue/task centre/Home reflect real progress/errors; no simulated success | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Accessibility | VoiceOver, large Dynamic Type, contrast over wallpapers and Reduce Motion | Meaningful labels, readable focus order/contrast, comfortable taps and restrained motion | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Launch-intro / See All | After existing implementations are identified, exercise and restart applicable settings | Existing action and persistent state, no fabricated feature; currently mapping UNKNOWN | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| Baseline native build | On approved macOS/Xcode path build exact baseline without modifying protected inputs; capture logs/provenance | Reproducible command outcome and artifact identity; report blockers rather than change build/engine | Not run in M0 | PENDING | No runtime/build evidence captured in this task |
| JIT/Java/Metal/gameplay regression | On original or equivalent physical device use existing working StikDebug/Java 25/Metal configuration to launch Minecraft 26.2 and load singleplayer world | Same original launch flow and real gameplay; no claim based only on JIT label or source review | Not run in M0 | PENDING | No runtime/build evidence captured in this task |

## Release gate

A source map or engine-zero-diff check cannot prove engine reliability or source-to-binary reproducibility. Native build and physical gameplay remain separate gates. Investigate failures without editing protected implementation; document external/toolchain blockers. Add per-control cases as UI milestones introduce changes, and mark PASS only with actual evidence. Never replace a failed runtime test with a trivial static check.
