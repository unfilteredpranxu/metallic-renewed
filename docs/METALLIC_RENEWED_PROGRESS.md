# Metallic Renewed progress

## Current continuation checkpoint

M5 is PARTIAL: Instances presentation and safe visible navigation routing are implemented and statically checked; native visual/interaction acceptance remains PENDING. Branch: `feat/renewed-uikit-home`, based on published M4 `59faa8bb812e561b576f7ac755b76890be73738e`. Read M5 below before editing. M1 remains BLOCKED, M3 legacy appearance coverage PARTIAL, M4 Home acceptance PARTIAL. Next: Downloads UI customization. Earlier milestone sections are historical, not instructions to repeat audits.

## Permanent scope

This is UIKit customization of the existing application, not a port. Success means the same application, engine, and functionality with a better UI.

- Repository: `unfilteredpranxu/metallic-renewed`
- Development branch: `feat/renewed-uikit-home`
- Protected baseline: `baseline/alpha-1.2-fe379d4`
- Verified baseline commit: `fe379d4f3723764ec0a8b6a6728368ac3492c4d8`

Allowed work: improve existing UIKit screens, navigation, cards, buttons, menus, sheets, layouts, wallpaper, themes, glass, blur, opacity, responsiveness, and accessibility. Fix UI-only layout, interaction, and settings-persistence bugs. Connect redesigned controls to existing native functionality. Implement the six supplied design references when available.

Forbidden work: launcher rewrites, replacement or migration; SwiftUI or other framework ports; unnecessary controller replacement; changes to JIT or StikDebug, Java/JVM/JNI/runtime libraries, Metal/Metallum/graphics engines, Minecraft launch/install/authentication logic, signing, entitlements, native dependencies, framework binaries, or existing engine preferences and behavior. Do not add fake buttons, placeholder settings, or simulated functionality.

Every redesigned control must call the existing working implementation. Every setting must genuinely work, persist, and restore after restart. Preserve existing functionality when changing presentation. If a UI request requires protected engine changes, report the blocker instead.

## Change control for every milestone and commit

1. Inspect existing changes and read applicable `AGENTS.md` instructions. Preserve user work.
2. Before every commit, compare modified files against the protected baseline, including staged, unstaged, and new files. Review the actual diff as well as filenames: protected engine behavior can also reside in UIKit controllers.
3. If protected engine or framework code was changed by this work, stop and revert that unauthorized change only. Do not discard unrelated pre-existing user changes; report them for resolution.
4. Validate existing action wiring and settings persistence. Record checks actually executed and distinguish source review from device/runtime verification.
5. Update this document after each milestone with changed files, validation, limitations, and next steps.

Use the existing isolated checkout; do not create a Git worktree unless requested. Do not merge or change repository defaults.

## Milestone: source environment and scope established (2026-10-27)

- Checked out `feat/renewed-uikit-home` at the exact baseline commit above. Verified the remote protected baseline branch resolves to that same commit.
- Corrected the initial audit of `main`: the development branch contains the native application source.
- Verified native Objective-C sources and UIKit controllers under `ios-app/Natives`, including `LauncherRootViewController.m`, `HomeTopNavView.m`, and `HomeCustomizeViewController.m`.
- Verified `bundle-templates/JIT26Script.js`, `UniversalJIT26.js`, and `UniversalJIT26Extension.js`.
- Verified bundled arm64 Mach-O libraries `libmetallum.dylib` and `libmetallic_native.dylib` in `ios-app/Natives/resources/Frameworks`.
- Verified `ios-app/Amethyst.xcodeproj/project.pbxproj`, `ios-app/Makefile`, and `.github/workflows/build.yml` exist. Git integrity and clean-diff checks passed before this documentation milestone.
- Linux supports source editing and review. Xcode, Apple SDKs, simulator/device execution, signing, and iOS runtime validation are unavailable here. The renderer submodule NG-GL4ES remains uninitialized and is outside UI-only setup.
- Saved the exact repository revision and startup guidance in the environment draft. Publication and restoration in a new task have not been verified.
- No application, JIT, Java, Metal, signing, dependency, or framework code has been changed. No UI redesign has been implemented yet.

## M0: UI architecture locked (2026-10-27)

Status: documentation and targeted source mapping complete; no UI implementation. Active implementation branch: `feat/renewed-uikit-home`, starting HEAD `fe379d4f3723764ec0a8b6a6728368ac3492c4d8`. Both remote development and protected baseline branches were verified at that SHA. The fetched comparison ref is `origin/baseline/alpha-1.2-fe379d4`; merge-base matches. Only this repository was accessed. The previously staged progress document was preserved and extended.

### Evidence boundaries

User-reported working-device evidence: original Alpha 1.2 IPA launched Minecraft 26.2 and loaded a singleplayer world on an A16 iPad running iPadOS 27.2, with StikDebug, Java 25, Metal/Metallum and enabled JIT/dyld settings. This is historical user evidence, not a test executed by this task. The IPA reports source revision fe379d4; exact source-to-binary reproducibility has NOT been proven. Earlier source-transfer/integrity checks and approximately 43,232 tracked entries are prior evidence, not grounds to claim runtime reliability.

Existing diagnostic limitation reported by user: a JIT readiness check historically interpreted a breakpoint error sentinel as a successful writable mapping. Do not patch or re-investigate it in UI milestones, or treat a status label as proof of engine reliability.

### Protected implementation boundary

Never modify `ios-app/Natives/JavaLauncher.m`, `ios-app/Natives/utils.m`, JIT/StikDebug/debugger attachment/breakpoint or allocation logic, `bundle-templates/*JIT*.js`, Java runtimes/JVM/JNI, Minecraft launch/install/auth internals, game files/worlds/accounts internals, Metal/Metallum/Vulkan/ANGLE/LWJGL/shader pipelines, Java agents, framework binaries, signing/entitlements, dependencies, CI or build infrastructure. This includes engine behavior inside mixed UI files such as `LauncherRightPanelViewController.m` and advanced preferences. No optimizations or modernization of those systems.

Keep Universal Script JIT (`debug.debug_universal_script_jit`), Always Attached JIT (`debug.debug_always_attached_jit`) and Bypass dyld library validation (`debug.dyld_bypass`) available with existing semantics and enable conditions. Do not change defaults to match the historical device configuration.

### Verified architecture and action map

Paths below are relative to `ios-app/Natives/` unless otherwise stated. Entries are source-confirmed wiring, not runtime PASS results. UNKNOWN means targeted inspection did not establish the detail.

