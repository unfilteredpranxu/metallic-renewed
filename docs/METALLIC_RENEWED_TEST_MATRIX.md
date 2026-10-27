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
| Home navigation | Open Home from every tab, nested page and modal; tap Home again | Existing Home resets correctly, dismisses/pops once, remains tappable | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Instances navigation | Open Instances and return repeatedly | Existing version manager, selection and all management routes remain reachable | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Downloads navigation | Open Downloads; switch every category then return Home | Real catalogue opens with working categories, no overlap | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Appearance destination | Once implemented, open Appearance from compact/wide navigation | Existing theme/glass/wallpaper actions are reachable; no fake settings | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Settings and AI access | Open Settings, every section/advanced option and existing AI route | All existing functionality remains available after any tab rearrangement | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Touch delivery / callbacks | Tap each card/button/menu/sheet control, including beneath glass and after modal dismissal; trace existing targets | Exactly one existing callback; no invisible overlay or disabled-hit-test regression | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Rapid navigation | Alternate tabs rapidly, repeat selected-tab taps, push/pop and dismiss during switching | No ghost page, duplicate presentation, stuck transition or competing handler | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Profile selection | Choose another profile via picker and Instances; terminate/reopen | PLProfiles selected profile and Home status agree; selection persists | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Play Now | With known working profile/account, tap Home launch; repeat in blocked/download/JIT states | Original launch action/guards run once with real disabled/busy/error state; no engine bypass | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| JIT display and lifecycle | Open Home, visit other tabs, background/return and return from StikDebug | Existing status refresh resumes through lifecycle/state bridge; no endless cached checking or hardcoded readiness | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Protected advanced options | Inspect Universal Script JIT, Always Attached JIT and Bypass dyld library validation | Existing keys, values, enable conditions and availability unchanged; do not change settings merely to test visual controls | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| System/Light/Dark | Switch each mode in Settings/Appearance; change system theme in System mode; restart | Live materials/text/window style and saved selection agree without account reset | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Wallpaper image/video | Choose valid image and video using existing pickers, cancel, return from background | Real media shown; cancel safe; video resumes as before; no nil write | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Wallpaper clearing/missing file | Clear background, restart; separately test a missing saved file on a disposable device profile | Safe default/migration, no crash or persistent invalid path | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Wallpaper persistence | Select media, terminate/reopen, change orientation | Selection retained; sizing correct; no accidental reset | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Glass and migration | Test fresh/legacy defaults and native/liquid style on supported/older OS | Missing keys use baseline migration/defaults; true UIKit materials/fallbacks render; legitimate values retained | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| UI Blur | Move slider through minimum/middle/maximum, navigate and restart | Actual existing material intensity changes and persists; no misleading inert slider | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Panel opacity | Move opacity slider, navigate and restart with/without wallpaper | Actual panels respond with baseline semantics and persistence; no unintended wallpaper dimming coupling | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Recommended reset | After explicit UI-only semantics are implemented, change appearance then reset | Only approved UI appearance defaults restored; accounts/profiles/engine settings preserved | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Settings persistence | For each changed setting test off/on/zero where valid, save/pick, terminate/reopen | Existing key/scope used; genuine value restores, no duplicate conflicting key | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Keyboard/sheets/popovers | Focus search/text inputs, open sheets/action menus and dismiss on phone/tablet | Keyboard does not hide primary actions; popovers anchored; safe areas and focus correct | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| iPhone/iPad widths | Exercise Home and all destinations on compact iPhone and wide iPad, including split widths if supported | No clipping/overlap; navigation, cards and primary taps usable | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Orientation/safe areas | Rotate each supported orientation with nested page/sheet open | One consistent inset, no duplicated constraints, Home/nav geometry aligned | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Download filtering/actions | Search, filter/sort, select version/profile and invoke real download on test data | Existing callbacks/provider results and correct target profile used; no decorative action | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Download progress/errors | Observe real queued/active/completed/failed tasks; cancel/retry when supported | Catalogue/task centre/Home reflect real progress/errors; no simulated success | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Accessibility | VoiceOver, large Dynamic Type, contrast over wallpapers and Reduce Motion | Meaningful labels, readable focus order/contrast, comfortable taps and restrained motion | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Launch-intro / See All | After existing implementations are identified, exercise and restart applicable settings | Existing action and persistent state, no fabricated feature; currently mapping UNKNOWN | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| Baseline native build | On approved macOS/Xcode path build exact baseline without modifying protected inputs; capture logs/provenance | Reproducible command outcome and artifact identity; report blockers rather than change build/engine | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |
| JIT/Java/Metal/gameplay regression | On original or equivalent physical device use existing working StikDebug/Java 25/Metal configuration to launch Minecraft 26.2 and load singleplayer world | Same original launch flow and real gameplay; no claim based only on JIT label or source review | Not run in M0 or M1 | PENDING | No runtime/build evidence captured in these tasks |

