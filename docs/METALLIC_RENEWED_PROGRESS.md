# Metallic Renewed progress

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