| UI/flow | Existing source and action | State/storage | Risk and implementation rule |
| --- | --- | --- | --- |
| Scene startup → root | `SceneDelegate.m`: `ameInstallLauncherRootUIWithSettingsLanguagePage:` → `ameMakeLauncherHomeViewController` → `AmeRootTabController tabControllerWithHomeViewController:`; installs window root | Creates `LauncherNewsViewController` directly; language notification rebuilds root | Do not replace startup implementation or regress language rebuild/settings-index assumptions |
| Main destinations | `AmeRootTabController.m`: current indices 0 Home, 1 Downloads (`DownloadViewController`), 2 AI (`AISessionListViewController`), 3 Instances (`VersionManagerViewController`), 4 Settings (`LauncherPreferencesViewController`); navigation wrappers via `AmeWrapInNav` | `selectedIndex`; `HomeTopNavView.m` `tapped:` → `onSelect`; Home → `ameResetToHome` | Desired Appearance destination is planned, not currently a root tab. Preserve AI and every existing destination when changing presentation; audit numerical tab consumers first |
| Home containment | `LauncherNewsViewController.m` `viewDidLoad` adds `LauncherRightPanelViewController` with `addChildViewController:`, a hidden zero-size view and `didMoveToParentViewController:` | Right panel remains launch/status owner | Preserve child lifecycle and forwarding; never install Home as a decorative background subview |
| Play Now | Home `norightLaunchTapped` → right-panel launch button `sendActionsForControlEvents:` / `launchButtonTapped`, fallback `norightPostAction:@"launch"` | Live launch title/enabled state from `AmeRightPanelStateNotification`; selected profile/account/JIT owned by existing controller | This existing handler explicitly enables the button before forwarding: preserve baseline, do not infer UI gate correctness or alter launch checks |
| Version/profile picker | Home `bottomBarChooseVersionTapped` → right-panel `showVersionPicker`; Instances `showProfileActions:` selection writes `PLProfiles.current.selectedProfileName` | `PLProfiles.m` setter saves `selectedProfile` in `$POJAV_GAME_DIR/launcher_profiles.json`, posts `SelectedProfileChanged` | Preserve save and refresh; do not duplicate profile keys or change isolation/renderer preferences |
| Profile/account display | Home `showAccountManagerModal`, `updateSkinDisplay`, `reloadProfileSection`; `UpdateAccountInfo` notification | Existing account state; credential storage internals not audited | Preserve existing account UI and callbacks; no auth implementation changes |
| Download catalogue | `DownloadViewController.m`: `tabChanged:`, `versionFilterChanged:`, `showFilterOptions`, `showSortOptions`, `sidebarSortButtonClicked:`, search-bar delegate callbacks | Existing catalogue/filter/search state; target profile defaults to selected profile | Reuse actual filtering/download handlers; do not invent providers or progress |
| Download actions and tasks | Catalogue `startVersionDownload:`, `downloadMod:`, `downloadShader:`, related resource callbacks; Home `openDownloadCenterModal` → right-panel `openDownloadCenter` or `DownloadTasksViewController` | Right-panel `AmeRightPanelStateNotification` drives badge/progress presentation | Catalogue and task centre are distinct; preserve real progress/errors and target profile. No install-engine edits |
| Appearance entry | Settings `general.launcher_background` action presents `BackgroundSettingsViewController`; `HomeCustomizeViewController.m` manages Home tile customization | Existing helpers/preferences | Full Appearance root is planned. Keep all Settings and advanced options reachable |
| Theme | Settings `ui_theme` action posts `UIThemeChanged`; `SceneDelegate.m` `applyUITheme:` updates window override | `general.ui_theme`: `auto`, `light`, `dark`; generic `setPreference` → `setPrefObject` | Never reload/reset accounts to change theme; verify both live and cold-start appearance |
| Glass | `BackgroundSettingsViewController.m` `glassStyleChanged:` / Settings glass special cases → `AMEGlassStyleSetConfigured`; helper `AMEGlassStyle.h`; `UIKit+GlassSurface.h` `AmeGlassEffect` | NSUserDefaults `background_glass_style`, `background_glass_handdrawn`; style notification and UI effect refresh | Listed `UIKit+GlassSurface.m` does not exist. Header uses runtime `UIGlassEffect` probing and UIKit blur fallback. Keep existing SwiftUI `AmeTabBar.swift` integration |
| UI blur | Background settings `blurIntensitySliderChanged:` → `BackgroundManager.blurIntensity` + `refreshUIEffect` | `background_blur_intensity`, clamped 0–1, saved by `saveUISettings` | Existing rendering uses effect alpha (e.g. 0.3 + intensity × 0.7 in `applyEffectToView:`), not a verified physical blur-radius API. Wallpaper also receives blur refresh; do not claim independent wallpaper blur controls exist |
| Panel opacity | `opacitySliderChanged:` → `BackgroundManager.uiOpacity` + `refreshUIEffect`; `applyEffectToView:`, cell/navigation helpers | `background_ui_opacity`, clamped 0.1–1 | Rendering depends on material/style; some branches use inverse alpha. Preserve existing semantics and do not turn panel opacity into wallpaper dimming |
| Wallpaper | Background settings `selectImageBackground`, `selectVideoBackground`, picker flow → manager `setImageBackground:completion:` / `setVideoBackgroundWithURL:completion:`; `restoreDefaultBackground` → `clearBackground` | `background_type`, `background_path`; `loadSavedBackground`, `saveBackgroundSettings` | Missing/nil path handling must survive; nil removes the defaults key. Existing reset also changes effect/opacity; do not relabel it as a broader reset without defining UI-only behavior |
| Settings persistence | Settings `setPreference` generic path → `setPrefObject`; `PLPreferences.m` global/instance save methods | Global `$POJAV_HOME/launcher_preferences_v2.plist`; instance `launcher_preferences.plist`; wallpaper uses NSUserDefaults separately | Preserve scope, migrations, legitimate false/zero values and shared keys; restart validation pending |
| Refresh/lifecycle | Home `viewWillAppear:` posts `AmeRightPanelRequestStateNotification`; panel `viewWillAppear:` / `norightHandleStateRequest:` → `norightBroadcastState` call existing `updateJITStatus`; Home consumes state notification | Existing right-panel state; background manager observes app background/foreground; Home logo observes did-become-active | Preserve lifecycle and notification subscriptions. Scene active/foreground methods alone do not establish JIT refresh; no new cached status |
| Legacy navigation | `LauncherRootViewController.m` retains split/right-panel composition; `LauncherMenuViewController.m` `ameTabSelected:` forwards `AmeTabSelected` from `AmeTabBar.swift` | Existing legacy route notifications | Not the active scene Home root. Do not delete working SwiftUI or add a competing tab-selection handler |
| Launch intro / See All | Exact launch-intro setting and desired See All callback UNKNOWN in targeted entry points | UNKNOWN | Confirm existing implementation before exposing either control; no invented selectors, keys or fake controls |

### Layout and regression safeguards for all following milestones

A — Touch delivery: retain UIKit containment, visible button hierarchy and hit testing; decorative overlays must not intercept touches; test taps on primary actions and after presentations.

B — Stuck JIT checking: retain appearance callbacks, right-panel child and state-request notifications, app return behavior; never cache/hardcode a status or change the verifier.

C — Overlapping navigation: retain `AmeTabInstantAnimator` zero-duration transition/removal safeguards, single selection path, navigation stacks, `ameFloatingDoneTapped` and `ameResetToHome`. Rapid alternating/repeated taps and modal dismissal must be tested.

D — Invisible glass: preserve `BackgroundManager.loadUISettings` absent-key detection and existing glass migration, AMEGlassStyle availability checks, true Apple materials and fallbacks. Legitimate zero is not the same as missing. No decorative substitute pretending to be a functional effect.

E — Wallpaper reset/crash: retain nil-safe `saveBackgroundSettings`, path handling and persistence/migration. Test missing files, clear and restart. Keep wallpaper blur/dimming conceptually separate from UI panel opacity; existing shared blur effects need careful UI-only assessment before separation.

F — Adaptive geometry: `HomeTopNavView.m` bar height is currently 60; `AmeRootTabController.m` other destinations reserve 76 (60 + 8 + 8); Home `LauncherNewsViewController.m` uses `kHomeNavReserve = 76` and `applyHomeSafeAreaInsets`. These are observed source values, not new design measurements. Treat them as coordinated dependencies. Preserve orientation/trait/safe-area updates, no double inset or duplicate constraints; test phone/tablet and keyboard/sheets/popovers.

G — Real settings: reuse mapped callbacks/storage/notifications; expose no fake toggles, sliders, download buttons, duplicate keys or simulated progress. Verify value changes, actual visual/function change, and cold restart. Keep engine preferences unchanged.

### Modified files and validation

M0 modifies only these documents: `docs/METALLIC_RENEWED_PROGRESS.md` (extends earlier staged file), `docs/METALLIC_RENEWED_UI_SPEC.md`, `docs/METALLIC_RENEWED_TEST_MATRIX.md`. `/docs` is ignored by existing rules; force-add only these explicit files, do not change `.gitignore`.

Checks: origin identity, branch/HEAD, remote UI/baseline refs and merge-base confirmed; source-map symbols checked in targeted files. Executed precommit gate compared staged and unstaged paths/content against the fetched baseline: only these three documents differ, no other untracked files, `git diff --cached --check` passed, and all non-document tracked content equals the protected baseline (engine diff zero). The gate is repeated before commits. No build, IPA, physical-device test, launch, persistence restart, or visual verification performed. See test matrix for precise PASS/PENDING evidence.

### Unresolved and next milestone

The six screenshots have not been attached in this conversation; visual measurements, exact colors and final composition remain unverified. Desired five destinations differ from current tabs; AI must remain accessible. Intro controls, See All and full reset semantics need targeted confirmation when implemented. NG-GL4ES remains uninitialized; native builds have not been reproduced. Linux has no Xcode/Apple SDK. M0 does not establish engine reliability or source-to-IPA equivalence.

**Exact next milestone: M1 — Baseline build verification.** Read this document first, verify repository/branch/HEAD and carry M0 forward without repeating the audit. Establish access to macOS/Xcode and the existing approved build path; inspect `BUILDING.md`, `ios-app/AGENTS.md` and existing build configuration read-only. Capture toolchain, source revision, dependency availability, command/logs and artifact provenance. Do not alter CI/build infrastructure, dependencies, signing, entitlements or protected source; if reproduction requires those changes, report the precise blocker. Compare the untouched engine tree to baseline and keep device gameplay/restart tests pending until actually run. After build verification, obtain the six references and begin a small UIKit presentation milestone using the map above.

