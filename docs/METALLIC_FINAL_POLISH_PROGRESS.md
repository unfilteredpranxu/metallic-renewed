# Metallic final polish and reliability

## Protected baseline
Application: a3f24f56fb3169e031678c19184742977e7e3e55 (recoverable Git object). User reports Minecraft26.2/Java25/Fabric/StikJIT/Metallum/dyld bypass and singleplayer rendering on A16/iPadOS27.2; this is USER-REPORTED DEVICE EVIDENCE for those scenarios, not an independent agent/device test.
Build40827817707: https://github.com/unfilteredpranxu/metallic-renewed/actions/runs/40827817707 . IPAartifact12877753192: https://github.com/unfilteredpranxu/metallic-renewed/actions/runs/40827817707/artifacts/12877753192 . Filename com.tokyxkai.metallic-1.2.0-ios.ipa;261756022bytes;SHA2561e644dd86cb7fb5f36e798fd494b0f39b184fd7e3fbfc567dad8512ca2f5e756. Existing ldid sideload signing, no provisioning supplied. Original artifact untouched.
New isolated branch feat/metallic-final-polish-stability created from latest restoration remote (including diagnostic-only reports). Restoration/main/baseline refs not written. Three pending UI fixes carried without discard: stable Settings owner for System details, rejected-transition callback handling, Dynamic Type card/controls sizing.

## Scope
Keep engine/JIT/StikJIT/dyld/Java/JVM/Metallum/ANGLE/MobileGlues/shaders/auth/signing/runtime/profile semantics untouched. Download-reliability changes explicitly authorized separately; preserve directories, target-profile snapshots, hashing, cancellation and installer behavior. UI sound preferences are additive opt-in only. No orientation-policy changes. Screenshots and docs/METALLIC_REFERENCE_GEOMETRY.json govern iPad composition. No intro per previous explicit user instruction.

## Milestones
0 baseline: DONE (source/build recoverable, isolated branch, artifact recorded).
1 Settings/Appearance repairs: ACTIVE.
2 Home feed removal/branding/logo: TODO.
3 Responsive layout: TODO.
4 Visual polish: TODO.
5 Motion/sound: TODO.
6 Download reliability: TODO;58% cause UNCONFIRMED, no measurements yet.
7 Final review: TODO.
8 Native candidate: TODO; build exact new source, never baseline a3 again.

All new simulator/device/performance/download measurements NOT RUN. Physical user baseline evidence above is historical for new changes. Preserve all90 existing settings descriptors/bindings; additional sound controls must not replace them. No production-readiness claim.

### Milestone1 source changes
Removed the hard-coded black accent-value background and oversized100/136/146 reference-row minima; retained content-driven minimum56 and existing descriptor factories. Added narrowly scoped missing-JIT-label/description fallbacks, preserving actual options and enable rules. Appearance opens at its true adjusted top rather than inheriting an offset. Pending UI route fixes saved in8cfeb080. All90 original descriptors/getters/setters remain unchanged; native/device validation pending.

### Milestone2 (in progress)
Legacy feed data source now permanently empty; header/hero/status/Your Instances remain. Neither saved Home key is deleted or reset. Home no longer reads/writes saved feed layouts on load or starts Mojang manifest/news/promotional requests; retired loaders are no-ops even after notifications. More retains Mods/Shaders/Modpack/Wallpaper/Multiplayer through original handleShortcutAction callbacks8–12. App updater startup/manual UI now explicitly says updates not configured rather than querying the unrelated Amethyst fork; no official Metallic release channel has been verified (API blocked), so no nonexistent endpoint substituted. Existing update service implementation retained behind explicit channel gate. Chrome logo RGB black background confirmed; alternate transparent vector asset is a DIFFERENT logo and not substituted. Transparency edit in progress. Branding inventory and complete About refinement pending.

Logo: existing Current asset is RGB with baked black. Existing Vector is a different pixel logo. Added a separate RGBA background-removal derivative of the original chrome (image editing tool), preserving Current and all AppIcon assets. New header asset has genuinely transparent corners/hole and opaque dark chrome pixels. Recognizable sculpture retained; edited pixels are NOT claimed bit-identical. Light/dark wallpaper/device visual acceptance pending.
