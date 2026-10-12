package com.mojang.text2speech;

public interface Narrator {
    void say(final String msg, final boolean interrupt);

    /**
     * Three-arg variant introduced in the MC 26.3 series (26.3-pre-1 call
     * sites pass a float volume argument). Kept alongside the legacy 2-arg
     * overload because the same launcher.jar must satisfy older MC versions
     * whose Narrator interface only declares the 2-arg form.
     */
    void say(final String msg, final boolean interrupt, final float volume);

    void clear();

    boolean active();

    void destroy();

    /**
     * Task 73 (root-cause crash fix): The empty narrator instance from the real text2speech 1.19.12 API.
     *
     * MC 26.2 + Fabulously Optimized v14.1.0 crash chain:
     *   Minecraft.<init>:733 → new GameNarrator → class verification resolves
     *   the catch-block type injected by ModernFix's
     *   (suppress_narrator_stacktrace) GameNarratorMixin:
     *   Narrator$InitializeException → the stub lacks this symbol →
     *   NoClassDefFoundError: com/mojang/text2speech/Narrator$InitializeException。
     *
     * ModernFix's mixin also references Narrator.EMPTY (the fallback when narrator
     * initialization fails) and the OperatingSystem enum. All three must be
     * provided together; otherwise the next NoClassDefFoundError/NoSuchFieldError
     * will occur at runtime. EMPTY matches the real library: all methods are
     * no-ops and active()=false.
     */
    Narrator EMPTY = new NarratorDummy();

    /**
     * Task 73: Narrator initialization exception matching the real 1.19.12 API.
     * The real class is public class InitializeException extends Exception,
     * with (String) and (String, Throwable) constructors. Interface member
     * classes are implicitly public static, matching the real bytecode access
     * flags (public super).
     */
    class InitializeException extends Exception {
        public InitializeException(final String message) {
            super(message);
        }

        public InitializeException(final String message, final Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * Task 73: Fatal narrator exception from the real 1.19.12 API (a
     * RuntimeException with only a (String) constructor). There are no known
     * callers (client 26.2/26.3 and ModernFix do not reference it); this is an
     * API-completeness safeguard so future mods or MC versions have the symbol
     * if the real getNarrator() throws when platform narrator initialization fails.
     */
    class FatalException extends RuntimeException {
        public FatalException(final String message) {
            super(message);
        }
    }

    static Narrator getNarrator() {
        return new NarratorDummy();
    }

    static void setJNAPath(String sep) {
        System.setProperty("jna.library.path", System.getProperty("jna.library.path") + sep + "./src/natives/resources/");
        System.setProperty("jna.library.path", System.getProperty("jna.library.path") + sep + System.getProperty("java.library.path"));
    }
}