At the start of every future task: read this progress document, check repository/branch, confirm milestone, read only necessary files, continue. After every milestone update changed files, tests, commit reference and exact next action. No merges, pushes, default-branch changes or baseline edits are authorized by M0.

### M0 commit record

M0 documentation commit: `a1b9d8f89b64b746861afe9181fafd3ceea41284` (`docs(ui): lock M0 scope and architecture`). This final bookkeeping update records that completed milestone commit; its own commit can be resolved with `git log -1 --format=%H -- docs/METALLIC_RENEWED_PROGRESS.md` (a commit cannot contain its own hash). M0 is complete. Next action remains M1 baseline build verification, with build/device results PENDING.


## M1: native IPA build verification (2026-10-27)

**Status: BLOCKED.** Focused inspection complete; no suitable unchanged-source native workflow was found. No workflow dispatched, native build attempted, artifact generated, or physical-device test executed. No compiler failure exists to diagnose because compilation was not started. This does not mean the historical IPA failed or that the application cannot be built elsewhere.

### Source and protection evidence

Repository `unfilteredpranxu/metallic-renewed`, branch `feat/renewed-uikit-home`, inspected source HEAD `26d114919d7ab8f7426352598783f2e82d36a232` (published M0). Remote UI ref matched that SHA; remote protected branch `baseline/alpha-1.2-fe379d4` matched `fe379d4f3723764ec0a8b6a6728368ac3492c4d8`. Before M1 changes, `git diff --exit-code origin/baseline/alpha-1.2-fe379d4 HEAD -- . ':(exclude)docs'` passed, as did staged/unstaged clean checks. All non-document content, including JIT, JavaLauncher/utils, runtimes, renderer/native libraries, signing, entitlements, functional preferences, UI and CI/build files, is unchanged. Final precommit gate repeats exact non-document equality and permits only the progress/test-matrix edits for M1.

M0 publication was independently confirmed in the previous task: remote commit `26d114919d7ab8f7426352598783f2e82d36a232`, with all three documents available. That GitHub publication is distinct from publishing the cloud environment snapshot.

### Existing build entry points (read-only inspection)

- `.github/workflows/build.yml` (`Build iOS`) is manual `workflow_dispatch`, `macos-latest`; checkout enables LFS and recursive submodules. It declares no custom dispatch inputs. It would need ref `feat/renewed-uikit-home`; no dispatch was sent. It installs Zulu JDK 8 and `ldid`/`wget`, reads Xcode versions, then runs from `ios-app`: `set -o pipefail; make all BOOTJDK=$JAVA_HOME/bin SDKPATH=$(xcrun --sdk iphoneos --show-sdk-path) 2>&1 | tee build.log`. This is a full native build intent, not a UI preview, but actual Minecraft capability is unverified.
- `ios-app/Makefile:330`: `all: clean native java jre assets payload package dsym`. Native CMake cross-compiles arm64 for iOS with the Apple SDK and compiles the existing SwiftUI bar. Defaults: `PLATFORM=2`, `SLIMMED=0`, `SLIMMED_ONLY=0`, `RUNNER=0`, `RELEASE=0`; no build settings were changed.
- `BUILDING.md` mentions Xcode/`make`, but calls its final artifact Alpha 1.1, while the Makefile declares 1.2.0. It is not evidence of reproducibility. Opening the Xcode project alone does not verify full payload assembly.
- `codemagic.yaml` defines `ios-build` on `mac_mini_m2`, Xcode latest and JDK 8 installation in script; uses the same `make all` command and includes a separate Minecraft 26.2 pre-bundle step. It is not a safe fallback (see below) and was not run.
- `.github/workflows/what-was-done.yml` is report-only on Ubuntu, explicitly builds nothing and also clones upstream. It cannot verify an IPA and was not run. These are the only two workflows in `.github/workflows` at the inspected revision.

### Exact dispatch blockers

1. `build.yml:31–87` clones moving upstream repositories (`herbrine8403/Amethyst-iOS-MyRemastered`, fallback `AngelAuraMC/Amethyst-iOS`) and copies missing submodule/native files into the runner checkout. Those are unapproved source substitutions, not a build of only the copied baseline. No other repository was accessed by this task.
2. `build.yml:97–106` conditionally replaces/fetches the ZeroTier dependency from another moving repository. `:115–168` can edit CMake source lists and Home source imports. `:170–191` explicitly patches AI and UI source in the runner checkout. Runner-only edits are still changes to build inputs and violate this verification milestone's restrictions.
3. The Makefile's `dep_mg` dependency (`:485` onward) replaces vendored glslang/SPIRV-Cross trees with downloaded snapshots by default. Payload dependencies include binary-patching targets (`dep_angle_freeze`, `dep_sdl3_guard`) and NG-GL4ES patch application. Do not execute these or disable guards to work around M1 restrictions.
4. Codemagic repeats upstream filling and runner patches and can promote/remove renderer libraries (`codemagic.yaml:94–96`). It is unsuitable for verifying unchanged source/framework inputs.
5. The selected worker is Linux. `xcodebuild`, `xcrun`, `codesign`, and `ldid` are unavailable. No Apple SDK/macOS executor is attached. Do not run a Linux IPA build or change CI to evade this blocker.

These are suitability blockers, not a permissions/token diagnosis. No dispatch/API authorization test was necessary once the available workflows were disqualified. Do not request new credentials as a substitute for a safe build path. Next external prerequisite for native verification: an approved macOS/Xcode route with known original dependencies and explicitly established handling of the existing runner substitutions/patches, or a separate user decision about those build-input changes. M1 authorizes no workflow or code changes.

### Immediate dependency and packaging checks

Overall dependencies: **Missing locally; remote resolution and final payload completeness Unverified.** No dependencies were installed, replaced or fetched from other repositories.

| Item | Observed result / evidence | Limitation |
| --- | --- | --- |
| Frameworks directory | Only `libmetallum.dylib` and `libmetallic_native.dylib` are present; `file` identifies both as arm64 Mach-O shared libraries | Presence/type do not prove linkability, correct signing, runtime compatibility or source/binary equivalence |
| Required linked frameworks | `libEGL.framework`, `libGLESv2.framework`, `AltKit.framework`, `CAltKit.framework`, `UnzipKit.framework` absent from `ios-app/Natives/resources/Frameworks`; named by native CMake link configuration | Full untouched checkout is not dependency-complete |
| Other referenced libraries | `libMoltenVK.dylib` and `libspirv-cross-c-shared.0.dylib` absent at Makefile resource paths | Some dependencies can be generated/fetched; no successful build or compatible resolution verified |
| ZeroTier | `ios-app/Natives/external/ZeroTierFramework/ios-example-app/zt.framework/zt` absent; CMakeLists.txt:75 has an explicit fatal missing-framework condition | Predicted configure prerequisite failure, not an executed CMake failure |
| Native/resource prerequisites | `ios-app/Natives/input/ControllerInput.m` and `ios-app/Natives/resources/en.lproj/LaunchScreen.storyboardc` absent; TouchController directory absent (optional paths exist in CMake/Makefile) | CI explicitly checks ControllerInput and copies from upstream; no replacements made |
| NG-GL4ES | `.gitmodules` points to BZLZHH/NG-GL4ES; `git submodule status` reports uninitialized `6e153a1622a8d9ef903f7975aafbef2453571bab`; no local CMakeLists.txt | Not initialized. Pinned commit's remote fetchability not tested, to preserve target-repository-only scope. No claim that submodule resolution passed |
| LFS | `git lfs version` = 3.6.1; `git lfs ls-files` empty; `git ls-files -- '*.tgz'` empty. `.gitattributes` applies LFS to `*.tgz` | No indexed LFS assets to materialize in this revision; does not establish remote LFS availability or restore missing dependencies |
| Java runtimes | `ios-app/depends` and JRE 8/17/21/25 `lib/server/libjvm.dylib` absent | Makefile jre target downloads from `assets.angelauramc.dev/openjdk/ios-arm64/jreN-ios-aarch64.zip`, validates/extracts and assembles `artifacts/java_runtimes`. URLs/content not fetched/verified |
| Java payload | Existing JavaApp Makefile compiles launcher/agent JARs; parent payload copies JavaApp build outputs plus existing dependency JAR directories | No Java build run. Java 25 runtime in generated IPA unverified |
| JIT scripts | `JIT26Script.js`, `UniversalJIT26.js`, `UniversalJIT26Extension.js` exist in root `bundle-templates`, absent from `ios-app/Natives/resources` | No copy step referring to those names or `bundle-templates` found in build.yml, codemagic.yaml or ios-app/Makefile. Native payload copies Natives/resources, not root templates. Script inclusion in final app NOT established; no packaging fix made |
| Metal payload | Makefile payload copies Natives/resources (including Frameworks) and generated dylibs to app bundle | Intended path includes existing Metallum/native libraries; no IPA inspected, binary/signing validation pending |
| Full vs slimmed | Non-slimmed payload copies Java runtimes into app; slimmed packaging explicitly excludes runtimes | Default full-IPA intent only; neither full nor preview artifact created |

