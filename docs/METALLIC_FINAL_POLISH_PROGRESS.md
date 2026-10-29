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