## Release gate

A source map or engine-zero-diff check cannot prove engine reliability or source-to-binary reproducibility. Native build and physical gameplay remain separate gates. Investigate failures without editing protected implementation; document external/toolchain blockers. Add per-control cases as UI milestones introduce changes, and mark PASS only with actual evidence. Never replace a failed runtime test with a trivial static check.


## M1 verification evidence (2026-10-27)

Source: `feat/renewed-uikit-home` at `26d114919d7ab8f7426352598783f2e82d36a232`; protected baseline `fe379d4f3723764ec0a8b6a6728368ac3492c4d8`. M1 overall **BLOCKED**. No workflow dispatched or native build attempted; therefore no compiler failure, run URL or IPA artifact URL. Existing source equality is not runtime compatibility.

| Feature | Test procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| Repository/ref continuity | Read progress/spec/matrix; inspect origin, branch, HEAD, remote feature/baseline refs | Correct source lineage, preserve M0 | Correct repository and refs; clean before docs edits | PASS | git remote get-url origin; branch --show-current; rev-parse HEAD; ls-remote |
| Protected engine/source equality | Compare baseline to HEAD/index/working tree excluding only approved docs | No JIT/Java/Metal/framework/launch/signing/settings/UI/build changes | Non-document diff zero before verification; repeated before commits | PASS | git diff --exit-code origin/baseline/alpha-1.2-fe379d4 HEAD -- . ':(exclude)docs'; final doc allowlist gate |
| Suitable native macOS workflow | Read build.yml and immediate make dependencies; check no unapproved substitutions/patches | Full native IPA from approved unchanged inputs | Manual macOS workflow exists but copies moving upstream source and patches runner UI/build inputs; Makefile also replaces vendored renderer sources | FAIL | build.yml:31–87, 97–106, 115–191; Makefile dep_mg/payload. Suitability failure, not executed build failure |
| Alternative workflows | Inspect report workflow and Codemagic entry | Suitable unchanged-source native alternative | Report workflow builds nothing; Codemagic substitutes/patches source and can change renderer binaries | FAIL | what-was-done.yml; codemagic.yaml:48–96,139–213; neither executed |
| Apple toolchain availability | uname; command lookup for xcodebuild/xcrun/codesign/ldid | macOS + Xcode and Apple SDK tooling | Linux; all four commands unavailable | FAIL | Local command checks; no attached macOS executor |
| Native prerequisite completeness | Check directly referenced framework/source/resource paths | Required files available without substitutions | Only two resource dylibs; missing linked frameworks, ZeroTier binary, ControllerInput.m and compiled LaunchScreen resource | FAIL | Exact path inventory recorded in progress; CMake ZeroTier fatal condition not executed |
| NG-GL4ES pinned checkout | Inspect gitlink/.gitmodules/status and local CMakeLists | Initialized dependency | Pin 6e153a1622a8d9ef903f7975aafbef2453571bab uninitialized; no local CMakeLists | FAIL | git submodule status; path check |
| NG-GL4ES remote resolvability | Fetch pinned dependency on an approved build route | Exact pinned object retrievable | Not tested; no other repository accessed | PENDING | Target-only scope retained; not a network/access-denial diagnosis |
| LFS current index | Read LFS rules, version, indexed files and tracked tgz paths | Indexed payload state established | LFS 3.6.1; no LFS entries or tracked tgz files at inspected revision | PASS | git lfs version; git lfs ls-files; git ls-files -- '*.tgz'; no claim of dependency completeness |
| LFS remote availability | Resolve required remote assets if any on approved route | Downloads verified when required | Not exercised; empty current indexed list | PENDING | No LFS transfer performed |
| Java 25/runtime payload | Check local runtimes and parent jre/payload rules | Required runtime available in full app | JRE 8/17/21/25 absent locally; make has download/copy rules; none executed | FAIL | depends paths absent; Makefile:456–481,1135; final runtime compatibility PENDING |
| JIT script packaging | Check root templates, native resources and explicit copy rules | Required scripts included in app bundle | Three root templates present; absent in native resources; inclusion not established by inspected build rules | PENDING | build.yml, codemagic.yaml, Makefile contain no template/script copy rule; no IPA to inspect |
| Full IPA, Metal/runtime contents | Run one approved full build; inspect archive and Mach-O/dependency contents | Genuine Minecraft-capable native package | Not run due suitability/toolchain blockers; no artifact | PENDING | Native build intentionally not attempted on Linux or via disqualified workflows |
| Signing/entitlements | Check produced app and all embedded binaries with Apple tooling | Correct signatures and expected entitlements | Baseline files unchanged; no produced app; existing ldid framework loop suppresses errors | PENDING | Makefile payload/package/codesign inspected only; no assertion of embedded signature validity |
| Diagnostics/artifact availability | Inspect existing upload/log rules then retrieve current-run outputs | IPA and useful diagnostics tied to source/run | Build log and error annotation rules exist; success-only metallic-ipa upload, no build.log/dSYM artifact upload; no M1 run | PENDING | build.yml:193–245; Makefile dsym; artifact URL none |
| New IPA known configuration/gameplay | On device use Minecraft 26.2 + Java 25 + StikDebug + original JIT/dyld/Metallum configuration | Same launch flow and working singleplayer world | Not performed; historical original-IPA success remains user evidence only | PENDING | No new build or physical-device session |

