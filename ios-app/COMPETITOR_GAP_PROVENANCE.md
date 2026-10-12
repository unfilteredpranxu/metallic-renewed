# COMPETITOR-GAP: Synchronization of Differences "Beyond the Renderer" — Sources and Licensing

This document records each item copied from a competitor's repository into `tree510` in this round (beyond the renderer), along with its source, license, and rollback method.
★ This round was **not pushed, merged, filed as an issue, or submitted as a PR**; all changes are local commits.

## Comparison Baseline and Method

- Our tree: `D:\CTF\_510src\tree510` (HEAD `899e51ec9`, derived from remote `upstream`).
- Competitor reference: `D:\CTF\_uibuild\repo` = **`Gsjsjzhznsz/Air-Minecraft-iOS-Launcher`**, branch `ui/e-design-1`, commit
  `50c59ee6bfc8e14bcbf3de3abee7a2f824209ba5` (also accessible in tree510 through `remotes/fork/ui/e-design-1`).
- The two trees have **no common ancestor** (unrelated histories). The competitor's repository uses **CRLF**, so all content comparisons were made after
  **LF normalization + MD5** (otherwise 342 false differences would be reported; only 82 actual differences were observed).
- **NG-GL4ES (ZalithLauncher2)** was **excluded** as requested; it was not introduced in this round.

## License

The competitor's repository and ours are both licensed under **GNU GPL-3.0** (`LICENSE` is identical in both; each is a fork of Amethyst-iOS-MyRemastered).
Therefore, importing files from the same-source project complies with its license; this document records attribution.

## Items Imported (This Commit)

| Path | Source | License | Original MD5 (before import) | Description |
|---|---|---|---|---|
| `intentprobe/project.yml` | Competitor repository `ui/e-design-1` @ `50c59ee6b` | GPL-3.0 | `3ef81565f3f4ba253710803eb97a971d` | XcodeGen project description (standalone probe app, `bundleIdPrefix` `com.probe`) |
| `intentprobe/Sources/App.swift` | Same | GPL-3.0 | `230a33897b60eca9c4ed0e18217ed10d` | Probe app entry point (SwiftUI) |
| `intentprobe/Sources/AmethystIntents.swift` | Same | GPL-3.0 | `75bd1b04b96465de3fe272d4eac0ab00` | App Intents / Siri Shortcuts reference (`LaunchVersionIntent` / `SetRendererIntent` / `AmethystShortcuts`) |
| `METAL_TUTORIAL.txt` | Same | GPL-3.0 | `1a6f73c84bca4e239bf231624b121cbd` | User documentation for Metal (metallum) integration |

### Why `intentprobe` Was Imported (The Key Reason — Not Copying for Its Own Sake)

Our tree **already had** `.github/workflows/intentprobe.yml` (identical to the competitor's; see commit `d7619d684`, "Add fork-specific files missed during the base replacement"). Its `working-directory: intentprobe` and `xcodegen generate` **pointed to a directory that did not exist in our tree** — the CI workflow referenced an empty path. Adding `intentprobe/` does only two things:

1. Prevents the existing workflow from referencing a nonexistent path (removes a dangling reference without adding any automation).
2. Keeps the competitor's probe source for "checking whether App Intents metadata can be generated in an unsigned build" in the tree as reusable evidence/reference
   **if Siri Shortcuts support is implemented in the future**.

It **does not participate in app packaging at all**: `intentprobe/` is a standalone XcodeGen project (`xcodegen generate` creates a separate
`.xcodeproj`); it is not referenced by `Natives/CMakeLists.txt`, the `Makefile`, or any payload/package manifest.
Therefore, **no `CMakeLists` changes or package-manifest entries are needed** — this is the fundamental reason it is "low risk."

### Rollback

```bash
rm -rf tree510/intentprobe tree510/METAL_TUTORIAL.txt
git -C tree510 revert <this-commit>     # or git checkout <prev> -- intentprobe METAL_TUTORIAL.txt
```

## Recorded but **Intentionally Not Copied/Replaced** (Different Builds with the Same Names · Previous Strategy Retained)

The following binaries have the same names but different builds, produced from each side's own source branches. Their MD5 hashes differ, but this is **not a capability gap**.
Per the established strategy, **they are recorded without forced replacement** (replacement would disrupt our stabilized build line and device validation).

| File | Ours | Competitor | Conclusion |
|---|---|---|---|
| `Natives/resources/Frameworks/libmetallum.dylib` | 221856 B | 231576 B | Built separately (competitor includes its agent/natives line) — do not replace |
| `Natives/resources/Frameworks/libshaderc.dylib` | 9384224 B | 8522336 B | Built separately — do not replace |
| `Natives/resources/Frameworks/libspirv-cross-c-shared.0.dylib` | 2679856 B | 3475240 B | Built separately — do not replace |
| `Natives/resources/Frameworks/liblwjgl.dylib` | 305216 B | 302104 B | Built separately — do not replace |
| `Natives/resources/Frameworks/liblwjgl_stb.dylib` | 464472 B | 406224 B | Built separately — do not replace |
| `JavaApp/libs/others/metallum_agent.jar` | 6852035 B | 539580 B (plus a redundant 4106015 B copy in the root) | Our agent is newer and larger (multi-version branch); do not replace |
| Root `metallum_agent.jar` | None | 4106015 B | Competitor's **stale redundant copy**; ours is loaded from `JavaApp/libs/others/` (`JavaLauncher.m:1921`); do not copy |
| `Natives/resources/Frameworks/libopenal.dylib` | None (**generated at build time**) | 4112728 B (byte-for-byte copy of `libopenal_impl.dylib`) | Our Makefile creates the same-name shim from `libopenal_impl.dylib` with `-reexport_library` — **not a gap**; do not copy |
