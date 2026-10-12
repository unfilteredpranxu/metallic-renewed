package net.kdt.pojavlaunch;

import java.beans.Beans;
import java.io.*;
import java.lang.reflect.Field;
import java.util.*;
import java.util.concurrent.*;

import org.lwjgl.glfw.CallbackBridge;
import org.lwjgl.glfw.GLFW;

import net.kdt.pojavlaunch.uikit.*;
import net.kdt.pojavlaunch.utils.*;
import net.kdt.pojavlaunch.value.*;

public class PojavLauncher {
    private static float currProgress, maxProgress;

    public static void main(String[] args) throws Throwable {
        // Skip calling to com.apple.eawt.Application.nativeInitializeApplicationDelegate()
        Beans.setDesignTime(true);
        try {
            // Some places use macOS-specific code, which is unavailable on iOS
            // In this case, try to get it to use Linux-specific code instead.
            com.apple.eawt.Application.getApplication();
            Class clazz = Class.forName("com.apple.eawt.Application");
            Field field = clazz.getDeclaredField("sApplication");
            field.setAccessible(true);
            field.set(null, null);
            sun.font.FontUtilities.isLinux = true;
            System.setProperty("java.util.prefs.PreferencesFactory", "java.util.prefs.FileSystemPreferencesFactory");
        } catch (Throwable th) {
            // Not on JRE8, ignore exception
            //Tools.showError(th);
        }

        Thread.currentThread().setUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {

            public void uncaughtException(Thread t, Throwable th) {
                th.printStackTrace();
                System.exit(1);
            }
        });

        try {
            // Try to initialize Caciocavallo17
            Class.forName("com.github.caciocavallosilano.cacio.ctc.CTCPreloadClassLoader");
        } catch (ClassNotFoundException e) {}