Next milestone: Unified UIKit design foundation. Preserve these open native build/device gates and the M0 regression matrix; do not convert pending runtime outcomes to PASS based on source inspection.


## M2 shared UIKit foundation evidence (2026-10-27)

Source start: feature branch at `a08a458a78e908bb993b7f7edc84359295c740fc`. All previous runtime tests remain PENDING; M1 remains BLOCKED. No native build or device/visual test was performed for M2.

| Feature | Test procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| Screenshot availability | Review attached Home/Appearance/Downloads/Settings captures | Existing visual authority used, no invented screen concept | Quiet native materials/typography/pills inform the shared foundation; no screen redesign | PASS | M2 attachments reviewed; visual implementation matching remains untested |
| Objective-C grammar | Parse both changed .m files; normalize enum/export/nullability macros for changed headers and parse baseline/current | No grammar errors in scoped source | Zero direct .m errors; zero normalized-header errors | PASS | tree-sitter + tree-sitter-objc in /tmp/metallic-m2-parser; not Apple SDK compilation/type checking |
| Imports and build inclusion | Resolve quoted imports; check existing CMake entries | No missing local header or new registration needed | Four existing UI files only; both .m files already listed | PASS | Local path assertions and CMakeLists.txt inspection; build config unchanged |
| Actions/geometry preservation | Compare callbacks, target/event, nav constants/anchors and bottom anchors/titles with pre-M2 HEAD | Functional wiring and coupled layout remain unchanged | tapped:/tabNote: and event line unchanged; 60-point constants/anchors unchanged, 76 reservations in untouched controllers, 36 bottom height unchanged | PASS | Source comparison assertions; no tap or rotation execution |
| Accent/preferences protection | Compare accent adapter and appearance key strings; inspect manager/style/scene files | No changed defaults, new keys or duplicate theme store | Adapter/key sets unchanged; BackgroundManager, AMEGlassStyle and SceneDelegate byte-identical | PASS | Diff/key assertions against baseline; runtime persistence still pending |
| Engine/protected boundary | Diff baseline allowing only four specified UI files and three docs | No engine/framework/JIT/Java/Metal/launch/auth/signing/build changes | All other tracked content identical | PASS | Exact path allowlist, baseline diff and precommit gates |
| Source quality/hit testing | Review full diff, observer ownership, material hierarchy and layout paths; whitespace check | Presentation-only changes, decorative descendants noninteractive; no repeated constraints/material allocation in layout | Construction guarded; observers cleaned up; no new targets/gestures; existing constraints retained; whitespace clean | PASS | Full diff review and git diff --check; runtime hit testing not performed |
| Light/Dark/System surfaces | Switch modes, system appearance and accent while components are onscreen | Semantic text/border and selected state update without account/game changes | Not run | PENDING | Native build unavailable; UIThemeChanged/traits wiring inspected only |
| Button roles/states | Exercise primary/secondary/subtle/navigation/destructive, enabled/disabled/selected/highlighted/busy combinations using existing callers or native test harness | Clear states, single original callback; busy owner retains enable guards; title/icon restored | Not run; only primary/secondary adopted by existing callers | PENDING | No UIKit runtime; busy API presentation only |
| Material/preferences switching | Toggle existing native/liquid/hand-drawn settings, navigate, rotate and restart | Correct real material/fallback, no invisible or inert glass, no duplicate layers or preference reset | Not run | PENDING | Existing resolver/migrations retained; no native runtime |
| Reduce Motion/VoiceOver | Enable Reduce Motion, switch destinations rapidly, inspect selected traits and accessibility focus | No stretch animation/ghost pages; selected state announced once; buttons remain tappable | Not run | PENDING | Source paths implemented; tab transitions untouched |
| Type/size/contrast | Test small iPhone, iPad, all supported orientations and large/accessibility text on bright/dark wallpapers | No overlap/clipping, legible enabled/disabled states, safe areas preserved | Not run; nav cap and legacy compact heights need review | PENDING | Reference review is not a rendered-app test |
| Persistence/lifecycle/gameplay | Repeat M0/M1 restart, background, JIT/Java/Metal/Minecraft device matrix using new IPA | Same functionality and engine behavior | No IPA built; no new gameplay/restart evidence | PENDING | M1 BLOCKED; historical original IPA evidence unchanged |