### Signing, artifacts and diagnostics

Signing/entitlement files and settings remain byte-identical to baseline. Existing payload code uses `ldid` and sideload/TrollStore/platform-specific entitlements; package conditionally uses Apple codesign/provisioning only when its original team/profile conditions are met, otherwise prints that codesigning was skipped. Framework `ldid` step suppresses failures (`|| true`). This is not proof every embedded binary is correctly signed; no signature was verified and no entitlement setting changed.

Expected full output by Makefile defaults: `ios-app/artifacts/com.tokyxkai.metallic-1.2.0-ios.ipa` (TrollStore changes suffix to `.tipa`). Workflow checks for an IPA and uploads artifact `metallic-ipa` from `ios-app/artifacts/*.ipa`. Build captures `ios-app/build.log`; failure steps print/annotate compiler/linker errors. Makefile has `dsym`, but workflow does not upload build.log, dSYM, or java_runtimes.zip as diagnostic artifacts; diagnostic persistence is therefore limited to Actions logs and the success-only IPA artifact. No run URL or artifact URL exists for M1.

Known working configuration is preserved as historical user evidence: Minecraft 26.2, Java 25, StikDebug, Universal Script JIT, Always Attached JIT, dyld library-validation bypass and native Metallum. No values/defaults changed. New IPA reproduction of this configuration is unverified; missing local runtimes and unestablished JIT script packaging are concrete gaps. All physical-device JIT/Java/Metal/gameplay and restart tests remain PENDING. Source equality is verified separately from runtime compatibility.

### Results and continuation

Changed files: only `docs/METALLIC_RENEWED_PROGRESS.md` and `docs/METALLIC_RENEWED_TEST_MATRIX.md`. UI spec unchanged. Tests: repository/ref and baseline equality checks PASS; dependency/path inspection completed with missing results; workflow suitability fails M1 constraints; native build, artifact inspection, signature and physical-device tests PENDING. No build fixes attempted. See matrix for individual evidence.

**Next milestone: Unified UIKit design foundation.** Read saved progress first; use the M0 action map without repeating it. Native build verification remains BLOCKED and must not be represented as PASS before subsequent UI work. Obtain the six design references, confirm tokens/material/typography/spacing against existing helpers, and define a small UIKit-only design foundation with preserved controls, storage and lifecycle. Keep baseline build/artifact/device gates open; proceed to implementation only within the user's next milestone instructions.

### M1 commit record

Verification documentation: `299449a4e05dd18fc224a08d5aa6065865346684` (`docs(build): record blocked M1 verification`). Final bookkeeping commit records this SHA; resolve its own SHA with `git log -1 --format=%H -- docs/METALLIC_RENEWED_PROGRESS.md`. Precommit and post-inspection protection gates PASS: only the two M1 documentation files changed, and every non-document tracked input remains identical to protected baseline. M1 stays BLOCKED; native build/artifact/device results remain pending. Next milestone: Unified UIKit design foundation.


## M2: shared UIKit appearance foundation (2026-10-27)

**Status: COMPLETE in source, with native build and all runtime/visual tests pending.** Started on verified feature branch at published M1 commit `a08a458a78e908bb993b7f7edc84359295c740fc`, clean working tree, required baseline ancestry preserved. The attached M2 screenshot set was visible and reviewed (including repeated captures of Home empty/selected-instance states, Appearance, Downloads and Settings). This supersedes earlier missing-reference observations. No screen layout was invented or redesigned in M2.

### Implemented UI changes / interfaces

Only four existing UI files changed; no new compilation unit or build registration:

- `ios-app/Natives/UIKit+GlassSurface.h`: additive `AmeUI*` semantic color/geometry helpers and `AmeUIFont(AmeUIFontRole)` for screen/section/card/body/status/button/description text. Accent delegates to the unchanged `AmeThemeTintColor` preference adapter. Primary/secondary/tertiary/disabled/destructive colors use semantic UIKit colors; panel/selection/border and overlay contrast tokens are trait aware. Layer-backed colors use `AmeUIResolvedColor` and display-scale hairlines. Existing card radius enum (13/16/22/26) and material helpers remain unchanged. New spacing values (16 margin/padding, 8 item gap, 24 section gap, 44 minimum touch target) are implementation defaults, NOT inferred screenshot measurements; only the unchanged 8-point bottom-row spacing is adopted in this milestone. Other tokens are opt-in for later screens.
- `ios-app/Natives/BottomActionBarView.h`: preserves existing class/function names; adds `AmeGlassButtonRole` primary/secondary/subtle/navigation/destructive and properties `ameRole`, `ameShowsActivityIndicator`. Roles style existing controls; no new product buttons/settings were created. Primary is default. Busy property is presentation only: action owners must retain existing enable/busy guards; no launch logic is connected to it or replaced.
- `ios-app/Natives/BottomActionBarView.m`: existing `AmePinkGlassButton` now has one real native material instead of permanent gradient/glow decoration. Thin semantic border and foreground states, opt-in low-strength hand-drawn tint, disabled/highlighted/selected appearance, optional noninteractive activity indicator, UIFontMetrics button typography. Bottom row adopts secondary role; its actual Execute Jar / Choose Version buttons remain the same objects. Effect created once and replaced only on explicit material-style notification; layout adjusts frames/radii only. No new constraints or observers in layout; each instance registers visual observers once and removes them on deallocation. Trait changes refresh layer-backed borders. No preference writes.
- `ios-app/Natives/HomeTopNavView.m`: unselected text now semantic rather than hardcoded near-white; selected accent uses existing preference adapter, selector uses semantic neutral fill. Text scaling bounded to 20 points for the existing fixed-height bar, with content-size notification and width-cache invalidation. Selection capsule moves in a restrained 0.22-second animation, no squash, immediate placement with Reduce Motion. Hit buttons expose selected accessibility traits; decorative text/icon stack is hidden from accessibility to avoid duplicate elements. Existing tap selector/event and tab notification callback are byte-identical. Material/theme changes have one visual refresh path and cleanup.

### Preserved architecture and settings

No controller, containment, root installation, navigation stack, zero-duration tab-transition safeguard, Home refresh, right-panel launch/JIT bridge, theme persistence or SceneDelegate implementation changed. Tab arrays/order and baseline hidden AI slot remain unchanged (no removal or new AI restriction). HomeTopNavView's 60-point height, existing constraints, and the untouched 76-point reservations are preserved. Existing 36-point bottom actions are NOT enlarged in M2 because parent geometry is coupled; minimum-touch and full accessibility layout verification remains pending for the later adaptive milestone.

`general.accent_color` adapter and its default are byte-identical; `auto/light/dark`, `UIThemeChanged`, `LauncherAppearanceChanged`, `AMEGlassStyleChanged` are reused, no parallel theme store. `AMEGlassStyle.h` and `BackgroundManager.h/.m` are unchanged, preserving absent-key checks, migrations, nil-safe wallpaper persistence, slider ranges/defaults, `background_ui_opacity`, `background_blur_intensity`, and glass keys. Current material behavior remains governed by existing resolver, with fallback to public system UIBlurEffect. No new private API or tuning introduced; existing legacy private-tuning helpers were not edited or invoked by new code. The material remains beneath title/image and does not intercept touch/accessibility. No opacity/blur sliders or wallpaper controls are implemented in M2; M3 must integrate their existing semantics carefully.

### Validation actually executed