        if (args[0].equals("-jar")) {
            UIKit.callback_JavaGUIViewController_launchJarFile(args[1], Arrays.copyOfRange(args, 2, args.length));
        } else {
            launchMinecraft(args);
        }
    }

    public static void launchMinecraft(String[] args) throws Throwable {
        // Args for Spiral Knights
        System.setProperty("appdir", "./spiral");
        System.setProperty("resource_dir", "./spiral/rsrc");

        String sizeStr = System.getProperty("cacio.managed.screensize");
        System.setProperty("glfw.windowSize", sizeStr);
        String[] size = sizeStr.split("x");
        MCOptionUtils.load();
        MCOptionUtils.set("fullscreen", "false");
        MCOptionUtils.set("overrideWidth", size[0]);
        MCOptionUtils.set("overrideHeight", size[1]);
        // Unlock the frame rate (disable VSync and remove the maxFps limit):
        // MC defaults to enableVsync=true, which locks the frame rate to the display refresh
        // rate (60 Hz locks to 60, and 120 Hz ProMotion locks to 120).
        // MC also defaults to maxFps=120, which remains a limit even with VSync disabled.
        //
        // When the launcher preference video.disable_game_vsync is enabled
        // (passed through the POJAV_DISABLE_VSYNC=1 environment variable):
        // 1. Force enableVsync=false so MC no longer calls glfwSwapInterval(1) to request VSync.
        // 2. Force maxFps=260; MC 1.16+ treats maxFps>=260 as "unlimited".
        //
        // Key fix for ineffective FPS unlocking:
        //   The previous value was maxFps=0, but MC accepts values from 10 to 260 (default 120).
        //   maxFps=0 does not mean "unlimited": MC 1.16+ ignores zero as invalid and continues
        //   using the old options.txt value or the default 120, keeping the frame rate capped at 120.
        //   MC 1.16+ has a special check: if (maxFps >= 260), treat it as unlimited.
        //   Therefore, use maxFps=260 (or higher) for "unlimited".
        //
        //   On older MC 1.8–1.15 versions, maxFps is absent or behaves differently, so this
        //   setting is ignored and unlocking relies entirely on the native eglSwapInterval(0) hook.
        //
        // MC 26.2+ compatibility (key fix):
        //   MC 26.2 may have renamed these options. Write all likely names for compatibility:
        //   - maxFps (MC 1.16–1.21): frame-rate limit
        //   - maxFramerate (possible new name in MC 26.2+): frame-rate limit
        //   - enableVsync (all versions): VSync toggle
        //   - framerateLimit (possible alternative in MC 26.2+): frame-rate limit
        //
        // Effects:
        // - Vulkan renderer (MoltenVK): LWJGL uses VK_PRESENT_MODE_IMMEDIATE_KHR when creating
        //   the swapchain; MoltenVK presents without waiting for vblank, allowing frame rates
        //   above the display refresh rate and reducing input latency.
        // - GL renderers (ANGLE Metal): eglSwapInterval(0) unblocks the render thread, but Core
        //   Animation still composites at the display refresh rate. Actual FPS does not exceed
        //   the refresh rate, but render-thread throughput improves.
        //
        // Use set (not setDefault) to force these values on every launch.
        // To restore in-game VSync and frame-rate limits, disable this toggle in launcher settings.
        if ("1".equals(System.getenv("POJAV_DISABLE_VSYNC"))) {
            MCOptionUtils.set("enableVsync", "false");
            // maxFps=260: MC 1.16+ treats maxFps>=260 as unlimited.
            // (Previously, 0 was ignored as invalid and maxFps=120 still capped the frame rate.)
            MCOptionUtils.set("maxFps", "260");
            // MC 26.2+ compatibility: the option may have been renamed maxFramerate or framerateLimit.
            MCOptionUtils.set("maxFramerate", "260");
            MCOptionUtils.set("framerateLimit", "260");
            // MC 1.21.8+ compatibility: the inactivityFpsLimit option (InactivityFpsLimit enum).
            //
            // Key fix for another cause of ineffective FPS unlocking:
            // MC 1.21.8+ introduced inactivity frame-rate limiting (inactivityFpsLimit),
            // which defaults to "afk":
            //   - 30 FPS after 1 minute without input
            //   - 10 FPS after 10 minutes without input
            //   - 10 FPS when the window is minimized
            // This severely limits FPS when users switch apps or stop interacting on iOS,
            // even if VSync and maxFps limits are disabled.
            //
            // The InactivityFpsLimit enum has two values:
            //   - "afk" (default): limit FPS while idle
            //   - "minimized": limit FPS only while minimized (10 FPS)
            //
            // With "minimized", idle users are not throttled; FPS is limited only when the
            // window is minimized, which almost never happens on iOS. Together with disabled
            // VSync and maxFps=260, this fully unlocks the frame rate.
            //
            // Older MC versions (1.21.7 and earlier) do not recognize this option; it is ignored.
            MCOptionUtils.set("inactivityFpsLimit", "minimized");
            // Diagnostic log: print the frame-rate options written above.
            System.out.println("[PojavLauncher] VSync disabled, maxFps/maxFramerate/framerateLimit set to 260");
            System.out.println("[PojavLauncher]   enableVsync=" + MCOptionUtils.get("enableVsync"));
            System.out.println("[PojavLauncher]   maxFps=" + MCOptionUtils.get("maxFps"));
            System.out.println("[PojavLauncher]   maxFramerate=" + MCOptionUtils.get("maxFramerate"));
            System.out.println("[PojavLauncher]   framerateLimit=" + MCOptionUtils.get("framerateLimit"));
            System.out.println("[PojavLauncher]   inactivityFpsLimit=" + MCOptionUtils.get("inactivityFpsLimit"));
        }
        // Default settings for performance
        MCOptionUtils.setDefault("mipmapLevels", "0");
        MCOptionUtils.setDefault("particles", "1");
        MCOptionUtils.setDefault("renderDistance", "2");
        MCOptionUtils.setDefault("simulationDistance", "5");
        // Disable OIT (Order-Independent Transparency): renderpearl's
        // oit_transmittance_flat_clouds Vulkan pipeline fails to compile on MoltenVK/A11 GPUs
        // and crashes. graphicsMode: 0=Fast, 1=Fancy, 2=Fabulous (OIT).
        // Matches Ynnyny repository commit be74cd4.
        MCOptionUtils.setDefault("graphicsMode", "0");
        MCOptionUtils.setDefault("transparency", "0");
        
        MCOptionUtils.save();

        // Task 104 (evidence loop for the MC 26.3 30 FPS issue): verify the persisted file.
        // The in-memory get() above confirms only the in-memory state; re-read the options.txt
        // that MC will load so the next device log can confirm whether the value reached the
        // correct file. In the known failure, MC 26.3 ran in AFK mode (confirmed SHORT_AFK=30 FPS)
        // even though the launcher wrote "minimized"; the state diverged at this point.
        if ("1".equals(System.getenv("POJAV_DISABLE_VSYNC"))) {
            System.out.println("[PojavLauncher] Task104 on-disk verification: "
                + "inactivityFpsLimit=" + MCOptionUtils.getFromFile("inactivityFpsLimit")
                + " maxFps=" + MCOptionUtils.getFromFile("maxFps")
                + " enableVsync=" + MCOptionUtils.getFromFile("enableVsync"));
        }

        // Tell renderpearl to skip OIT pipeline compilation.
        System.setProperty("com.mojang.renderpearl.disableOIT", "true");
        System.setProperty("com.mojang.renderpearl.skipOIT", "true");
        System.setProperty("com.mojang.renderpearl.forceNoOIT", "true");

        // Setup Forge splash.properties
        File forgeSplashFile = new File(Tools.DIR_GAME_NEW, "config/splash.properties");
        if (System.getProperty("pojav.internal.keepForgeSplash") == null) {
            forgeSplashFile.getParentFile().mkdir();
            if (forgeSplashFile.exists()) {
                Tools.write(forgeSplashFile.getAbsolutePath(), Tools.read(forgeSplashFile.getAbsolutePath().replace("enabled=true", "enabled=false")));
            } else {
                Tools.write(forgeSplashFile.getAbsolutePath(), "enabled=false");
            }
        }

        // Set the LWJGL Vulkan native-library name only when the Vulkan renderer
        // is explicitly selected, so it does not override the OpenGL libname
        // that JavaLauncher.m sets for ANGLE/MobileGlues/GL4ES.
        //
        // Pass the bare name "MoltenVK". LWJGL's Platform.mapLibraryName (macOS
        // branch) uses the regex
        //     (?:^|/)lib\w+(?:[.]\d+)*[.]dylib$
        // to determine whether libname is already a dylib filename. Matches are
        // returned unchanged; otherwise System.mapLibraryName adds the "lib"
        // prefix and ".dylib" suffix. The bare name does not start with "lib",
        // so it becomes "libMoltenVK.dylib", matching the on-disk filename.
        //
        // Correct the old comment: it claimed that passing "libMoltenVK.dylib"
        // would wrap it again as "liblibMoltenVK.dylib.dylib". In fact, that name
        // matches the regex above ("\w" includes "MoltenVK") and is returned unchanged.
        // The real problem is libraries with hyphens: "\w" does not include '-',
        // so "libMobileGL-gles.dylib" is misidentified and wrapped as
        // "liblibMobileGL-gles.dylib.dylib". Passing bare names works consistently.
        String renderer = System.getenv("AMETHYST_RENDERER");
        if ("libMoltenVK.dylib".equals(renderer) || "vulkan".equals(renderer)) {
            System.setProperty("org.lwjgl.vulkan.libname", "MoltenVK");

        // Sanity check: the LWJGL jar on the classpath must match the version the
        // native launcher selected (AndroidLauncher sets -Dpojav.lwjgl.version and
        // builds the classpath from libs/lwjgl-<version>/). Otherwise the wrong
        // LWJGL set would be used, e.g. 3.3.3 when 3.4.1 (real SDL3 bindings) is
        // required by MC 26.3+. org.lwjgl.Version comes from whichever lwjgl jar
        // the classpath resolved first.
        String activeLwjgl = System.getProperty("pojav.lwjgl.version");
        if (activeLwjgl != null) {
            try {
                String versionStr = Class.forName("org.lwjgl.Version").getMethod("getVersion").invoke(null).toString();
                System.out.println("[PojavLauncher] LWJGL selected by launcher: " + activeLwjgl
                    + ", LWJGL on classpath: " + versionStr);
            } catch (ReflectiveOperationException e) {
                System.out.println("[PojavLauncher] LWJGL selected by launcher: " + activeLwjgl
                    + ", failed to read org.lwjgl.Version: " + e);
            }
        }
        }

        // MC 26.2+ Graphics API switch (select the in-game OpenGL/Vulkan backend).
        //
        // Mojang introduced the "Graphics API" video setting in MC 26.2 Snapshot 1.
        // It has three values:
        //   - default        Let Mojang decide (Vulkan in snapshots 1–7, OpenGL in snapshot 8+)
        //   - prefer_vulkan  Prefer Vulkan; fall back to OpenGL on failure
        //   - prefer_opengl  Prefer OpenGL; fall back to Vulkan on failure
        //
        // Note: graphicsApi and the launcher's renderer (native-library choice such as
        // libgl4es/libMoltenVK) are separate settings:
        //   - renderer: Which native renderer library the launcher loads (LWJGL layer)
        //   - graphicsApi: Whether MC 26.2+ uses OpenGL or Vulkan internally (game layer)
        //
        // When the user selects prefer_vulkan, also set renderer to libMoltenVK.dylib.
        // The UI recommends this but does not force the two settings to match, allowing
        // advanced users to configure them separately.
        //
        // Older MC versions (1.21.7 and earlier) do not recognize graphicsApi in
        // options.txt; it is ignored.
        //
        // Key fix for an ineffective Graphics API change:
        //   Previously, graphicsApi="default" was skipped and not written to options.txt.
        //   When switching from prefer_vulkan/prefer_opengl back to default, the old value
        //   remained in options.txt and MC continued using it instead of its internal default.
        //   Now:
        //   - "default": Remove the graphicsApi line and let MC use its internal default.
        //   - prefer_vulkan/prefer_opengl: Write the selected value, replacing the old one.
        String graphicsApi = System.getenv("AMETHYST_GRAPHICS_API");
        if (graphicsApi != null && !graphicsApi.isEmpty()) {
            MCOptionUtils.load();
            if ("default".equalsIgnoreCase(graphicsApi)) {
                // When "Default" is selected, remove graphicsApi from options.txt so
                // MC 26.2+ uses its internal default behavior (it does not read this field).
                MCOptionUtils.remove("graphicsApi");
                System.out.println("[PojavLauncher] MC 26.2+ graphicsApi cleared (default)");
            } else {
                String normalized;
                if ("vulkan".equalsIgnoreCase(graphicsApi) || "prefer_vulkan".equalsIgnoreCase(graphicsApi)) {
                    normalized = "prefer_vulkan";
                } else if ("opengl".equalsIgnoreCase(graphicsApi) || "prefer_opengl".equalsIgnoreCase(graphicsApi)) {
                    normalized = "prefer_opengl";
                } else {
                    normalized = graphicsApi.toLowerCase();
                }
                MCOptionUtils.set("graphicsApi", normalized);
                System.out.println("[PojavLauncher] MC 26.2+ graphicsApi set to " + normalized);
            }
            MCOptionUtils.save();
        }

        MinecraftAccount account = MinecraftAccount.load(args[0]);
        JMinecraftVersionList.Version version = Tools.getVersionInfo(args[1]);
        System.out.println("Launching Minecraft " + version.id);

        // The third argument is a server address (FCL style): if nonempty, join it
        // automatically after launch; if empty, do nothing. JavaLauncher.m passes
        // this as args[2] in the NSDictionary launch branch.
        String serverIp = (args.length > 2 && args[2] != null) ? args[2] : "";

        // Set language to Chinese on first launch
        // For Minecraft 1.11 and later: zh_cn (lowercase)
        // For Minecraft 1.6 to 1.10: zh_CN (uppercase)
        // For Minecraft 1.1 to 1.5: zh_CN (uppercase, lowercase crashes)
        MCOptionUtils.load();
        String minecraftVersion = version.id;
        if (minecraftVersion.compareTo("1.11") >= 0) {
            MCOptionUtils.setDefault("lang", "zh_cn");
        } else if (minecraftVersion.compareTo("1.1") >= 0) {
            MCOptionUtils.setDefault("lang", "zh_CN");
        }
        // For Minecraft 1.0 and earlier, no language option
        MCOptionUtils.save();
        String configPath = null;
        // ★ [DEMINE] Previously accessed version.logging.client.file.id directly.
        //   A custom or slim version JSON may have non-null logging but null client/file/id,
        //   causing an NPE and an uncaught exception on the main thread to call System.exit(1).
        //   Check each level and use the fallback configuration below when a value is missing.
        if (version.logging != null && version.logging.client != null
                && version.logging.client.file != null && version.logging.client.file.id != null) {
            if (version.logging.client.file.id.equals("client-1.12.xml")) {
                configPath = Tools.DIR_BUNDLE + "/log4j-rce-patch-1.12.xml";
            } else if (version.logging.client.file.id.equals("client-1.7.xml")) {
                configPath = Tools.DIR_BUNDLE + "/log4j-rce-patch-1.7.xml";
            } else {
                configPath = Tools.DIR_GAME_NEW + "/" + version.logging.client.file.id;
            }
        }
        // Fallback: If the logging configuration is missing or its file does not exist,
        // use the 1.12 patch configuration so MC logs are written to stdout for crash diagnosis.
        if (configPath == null || !new java.io.File(configPath).exists()) {
            configPath = Tools.DIR_BUNDLE + "/log4j-rce-patch-1.12.xml";
            System.out.println("[PojavLauncher] Using fallback log4j config: " + configPath);
        }
        System.setProperty("log4j.configurationFile", configPath);

        Tools.launchMinecraft(account, version, serverIp);
    }
}