Next: Wallpaper, Glass, Blur and Opacity integration. Maintain existing runtime gates and record exact source/build/device identity when execution becomes available.


## M3 source / logic verification (2026-10-27)

Start: `0940a6d9d9824c10ee5eaad0e07267a7ccea48fc`, feature branch. M3 PARTIAL; M1 native build BLOCKED. Source equality/logic checks are separate from runtime acceptance.

| Feature | Procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| Objective-C syntax grammar / imports | Parse four changed implementations and normalized manager header, resolve local imports / existing CMake registrations | No grammar errors, no new source registration | Checks passed | PASS | tree-sitter grammar parsing via /tmp/m3_verify.py; not Apple SDK compilation |
| Numeric boundaries | Compile and execute production AMEClampAppearance C body with GCC | Preserve valid zero, clamp ranges, reject non-finite values | Nine assertions passed | PASS | /tmp/m3_clamp.c binary: zero, min, negative, above-max, in-range, max, NaN, ±infinity |
| Control/render/reset paths | Trace four slider selectors to property/save/decoration; assert reset assignments | Distinct model/render responsibilities; reset limited to three UI values | Source assertions passed | PASS | /tmp/m3_verify.py; not UIKit event execution |
| Preferences / migration | Compare old constants, new keys, objectForKey presence guards and save calls | Old keys unchanged, two unique keys, explicit zero kept | Source checks passed | PASS | Manager constants/load/save; NSUserDefaults runtime still pending |
| Refresh / wiring / M2 preservation | Inspect construction-only targets, tracking checks, observer cleanup, coalesced sender, M2 action/animation/accent bodies | No added action forwarding or gesture/constraint/material accumulation | Source checks passed | PASS | Grammar/source review; manager sends appearance notification at one site |
| Protected engine boundary | Compare baseline allowing only approved M2/M3 UI files and three docs | No engine/framework/JIT/Java/Metal/launch/auth/signing/build changes | All other tracked paths identical | PASS | Exact path gate; source equality only |