- `git diff --check`: PASS.
- Objective-C grammar parsing using tree-sitter + tree-sitter-objc, installed only under `/tmp/metallic-m2-parser`: both changed .m files parsed with zero errors directly. Both changed .h files and their baseline versions parsed with zero errors after parser-only expansion of NS_ENUM and removal/normalization of NS_ASSUME_NONNULL/FOUNDATION_EXPORT macros. This is grammar validation, NOT Apple SDK type checking, Objective-C linking, IPA compilation, visual verification or button-tap testing. No C/Objective-C compiler with UIKit SDK is available here.
- Targeted assertions: nav `tapped:` and `tabNote:` bodies, existing hit target/event, AI hidden-slot statement, geometry constants/anchor lines, bottom-button anchor lines/titles, and `AmeThemeTintColor` implementation are unchanged. No new/changed preference keys. Local quoted imports resolve; HomeTopNavView.m and BottomActionBarView.m already appear in native CMakeLists.txt. PASS.
- Reviewed entire UI diff: presentation-only enum/tokens/styles/states/observers/animation/accessibility; no action selectors replaced, callbacks forwarded twice, added gestures, enabled-state mutation, or controller changes. Only material/indicator descendants are noninteractive. Observer cleanup and construction guards retained. Font/style changes do not add constraints. Public APIs introduced are available before the existing iOS 14 minimum; newer glass remains resolved by the existing helper.
- Protected gate: compare every path to `fe379d4f3723764ec0a8b6a6728368ac3492c4d8` allowing ONLY these four UI files and the three M0/M1/M2 docs. All other tracked content identical: **engine/framework/JIT/Java/Metal/launch/auth/startup/signing/dependencies/build/workflow diff ZERO**. This gate is repeated before committing. UI spec and matrix updated below; no unrelated or new source files.

### Limitations / risks / exact next action

M1 stays **BLOCKED**, not failed: existing CI substitutes/patches protected inputs and this Linux worker has no Xcode/Apple SDK. No unsuitable workflow was dispatched. No native compile, screenshot render, simulator, device tap, lifecycle, persistence restart, JIT, Java, Metal or gameplay test passed. Historical working IPA is not evidence of these source changes running successfully.

Residual risks needing native validation: dynamic type versus fixed pill/bottom-bar geometry, light-theme contrast over arbitrary dark wallpaper, disabled/selected combinations and UIKit system-button highlighting, semantic border appearance on each display scale, busy presentation with existing launch owner, material changes while visible, rapid-tap/rotation behavior, and existing compact layout limitations. Opt-in roles/busy presentation beyond current primary/secondary callers need future adoption testing. No claim of matching complete screenshots. Screenshots' JIT labels, runtime value 0 and example profiles are visual references, not values to hardcode.

**Next milestone: M3 — Wallpaper, Glass, Blur and Opacity integration.** Start with this checkpoint, the existing BackgroundSettingsViewController actions and BackgroundManager public interface, AMEGlassStyle, and M0 persistence map. Use the newly supplied Appearance reference; preserve engine settings. Confirm current shared blur/opacity behavior, design safe UI-only integration with the existing keys, and distinguish wallpaper dimming/blur from interface tint/material. Do not promise a physical blur radius or change ranges/defaults. Keep M1 build blockers and all device/runtime tests open. Do not restructure navigation or redesign Home/Downloads/Settings in that milestone unless explicitly requested.

### M2 commit record

Implementation commit: `031de92d00a056a38e791e93fedc7fceae0f330d` (`feat(ui): establish shared UIKit appearance foundation`). Final documentation bookkeeping records this SHA; resolve its own SHA with `git log -1 --format=%H -- docs/METALLIC_RENEWED_PROGRESS.md`. Source-only M2 completion does not change M1 BLOCKED or pending device/build statuses. Next: Wallpaper, Glass, Blur and Opacity integration.


## M3: wallpaper, glass and live appearance (2026-10-27)

**Status: PARTIAL.** Real UI code implemented and statically checked; not a claim of complete global coverage or native/device validation. Start: published M2 `0940a6d9d9824c10ee5eaad0e07267a7ccea48fc` on `feat/renewed-uikit-home`, clean tree. Origin/remote feature/protected-baseline refs verified. M2 tokens/typography/roles/accessibility/Reduce Motion and 60/76-point navigation geometry preserved. M1 remains BLOCKED; no workflows or build settings changed.

### Files and actual rendering responsibilities

Modified existing UI files only: `ios-app/Natives/BackgroundManager.h`, `BackgroundManager.m`, `BackgroundSettingsViewController.m`, `BottomActionBarView.m`, `HomeTopNavView.m`. No new compilation unit/dependency/registration. Three continuity documents updated.

The original single `blurIntensity` controlled wallpaper material alpha, wallpaper dim alpha, and some interface panel alpha. One number cannot represent independent values. Two new UI-only NSUserDefaults keys therefore live in the same BackgroundManager store, with the legacy key preserved:

| Control / property | Key / range / migration | Actual rendered target |
| --- | --- | --- |
| Wallpaper Blur / `blurIntensity` / existing `blurIntensitySliderChanged:` | Existing `background_blur_intensity`, 0–1, absent/invalid default 0.7; explicit zero retained | Custom wallpaper's standard system thin-material view alpha = value × 0.5. No longer a live input to interface materials or dimming |
| UI Blur / `interfaceBlurIntensity` / new `interfaceBlurSliderChanged:` | New `background_interface_blur_intensity_v1`, 0–1; when absent seed previous panel visibility: min(1, 0.3 + legacy × 0.7 + 0.2 if no custom wallpaper). Existing zero is retained. Invalid/non-finite values safely clamp/fall back to 0.79 | Only decorative interface material alpha; zero makes the material invisible while panel tint/text remain. Does not claim arbitrary Gaussian blur radius. Disabled in Translucent mode; stored value preserved |
| UI Panel Opacity / `uiOpacity` / existing `opacitySliderChanged:` | Existing `background_ui_opacity`, 0.1–1; existing default 0.7 | Managed panel backdrop tint, separate from content alpha: tint alpha = opacity × 0.22 in Blur mode, opacity in Translucent mode. 100% means maximum tint strength for the chosen material, not opaque text/card hierarchy. No wallpaper dimming |
| Wallpaper Dimming / `wallpaperDimming` / new `wallpaperDimmingSliderChanged:` | New `background_wallpaper_dimming_v1`, 0–1; absent seed validated legacy blur; invalid fallback 0.7; explicit zero retained | Dedicated black wallpaper overlay alpha up to 0.2 in Dark, 0.08 in Light. Corrects old labelColor overlay that whitened Dark mode; saved intensity retained but appearance intentionally corrected |

Both new keys are initialized once when absent, persisted alongside existing appearance values, and never written through PLPreferences. Old keys/defaults/glass migrations are unchanged. Downgrading ignores new keys and resumes the old coupling, without losing wallpaper paths or legacy blur/opacity values. Wallpaper controls apply to custom images/videos and are disabled without one; established default wallpaper stays unchanged. Theme System/Light/Dark remains in existing main Settings with its original preference/enable conditions; no duplicate theme control/store or new Appearance destination was introduced.

### Surfaces, performance and state consistency

Manager-owned ordinary views/table-cell backgrounds/collection-cell backgrounds now reuse one noninteractive native UIVisualEffectView. `applyInterfaceAppearanceToMaterial:inView:` updates decoration alpha and host tint; it never fades labels/buttons/icons or changes their enabled state. Uses unchanged `AmeGlassEffect`/AMEGlassStyle capability checks and public UIKit material fallback. No private backdrop tuning in changed manager paths. Optional highlight/rim controls are retained; table/collection rows preserve no-rim treatment and frame repair is retained for other rim hosts.

A weak registry updates only attached managed hosts. `refreshUIEffect` coalesces requests to one next-frame update, without traversing the root tree, reading wallpaper files, rebuilding materials or recreating players. It is the sole BackgroundUIEffectChanged sender in the manager; effect picker/rim/style callbacks route through it rather than issuing extra direct broadcasts. Explicit style changes may traverse existing glass once; they skip the wallpaper container so interface style never replaces wallpaper material. NSUserDefaults synchronous flushes removed from slider saving; native asynchronous persistence used. Process-kill/restart durability still needs device testing.

M2 glass buttons and top bar now consume the shared material/tint values and existing appearance notification. Their state multipliers/targets/selection/geometry/Reduce Motion remain. BackgroundSettings uses a construction-only slider builder with 44-point slider height, Auto Layout, M2 fonts/semantic colors, distinct live percentage and VoiceOver value. No reload or target duplication in value-change callbacks; synchronization skips tracking sliders. Reopening reads actual manager state; visible style/switch/highlight/slider/effect labels update without replacing cells. Existing main Settings glass keys and notifications remain shared. No competing preferences.

### Wallpaper and reset safety

