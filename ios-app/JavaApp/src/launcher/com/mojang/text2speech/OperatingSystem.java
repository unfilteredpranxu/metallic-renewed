package com.mojang.text2speech;

/**
 * Task 73: Reproduces the OperatingSystem enum from the real text2speech 1.19.12 library.
 *
 * ModernFix (suppress_narrator_stacktrace, bundled with Fabulously Optimized
 * v14.x) has a GameNarratorMixin that references OperatingSystem.get()/ordinal().
 * Its generated switch-map class calls values(); without this enum, the stub
 * package throws at runtime:
 * NoClassDefFoundError: com/mojang/text2speech/OperatingSystem。
 *
 * Real detection logic (confirmed by decompiling the 1.19.12 jar): lowercase
 * os.name, then contains("linux") → LINUX, contains("win") → WINDOWS, and
 * contains("mac") → MAC_OS; all others are UNSUPPORTED. On iOS, os.name is
 * "Mac OS X", so the dummy narrator path is used and no platform narrator is
 * constructed. The detectWith field is retained for API shape only; it has no callers.
 */
public enum OperatingSystem {
    LINUX("linux"),
    WINDOWS("win"),
    MAC_OS("mac"),
    UNSUPPORTED("");

    private final String detectWith;

    OperatingSystem(final String detectWith) {
        this.detectWith = detectWith;
    }

    public static OperatingSystem get() {
        final String name = System.getProperty("os.name", "").toLowerCase();
        if (name.contains("linux")) {
            return LINUX;
        }
        if (name.contains("win")) {
            return WINDOWS;
        }
        if (name.contains("mac")) {
            return MAC_OS;
        }
        return UNSUPPORTED;
    }
}