## M3 native acceptance (not executed)

| Feature | Procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| Default wallpaper | Open/reopen, rotate phone/tablet | Established default aspect-fill, no blank flash or repeated setup | Not run | PENDING | Default rendering preserved; native build unavailable |
| Custom image | Pick/crop image from Photos and Files, then reopen | Wallpaper/preview update; same storage folder and crop, cached without repeated reads | Not run | PENDING | Async/cache source path implemented only |
| Custom video | Pick supported video, navigate, background/foreground | Aspect-fill playback, one player, original lifecycle retained | Not run | PENDING | Same-host reuse and original player/lifecycle methods; no AVPlayer runtime |
| Picker cancellation / file error | Cancel both pickers; choose inaccessible/invalid media | Old state/files retained, no crash; useful error | Not run | PENDING | Cancellation delegates unchanged; copy-before-replace and Files error source checks only |
| Missing wallpaper | Restart with missing/invalid path and corrupt image | Safe default, nil-safe persistence, no blank or unrelated deletion | Not run | PENDING | Path validation, async fallback and removeObjectForKey inspected |
| Clear wallpaper | Confirm clear, then pick another wallpaper | Immediate default, host retained, UI/engine values unchanged | Not run | PENDING | Manager clear path implemented; UI confirmation not executed |
| Light theme | Existing Light switch, bright/dark wallpapers | Readable semantic panels; gentler dimming, no opaque page overlay | Not run | PENDING | Semantic material/tint source only |
| Dark theme | Existing Dark switch, bright/dark wallpapers | Readable native glass; dimming is black, not white | Not run | PENDING | Dynamic color source only |
| Liquid Glass | Supported OS, style auto/liquid and highlights toggle | Native effect and existing optional highlights function | Not run | PENDING | Capability resolver preserved; no new private tuning |
| Native fallback | Older OS / native choice | Valid UIKit blur; no forced unavailable APIs | Not run | PENDING | Resolver unchanged, no native execution |
| UI Blur | Drag 0/mid/100 in Blur mode, reopen | Material visibility changes on managed panels/cells and M2 controls; tint/text retained at zero | Not run | PENDING | Independent new key and rendering helper inspected |
| Panel Opacity | Drag 10/mid/100 in both modes | Backdrop tint changes, no text fade or wallpaper dimming | Not run | PENDING | Separate host tint path inspected; no rendered comparison |
| Wallpaper dimming independence | Change each wallpaper/UI slider separately, switch glass style | Only intended wallpaper/material/tint/overlay changes | Not run | PENDING | Source paths split; legacy bars/chip coverage incomplete |
| Reset to Recommended | Change UI/wallpaper/game settings, confirm reset | Only Blur mode + opacity .7 + interface material .79 reset | Not run | PENDING | Three backing assignments verified; runtime settings not observed |
| Legacy wallpaper restore | Confirm original Restore Default Background | Original clear + UI effect/opacity reset retained; no new UI intensity reset | Not run | PENDING | Compatibility source path documented |
| Persistence | Change all four sliders, explicit zero, terminate/reopen; test legacy defaults migration | Values, image/video selection and shared screens restore correctly | Not run | PENDING | Save/load source checked; real process restart not performed |
| Rapid slider movement | Drag quickly, switch direction, leave/reenter, change style | Responsive thumb, no cell replacement, targets/layers do not accumulate | Not run | PENDING | Tracking guards/coalescing/reuse inspected; performance not measured |
| Multiple navigation changes | Rapid tabs/modals/rotation while media and sliders active | No duplicate overlay/player, blocked control, page overlap or lost JIT refresh | Not run | PENDING | Root/tab lifecycle not edited; UIKit runtime unavailable |
| Global consumer coverage | Compare manager surfaces, M2 controls, legacy bars/toolbars/search/chips | Consistent complete interface behavior | Legacy consumers not fully converted | PENDING | Explicit partial scope, no global parity claim |
| JIT / Java / Metal / gameplay | Build safely, validate historical known configuration on device | Same engine and working Minecraft world | New runtime test not performed; protected source diff zero | PENDING | M1 BLOCKED; original IPA user evidence remains historical |