Default renderer/aspect-fill bundled image/fallback, image crop/picker flow, video aspect-fill, pause/resume/loop methods preserved. Host assignment now occurs after removal of old presentation (previously removal nulled the newly assigned window/split controller). Reapplying the same path/host or default presentation reuses it; no new player on navigation. Cold image reads run off-main and cache a single image/preview, with path/container identity checks; the established default fills the loading interval. Invalid/missing paths/types fall back safely and nil path uses removeObjectForKey. Corrupt or invalid video playback still requires native validation; no new format/codec implementation.

New wallpaper is encoded/copied before changing the current wallpaper; failure retains previous state. Successful replacement/model/UI work occurs on main. UUID file names avoid same-second collisions. A pending-selection token prevents a delayed completion from undoing a newer pick/clear. Security scopes for Files are retained through reads/copy; image File reads moved off-main with error feedback. Cancellation delegates remain no-op/dismiss-only. Clear installs default immediately, retains the host, preserves appearance properties, and deletes only app-owned generated copies within the backgrounds folder, never arbitrary persisted Documents paths. No game/world/account data touched. AVPlayer behavior/lifecycle methods themselves remain unchanged.

New **Reset to Recommended** (Interface Glass row) confirms its exact scope, then resets only `uiEffect=Blur`, `uiOpacity=0.7`, `interfaceBlurIntensity=0.79` (derived from existing 0.7 recommendation). Persists once and schedules one appearance refresh; visible controls reload only after the reset action, not during slider tracking. It retains wallpaper/path, wallpaper blur/dimming, theme, glass style/highlights, account/profile and all gameplay/JIT/Java/renderer settings. Existing **Restore Default Background** intentionally still clears custom wallpaper and resets UI effect/opacity as before; **Clear Background** leaves appearance values alone. These legacy flows are not silently redefined.

### Checks actually executed and boundaries

PASS: `git diff --check`; grammar parsing of four changed .m files plus normalized BackgroundManager.h; local imports and existing source registration; all old preference constants unchanged, exactly two new keys; source assertions of control→property→save→render paths and reset's three assignments; zero/absence guards; one manager appearance broadcast; no private tuning call in manager; tracking-safe refresh; M2 tap/tab/selector animation and accent adapter bodies unchanged. The actual production pure-C clamping function was extracted and compiled with GCC; nine boundary cases executed (zero, minimum, negative, above maximum, in-range, maximum, NaN, positive/negative infinity). This is not an Objective-C/UIKit or NSUserDefaults runtime test. Temporary grammar/clamp tools live only in /tmp.

Protected-file comparison against `fe379d4f3723764ec0a8b6a6728368ac3492c4d8` permits only approved M2/M3 UI files and these three docs; every other tracked file is identical. **JIT/Java/Metallum/Metal/launch/auth/framework/signing/dependency/CI/Makefile diff ZERO.** No native compilation, IPA, signature inspection, iPhone/iPad interaction, restart, visual, performance or new gameplay evidence. JavaGUI's original root-transparency semantics are explicitly preserved in the appearance helper without editing that controller.

### Remaining limits and next step

Independence is implemented in source for manager-owned panels/cells, M2 buttons/top navigation and custom wallpaper. Legacy system UINavigationBar/UIToolbar cached appearances, search-field styling, and arbitrary controls using separate chip helpers have not all been adapted to the new UI Blur/tint semantics. Do not claim global consistency; that coverage and visual acceptance remain PENDING. No new global Appearance destination or theme picker/launch-intro control was added. English fallback strings for new localize keys need translation review. Fixed legacy glass-control rows/large type, video file errors, cold preview timing, rapid switching, Light/Dark tint readability and memory/performance require device validation.

Next milestone: **Polished and fully functional Home screen**. Start in `LauncherNewsViewController.m`, reuse M0's original right-panel launch/version/account/download callbacks, M2 tokens and M3 appearance interface. Keep root containment, 60/76 geometry and tab transition protections; do not move JIT/engine behavior. Carry forward M1 BLOCKED and the pending global appearance/device matrix. Read this progress first; do not repeat M0–M2.

### M3 commit record

Implementation: `788f9508059bfef5f937921617bf780903e37545` (`feat(ui): integrate wallpaper glass and appearance controls`). Final bookkeeping commit records this SHA; resolve its own SHA with `git log -1 --format=%H -- docs/METALLIC_RENEWED_PROGRESS.md`. Final checks also confirmed wallpaper lifecycle/default draw and picker-cancellation method bodies unchanged. M3 remains PARTIAL, M1 BLOCKED, runtime/device acceptance PENDING. Next: Polished and fully functional Home screen.


## M4: functional Home presentation (2026-10-27)

**Status: PARTIAL.** Meaningful UIKit implementation delivered; exact rendered fidelity, native type checking and device acceptance are unverified. Started from published M3 `6d260fb2a11293306d7e0b3543653cc3759152c3`, correct feature branch, clean working tree. Only `ios-app/Natives/LauncherNewsViewController.m` and the three continuity documents change in M4. No new source file/project registration. Earlier Home screenshots in this conversation informed composition; M4 contained no additional image attachment. No new screenshot/IPA was generated.

### Home composition and compatibility

The existing source hid collectionView/customizeButton every layout and displayed a large bobbing logo. M4 restores the actual collection and customization entry, reduces the existing HomeLogo resource to static header branding, and adds `AMERenewedHomeHeader` in the already registered Home .m. It is a self-sizing global UICollectionView supplementary header above the unchanged tile sections, not another controller/root/collection. It scrolls with Home. An empty structural section with zero items retains the overview even when users hide all tiles; no fake item/card is inserted.

Overview: welcome/tagline, configured selected-instance hero (or “Your next world awaits”), account/name, canonical launch action, choose/manage profiles, Discover Minecraft, My Metallic status, Your Instances (up to three actual saved profiles with selected state) and See All. Existing news, announcements, release/snapshot cards, mods/shaders/modpack/multiplayer/background/version shortcuts remain in the original customizable grid below “Home cards”. Existing bottom Execute JAR/Choose Version tools and top account panel remain reachable. Their temporary extra chrome and original global navigation composition do not exactly match the final screenshots; global tab migration remains deferred.

Wide layouts pair hero and status at an implementation breakpoint of 820pt; compact widths stack them. Instance previews stack below 700pt. Accessibility text categories force stacking and disable the horizontal launch row. These are conservative source-layout choices, not screenshot pixel measurements. Uses M2 fonts/semantic colors/glass roles and M3 manager materials/tint; decorative material/icons are noninteractive. No permanent glow or new appearance setting. Static branding removes unnecessary motion; restored tiles' entry/edit animations respect Reduce Motion. Existing 60/76 navigation reservation and tab transitions are unchanged; the supported orientation masks remain landscape as before. Only a pre-existing closing brace swallowed by an orientation comment was repaired, not the orientation values.

Hero/status are fixed overview context outside HomeTileConfig; they are not draggable/resizable/customizable through the tile editor. This is explicit additional UI, not a replacement/migration of saved cards. Hidden/ordered/sized/custom-titled/icon/color/shortcut tiles remain exactly as stored; hiding the old profile tile does not hide the new overview. No saved layout is erased or converted and no second Home layout store exists. The redundant floating launch control is retained as a hidden mirror for compatibility; the hero is the single visible launch entry. Bottom scroll clearance now reserves only the remaining JAR/version toolbar.

### Actual state and callbacks