Next milestone: Polished and fully functional Home screen. Keep every unexecuted acceptance test pending and carry forward legacy-consumer coverage and M1 blockers.


## M4 source verification (2026-10-27)

Start: `6d260fb2a11293306d7e0b3543653cc3759152c3`; branch `feat/renewed-uikit-home`. M4 PARTIAL. No native build, screenshot rendering or device execution. Temporary AST/source check: /tmp/m4_verify.py.

| Feature | Procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| Syntax / imports / inclusion | Normalize NS_ENUM/__unused, parse entire Home .m, resolve imports and existing CMake source | Grammar clean; no registration edit | Passed; existing swallowed orientation brace repaired without mask change | PASS | tree-sitter grammar, path/source-list checks; not SDK type checking |
| Storage/editor compatibility | Compare HomeTileConfig default/load/save, layout read/write, long-press/drag/resize/save/Done core | Preserve saved layouts and editing functions | Compared method bodies unchanged | PASS | AST/source comparison; new overview stays outside tile storage |
| Action and lifecycle wiring | Compare fix2PushTab/shortcuts/containment/observers; trace new actions | Original owner/routes retained, no duplicate canonical observer | Passed source checks | PASS | No coordinator implementation edits; existing notifications reused |
| Launch safety source | Inspect guard and dispatch, compare original target bindings | No force-enable or direct fallback; one dispatch | Canonical enabled/existence/edit/modal gate + UI debounce; one sendActions | PASS | Source assertion only; modal/error/busy timing needs device test |
| Data/reuse/performance | Inspect profile snapshots/name-bound buttons, label updates and layout methods | Actual metadata, no per-layout I/O, no stale index selection | Source paths satisfy checks | PASS | Associated immutable name; no new async image/network pipeline |
| Protected engine | Compare baseline allowing approved cumulative UI/docs only | Engine/framework/signing/build unchanged | Gate executed before commit | PASS | Exact path allowlist; not runtime compatibility |

## M4 device acceptance — all unexecuted

| Feature | Procedure | Expected result | Actual result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| One valid instance | Open Home with configured installed profile | Actual hero/version, canonical launch label/state and selected preview | Not run | PENDING | Native build/device environment unavailable |
| Several instances | Open with more than three saved profiles; select each through preview/See All | Real previews, selection persists; all profiles reachable in Instances | Not run | PENDING | Native build/device environment unavailable |
| Zero / unconfigured instances | Open with no profiles or selected profile lacking lastVersionId | Honest empty hero, no launch entry; Discover and Manage work | Not run | PENDING | Native build/device environment unavailable |
| Login/logout/account switching | Change account, return while avatar requests finish | Current username/account UI; no stale profile or false sign-in state | Not run | PENDING | Native build/device environment unavailable |
| Selecting another profile | Tap preview and native picker, restart | Existing setter saves selection; hero/status/cards refresh | Not run | PENDING | Native build/device environment unavailable |
| Return from Instances | See All, push/pop management pages, tap Home | Home root retained, latest profile state visible | Not run | PENDING | Native build/device environment unavailable |
| Return from Downloads | Discover, download profile, return | Original catalogue; ReloadProfileList updates overview, Home remains Home | Not run | PENDING | Native build/device environment unavailable |
| Return from Mods/Shaders/Modpacks/Multiplayer | Open original shortcut cards and return repeatedly | Unchanged fix2PushTab/native routes, no root replacement | Not run | PENDING | Native build/device environment unavailable |
| Rapid Home navigation | Alternate tabs, modal dismissals and Home reset | No overlap/duplicate presentation; scroll/editor reset works | Not run | PENDING | Native build/device environment unavailable |
| Play enabled | Tap once on an enabled canonical action with configured target | One existing coordinator action; original validation/launch chain | Not run | PENDING | Native build/device environment unavailable |
| Play disabled | While canonical button disabled, tap/programmatically trigger Home control | No forwarded action; original gate never overridden | Not run | PENDING | Native build/device environment unavailable |
| Repeated launch taps / errors | Rapid taps, taps after .8s, cancel validation alerts and return | Burst debounce works; canonical busy/modal state remains authoritative; no duplicate launch | Not run | PENDING | Native build/device environment unavailable |
| JIT Checking | Receive actual checking state, navigate and return | Live native text/color, no Home hardcoded readiness | Not run | PENDING | Native build/device environment unavailable |
| JIT Ready | Receive genuine ready status on known setup | Real owner state displayed; label alone not gameplay proof | Not run | PENDING | Native build/device environment unavailable |
| Download required | Use saved but not installed target and tap existing launch | Original coordinator interception/download path, no invented install status | Not run | PENDING | Native build/device environment unavailable |
| Background/foreground | Return from StikDebug/system and app background | Existing coordinator refresh resumes; Home updates without reconstruction | Not run | PENDING | Native build/device environment unavailable |
| Long-press edit | Enter edit on tile; press hero/account/toolbar while editing | Only tile editor operates; no launch/navigation; Done reachable | Not run | PENDING | Native build/device environment unavailable |
| Drag/resize/save | Move tiles, use four sizes, change visibility/title/icon, save and reopen | Original keys/layouts retain values; overview does not overwrite them | Not run | PENDING | Native build/device environment unavailable |
| All tiles hidden | Hide every tile and reopen Home | Overview remains visible; Customize can restore tile grid | Not run | PENDING | Native build/device environment unavailable |
| Light/Dark/System | Change existing appearance mode and accent | Readable neutral Home and correct selected/disabled states | Not run | PENDING | Native build/device environment unavailable |
| Wallpaper image/video/default | Switch wallpaper and return/scroll | Existing cached wallpaper/player presentation preserved | Not run | PENDING | Native build/device environment unavailable |
| UI Blur 0/50/100 | Adjust M3 control while Home is shown/reopened | Managed overview/button materials update; no text fade or touch blockage | Not run | PENDING | Native build/device environment unavailable |
| Panel opacity min/mid/max | Adjust M3 opacity through allowed range | Only panel tint changes; wallpaper dimming independent | Not run | PENDING | Native build/device environment unavailable |
| Narrow iPhone / iPad split width | Exercise smallest supported widths and scroll | Hero/status/previews stack; actions fit and remain reachable | Not run | PENDING | Native build/device environment unavailable |
| Wide iPad | Open landscape Home, inspect full composition | Balanced hero/status columns and profile previews; no giant gaps | Not run | PENDING | Native build/device environment unavailable |
| Orientation change | Rotate through supported orientations, with editor/modal open | No duplicated constraints or safe-area offsets; original orientation policy retained | Not run | PENDING | Native build/device environment unavailable |
| Dynamic Type | Use largest/accessibility categories and long names/translations | Overview stacks/self-sizes and scrolls without clipped actions | Not run | PENDING | Native build/device environment unavailable |
| VoiceOver | Traverse header, status, actions, selected profiles and tiles | Meaningful real labels/selection, no decorative focus traps | Not run | PENDING | Native build/device environment unavailable |
| Reduce Motion | Enable, scroll tiles, enter/exit editor and navigate | No new decorative motion; tile entry/wiggle disabled, controls still work | Not run | PENDING | Native build/device environment unavailable |
| Real gameplay | Safely build and launch known Minecraft/Java/JIT/Metallum configuration on device | Same native engine and working world; independent new evidence | Not run | PENDING | Native build/device environment unavailable |

Native build stays BLOCKED under M1. M3 global legacy-bar/search/chip coverage stays PARTIAL. Screenshot interpretation/source checks do not establish rendered fidelity or physical interaction. Next: Instances and navigation customization, retaining these pending acceptance gates.