| UI | Source / callback | Boundary |
| --- | --- | --- |
| Selected profile/version and previews | Public `PLProfiles.current.profiles`, `selectedProfileName`, profile `lastVersionId`; immutable in-memory snapshots | These are saved/configured profiles, NOT proof of installed files or an active game. No directory enumeration or second database. Empty/invalid metadata renders the empty hero |
| Play | Hero action 0 → `norightLaunchTapped` → existing coordinator launchButton `sendActionsForControlEvents:UIControlEventTouchUpInside` once | No direct launch implementation or unsafe fallback. Owner button must exist and be enabled; no enabling override. Edit/presented-controller/input-burst guards. Owner handles all auth, downloads, JIT and launch checks |
| Launch label/enabled/busy presentation | Read canonical launch button title/enabled at refresh and again at tap; existing right-panel notification triggers updates | No hardcoded “Ready” or forced “Play Now” caption. 0.8s UI input-burst debounce/spinner only, not a claim of engine busy-state tracking. Ongoing busy state remains owner's enabled/title; repeated activation beyond debounce needs runtime testing |
| Choose instance | Hero action 1 → existing `bottomBarChooseVersionTapped` → coordinator `showVersionPicker` | Original selection function; no new backend |
| See All / empty Manage profiles | Action 4 → original `handleShortcutAction:kShortcutActionVersions` → unchanged `fix2PushTab:3 pushes:makeVC:` | Preserves Instances navigation stack and Home root |
| Empty Discover Minecraft | Action 2 → unchanged `fix2PushTab:1 pushes:DownloadViewController.class makeVC:`; legacy non-tab fallback presents existing downloader in nav | Catalogue navigation, not a new downloader or simulated install |
| Profile preview selection | Button-bound immutable name → existing `PLProfiles.current.selectedProfileName` setter | Setter persists and emits SelectedProfileChanged. No extra save call or engine preference mutation; invalid/missing profiles ignored |
| Account | Action 3 → existing `showAccountManagerModal`; username from public `BaseAuthenticator.current.authData` | No authentication implementation changes; missing account displays “Not signed in” |
| JIT and download information | Existing `AmeRightPanelStateNotification` fields and existing state labels; actual reported colors/progress/badge/visibility | Unreported state is unavailable. Idle does not show stale progress. No invented download counts/JIT predicate/performance metrics |
| Java / launcher version | Public profile javaVersion resolver, labeled “Java preference”; bundle CFBundleShortVersionString | Configured/automatic preference is NOT an active/installed runtime claim. No target = “Not reported”. App version is bundle metadata, including legacy account panel instead of its previous hardcoded version |
| Task Center / JAR / customize | Action 5 → original openDownloadCenterModal; original JAR/version toolbar, openCustomize and Done/editor callbacks retained | No new targets on those existing buttons; editing suppresses overview/account/toolbar navigation and launch |

Contained hidden rightPanelVC still uses addChild/addSubview/didMove and original zero-size collapse; no controller detachment, root replacement or state ownership change. Existing viewWillAppear/state request, account/SelectedProfileChanged/reset observers remain. The old logo foreground observer now requests real coordinator state, and one source-verified `ReloadProfileList` observer refreshes metadata after existing downloader/profile updates. Observer cleanup retained. Ordinary JIT/download updates change labels, not the full Home hierarchy. Snapshot rebuilding occurs on appearance/profile/list/version changes, never layout passes. Supplementary-size invalidation is coalesced for relevant metadata/title/account/type changes.

Profile buttons bind their name via an associated immutable value, avoiding stale index selection after data refresh. No new asynchronous card images/network requests; existing avatar/skin/news pipelines remain. Existing fix2PushTab, shortcut routes, HomeTileConfig save/load/default methods, ameHomeCardLayout handling, core long-press/drag/resize/save/Done methods remain byte-identical. New header controls do not enter tile long-press edit mode; while editing, overview and legacy toolbar/account controls are disabled and action forwards guard homeEditing.

### Validation and remaining risks

Executed: `git diff --check`; full normalized Objective-C grammar parse (expand NS_ENUM and remove parser-unknown __unused). Baseline had the swallowed orientation brace; current file parses without errors. This is grammar validation only, not UIKit SDK compilation. Local imports and existing CMake registration checked. Targeted AST/source assertions verify original persistence/editor/navigation functions, containment and observer counts; a single canonical launch dispatch with enabled gate/no force-enable/no direct fallback; real profile/setter mapping; M2/M3 use; no new preference keys/store or per-layout I/O. Entire UI diff reviewed; new component targets registered only during construction, observers cleaned up, constraints built once with one toggled width ratio. Temporary check script: /tmp/m4_verify.py.

Cumulative protected-file diff against `fe379d4f3723764ec0a8b6a6728368ac3492c4d8` allows only prior M2/M3 UI paths, this Home file and the three docs. All other tracked files, including LauncherRightPanelViewController.m, JavaLauncher/utils, JIT scripts, Java/Metal/framework binaries, signing, dependencies and workflows/Makefile are identical: **engine diff ZERO**. Source equality is not proof of runtime compatibility.

M1 remains BLOCKED (no Xcode/Apple SDK, unsafe CI substitutions, unverified packaging/dependencies); no workflow dispatched or IPA built. M3 remains PARTIAL (legacy system bars/search/chip consumers). All new Home runtime cases are PENDING. Specifically validate supplementary self-sizing/all-tiles-hidden behavior, Dynamic Type/long localization, rotation/narrow widths, existing landscape-only policy/global pill fit, edit/drag/resize hit testing, canonical modal/error/busy return behavior and repeated taps beyond the debounce. Native screenshot comparison, exact proportions, installed-target discovery, active runtime determination and gameplay are not verified. English fallback translations and retained bottom tools/old tile visuals need review. Legacy avatar/skin async behavior was retained, not newly validated.

Next milestone: **Instances and navigation customization.** Read this checkpoint and reuse the existing VersionManager/PLProfiles APIs and fix2PushTab routes. Preserve AI and all other destinations, core engine and 60/76 geometry while planning tab changes; do not re-audit M0–M3. Carry forward pending Home acceptance, M1 BLOCKED and M3 coverage limits. Fixed overview customization needs an explicit future decision before adding any layout preferences.

### M4 commit record

Implementation: `97884714f7144bf16368c041c1bead95f88e6a71` (`feat(ui): recreate functional Metallic Home dashboard`). Final documentation commit records this SHA; resolve its own SHA with `git log -1 --format=%H -- docs/METALLIC_RENEWED_PROGRESS.md`. Git access was verified with the existing GH CLI credentials via command-scoped `git -c credential.helper='!gh auth git-credential'`; no credentials or Git configuration were saved. M4 stays PARTIAL, M1 BLOCKED and device acceptance PENDING. Next: Instances and navigation customization.


## M5 — Instances and safe global navigation (2026-10-27)

Status: **PARTIAL**. Production UI source changes implemented; native compilation, rendered fidelity and device interaction are not validated. Verified clean feature checkout and fetched feature/protected baseline before editing: feature `59faa8bb812e561b576f7ac755b76890be73738e`, baseline `fe379d4f3723764ec0a8b6a6728368ac3492c4d8`. No user changes were present. No main/baseline update, force push, workflow dispatch or build repair.

### Changed files and actual presentation

- `ios-app/Natives/VersionManagerViewController.m`: same native collection/controller/data model. Adds a self-sizing, scrolling overview with Instances title, actual saved-profile count and New Instance. Header stacks at compact widths/accessibility sizes, so it cannot consume a fixed short landscape viewport. Game directories stay reachable with zero profiles; profile section shows original empty guidance. New opens the existing native Downloads tab, never hidden Home content.
- `VMVersionCardCell`: M2 fonts/semantic colors, M3-managed native material, quiet rounded cards and selected checkmark/border. Real name, lastVersionId, cached isolation flag, existing loader icon and lastPlayed formatter; no installed/runtime/performance claims. One/two/three columns according to available width (single at accessibility sizes), font-based row heights, real 44-point More control. More captures a copied profile name rather than a reused index path; callback cleared on reuse and weakly captures controller. VoiceOver selected traits and Profile actions custom action; original tap still selects the profile then opens ProfileSettings.
- `VMGameDirCell` presentation: scaled fonts, semantic border, clear inner fill, correct selected accessibility state, live accessibility value from the size label. Directory cache, in-flight dedup, background enumeration and identity-based visible-cell update remain unchanged. Base cell retains rounded content clipping and cached shadowPath; subtle native highlight feedback respects Reduce Motion and resets on reuse.
- Section headers use scalable text/count without a second independent blur overlay. Removed the Instances `BackgroundUIEffectChanged` reload observer/handler: M3 already refreshes registered cell material/tint, so slider ticks no longer cause collection rebuilding. Existing accent/profile/reload observers and dealloc cleanup remain; no new controller observers or preference keys.
- `ios-app/Natives/HomeTopNavView.h`: stable `AMELauncherTab` constants and `AMEPrimaryDestination` with two inline translation helpers. No new source registration.
- `ios-app/Natives/HomeTopNavView.m`: five visible items in reference order. `selectedIndex` retains INTERNAL semantics for existing callers/notifications; root owns selection, without optimistic tap highlighting. Equal tap areas, icon-only compact/accessibility presentation with full accessibility labels, existing theme/material/Reduce Motion behavior. Height stays 60.
- `ios-app/Natives/AmeRootTabController.m`: uses named constants in existing factory, unchanged controller order/wrappers. Routes five visible actions; adds a 44-point native Tools menu with actual AI entry. Appearance is a functional settings sheet, leaving the underlying stack/tab intact. Root reservation stays 76; Tools stays alongside the pill. Initial and subsequent selection synchronizes the pill and Tools selected state.
- `ios-app/Natives/LauncherNewsViewController.m`: one-line correction of the existing M4 global header factory to `boundarySupplementaryItemWithLayoutSize:elementKind:alignment:` (the same public boundary-item selector used by native section headers). M5 overview uses that selector too. No Home callbacks, state, layout stores, containment or launch forwarding changed. Apple documentation fetch was unavailable (HTTP 403); this is source/API review, not native SDK verification.
- The three continuity documents: this record, implemented UI specification and M5 acceptance matrix. No other paths changed in M5.

### Native actions and persistence preserved

| Control | Actual callback / native state / persistence |
| --- | --- |
| New instance | Overview `createTapped` → weak `onCreate` → unchanged `createNewVersion` semantics → `AMELauncherTabDownloads` (1); standalone legacy ShowDownloadPage fallback retained |
| Profile card | Existing `collectionView:didSelectItemAtIndexPath:` → `editProfile:` → existing `PLProfiles.current.selectedProfileName` setter (save + SelectedProfileChanged) → `ProfileSettingsViewController.profileName` push |
| Profile More / VoiceOver actions / long press | Copied profile identity → original `showProfileActions:`; Select/Edit/Delete options unchanged |
| Profile deletion | Original `deleteProfile:`: last-profile restriction, native cancel/confirm, existing profile-only removal/selection/save/UI refresh unchanged |
| Directory selection/create/actions/delete | Original `switchGameDirTo:`, `showCreateGameDirAlert`, `createGameDirWithName:`, `showGameDirActions:`, `confirmDeleteGameDir:`, `deleteGameDir:` and safeguards byte-identical; UI-only tap/transition guards added at collection entry points |
| Renderer / graphics API | Existing `ProfileSettingsViewController` entry retained; VersionManager renderer/graphics setup/resolvers/selectors unchanged, including `renderer`, `graphicsApi` and global fallback semantics. No automatic engine switch |
| Mods/Shaders/Resource Packs/Data Packs/Worlds | Existing profile settings access and all five VersionManager `open…Manager` methods unchanged; no fake quick-action section |
| Home launch / profile refresh | Home action/state paths and original right-panel coordinator untouched (one Home header factory selector corrected). Canonical selected-profile setter/notification remains the source for Home and next launch |
| Back/Done/Close | Existing nav controllers; `ameOwnExitItemOfNav:`, `ameFloatingDoneTapped`, nav-delegate refresh and Home reset unchanged. Appearance uses its own existing `closeTapped` dismissal |

New UI action guards reject duplicate presentations/selection while the native navigation controller is transitioning; they do not alter model operations. No direct game launch, JIT logic or profile/renderer storage implementation was added.

### Visible navigation contract (do not renumber internal tabs)

| Visible destination | Existing native destination |
| --- | --- |
| Home | Internal 0, existing Home reset and Home UINavigationController |
| Instances | Internal 3, VersionManagerViewController stack |
| Downloads | Internal 1, DownloadViewController stack |
| Appearance | BackgroundSettingsViewController in a form-sheet UINavigationController; actual wallpaper, glass style, UI Blur, Panel Opacity and scoped Reset to Recommended. No sixth internal slot |
| Settings | Internal 4, LauncherPreferencesViewController stack; System/Light/Dark remains here |
| Tools → AI (secondary) | Internal 2, AISessionListViewController stack; Tools selected, no unrelated primary pill highlighted |

While the Appearance sheet is visible, the underlying tab remains selected, as it remains the sheet's return destination. Appearance is temporarily an action route, not a selected tab. Screenshot-accurate consolidated Appearance/theme/intro composition is deferred to the Settings/Appearance milestone; no empty page or duplicate settings store was added.

Targeted numeric-consumer review: Home's `fix2PushTab:0/1/3` (multiplayer/Downloads/modpack/Instances/mods/shaders/See All), SceneDelegate language rebuild Settings=4, legacy LauncherMenu/AmeTabBar internal notifications, root factory/setSelectedIndex, and Instances New=1. Internal values stay 0 Home / 1 Downloads / 2 AI / 3 Instances / 4 Settings. Only root factory and New use new named constants; unchanged legacy consumers remain valid. Root does not replace Home content, pop unrelated stacks for normal tab changes or add another root/tab controller. The former Help pill had no handled destination; functional AI Tools replaces that unused item.

### Verification and protected diff

Executed `git diff --check`; Tree-sitter Objective-C grammar parse for the four changed .m files and HomeTopNavView.h (NS_ENUM expanded for parser only), header/import/source-inclusion review, duplicate-method and new-selector/target checks. Used temporary `/tmp/m5_verify.py` and existing temporary parser tooling; no test dependency or source registration added to the app.

Compared native profile edit/delete/select/action-sheet, directory operations, renderer/graphics resolver/selectors, load/cache/async enumeration and lifecycle methods against M4: unchanged bodies, except UI entry-point guards and New's equivalent named tab constant. Cell data/configuration path differs only by identity-bound More callback. Existing animator, Home reset, floating Done/own-exit/navigation delegate/game-orientation bodies unchanged. Home differs only by the boundary-header factory selector correction; tile preferences/editor and canonical Play forwarding are untouched by M5. Source checks do not establish that callbacks physically work on device.

Compiled and executed the ACTUAL inline routing helpers as C with Foundation integer typedefs/NS_ENUM normalized: stable numeric slots, five visible mappings, Appearance/AI sentinel behavior, reverse mapping round trips and invalid destinations passed under gcc `-Wall -Wextra -Werror`. UIKit APIs were not compiled or executed. New menu API floor is iOS 14, matching the existing CMake/Makefile deployment floor; native materials use the existing guarded resolver.

Cumulative baseline comparison allows only eleven approved UI files (M2/M3/M4 plus HomeTopNavView.h, AmeRootTabController.m and VersionManagerViewController.m) and the three docs. Full Git content diff outside that allowlist is zero. **ENGINE DIFF: ZERO**: JIT, Java, Metal, game launch, auth, framework binaries, native dependencies, signing, entitlements, Makefile/workflows and protected baseline unchanged. No new appearance/game preference keys or defaults.

### Limitations and exact continuation

M1 remains **BLOCKED**: no Xcode/Apple SDK toolchain; existing CI substitutes upstream source/patches protected inputs; dependencies/framework and JIT packaging unverified. No workflow run, IPA build, simulator or physical-device test. M3 remains **PARTIAL** for legacy bars/search/chips; M4 remains **PARTIAL** for Home visual/interaction acceptance. Historical Alpha 1.2 gameplay is not M5 runtime evidence.

M5 risks/PENDING: native type/link validation; self-sizing global/empty supplementary headers; typography/long translations and extreme Dynamic Type; compact pill and Tools/menu fit; VoiceOver activation/custom-action focus; supported rotation; rapid tab/modal/push interactions; material contrast across wallpaper/theme/opacity; profile edit/delete/directory safety on disposable data; Home/JIT live-state and real launch after navigation. No dedicated Instances screenshot was supplied with M5; established card/material references and saved specification guide styling, not a claimed rendered match. English fallback strings are localized at call sites; translation coverage is pending. Existing landscape policy is unchanged. Directory metadata invalidation behavior remains native; do not broaden this into game-data refactoring.

**Next milestone: Downloads UI customization.** Start with progress, then existing `DownloadViewController` and only its directly relevant UI consumers; reuse stable navigation constants, M2 styles and M3 material settings. Preserve real downloader/install logic, task/error state, AI route, profile storage and all pending native acceptance gates. Do not re-audit M0–M4 or repair the build system without separate authorization.

M5 public-selector review: both the Instances overview and existing Home global header now call `NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:elementKind:alignment:`. The Home change is exactly one factory-selector correction; native SDK/type checking remains BLOCKED.


### M5 commit record

Implementation: `cefd07b4bfd60dcb21a0e1d2afaabdc76850e77f` (`feat(ui): polish Instances and native navigation`), parent M4 `59faa8bb812e561b576f7ac755b76890be73738e`. This documentation bookkeeping commit records the implementation SHA; resolve the final checkpoint with `git log -1 --format=%H -- docs/METALLIC_RENEWED_PROGRESS.md`. Publication is restricted to `feat/renewed-uikit-home` using the existing command-scoped Git credential helper and a normal fast-forward push; no saved credentials/configuration. No baseline/main update. M5 PARTIAL, native build BLOCKED, device tests PENDING. Next: Downloads UI customization.
