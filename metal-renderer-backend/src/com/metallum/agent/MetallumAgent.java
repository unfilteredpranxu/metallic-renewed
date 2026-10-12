/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  java.lang.Module
 */
package com.metallum.agent;

import com.metallum.shaded.asm.ClassReader;
import com.metallum.shaded.asm.ClassVisitor;
import com.metallum.shaded.asm.ClassWriter;
import com.metallum.shaded.asm.FieldVisitor;
import com.metallum.shaded.asm.Handle;
import com.metallum.shaded.asm.Label;
import com.metallum.shaded.asm.MethodVisitor;
import com.metallum.shaded.asm.Type;
import com.metallum.shaded.asm.commons.AdviceAdapter;
import com.metallum.shaded.asm.commons.Method;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.io.Writer;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.AccessibleObject;
import java.lang.reflect.AnnotatedElement;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

public final class MetallumAgent
implements ClassFileTransformer {
    private static final String TARGET = "net/minecraft/client/PreferredGraphicsApi";
    private static volatile Instrumentation gInst = null;
    private static volatile boolean gDefineAccessOpened = false;
    private static final boolean FIX460_GL_MAKECURRENT = false;
    private static final Set<String> ACCESSIBLE_CLASSES = Set.of((Object)"com/mojang/blaze3d/vulkan/glsl/SpvUniformBuffer", (Object)"com/mojang/blaze3d/vulkan/glsl/SpvSampler", (Object)"com/mojang/blaze3d/vulkan/glsl/SpvVariable");
    private static long EXTRACT_TRACE = 0L;
    private static int setScreenLogs;
    private static long TICK_TRACE;
    private static long HEARTBEAT_COUNT;
    private static long HEARTBEAT_LAST_MS;
    private static long TRACE2;
    private static final ConcurrentHashMap<String, long[]> RATE_STATE;
    private static final long RATE_FIRST = 3L;
    private static final long RATE_INTERVAL_MS = 60000L;
    private static long TICK_LOG_COUNT;
    private static boolean g12111Defined;
    private static final Set<String> gDefinedClasses;
    private static final Set<String> gDeferredDefine;
    private static final AtomicBoolean gDeferRetryStarted;
    private static volatile ClassLoader gDeferLoader;
    private static volatile String gDeferPrefix;
    private static volatile java.lang.reflect.Method gDefineClassMethod;
    private static String rsDynamicUniformsDesc;
    private static final String MC_VERSION_PROP;
    private static volatile String MC_VERSION;
    private static volatile boolean gMcVersionResolved;
    private static int gMcVersionProbeTries;
    private static final boolean IS_METAL_RENDERER;
    private static volatile double lastCursorX;
    private static volatile double lastCursorY;
    private static volatile boolean hasCursor;
    private static volatile Field cursorXField;
    private static volatile Field cursorYField;

    private static int pub(int n) {
        return n & 0xFFFFFFF9 | 1;
    }

    private static void ensureSlf4jOnSystem(Instrumentation instrumentation) {
        try {
            String string2 = System.getProperty("user.dir");
            if (string2 == null || string2.isEmpty()) {
                string2 = System.getenv("POJAV_HOME");
            }
            if (string2 == null || string2.isEmpty()) {
                System.out.println("[MetallumAgent] slf4j: user.dir/POJAV_HOME unset, skip");
                return;
            }
            File file2 = new File(new File(string2, "libraries"), "org/slf4j/slf4j-api");
            if (!file2.isDirectory()) {
                System.out.println("[MetallumAgent] slf4j: " + String.valueOf(file2) + " not found, skip");
                return;
            }
            File file3 = null;
            File[] fileArray = file2.listFiles();
            if (fileArray != null) {
                for (File file4 : fileArray) {
                    File[] fileArray2;
                    if (!file4.isDirectory() || (fileArray2 = file4.listFiles((file, string) -> string.startsWith("slf4j-api-") && string.endsWith(".jar"))) == null || fileArray2.length <= 0) continue;
                    file3 = fileArray2[0];
                }
            }
            if (file3 == null) {
                System.out.println("[MetallumAgent] slf4j: no slf4j-api jar under " + String.valueOf(file2));
                return;
            }
            instrumentation.appendToSystemClassLoaderSearch(new JarFile(file3));
            System.out.println("[MetallumAgent] slf4j-api appended to system classpath: " + String.valueOf(file3));
        }
        catch (Throwable throwable) {
            System.err.println("[MetallumAgent] slf4j search failed: " + String.valueOf(throwable));
        }
    }

    public static void premain(String string, Instrumentation instrumentation) {
        System.out.println("[MetallumAgent] version v15 (cs262-route)");
        gInst = instrumentation;
        if (!IS_METAL_RENDERER) {
            System.out.println("[MetallumAgent] non-Metal renderer: SDL stubs + metallum classes only (render patches disabled)");
        }
        if (MetallumAgent.isFabricLoaderPresent()) {
            if (MC_VERSION.contains("26.3")) {
                System.out.println("[MetallumAgent] Fabric Loader + 26.3 - official mod does not support 26.3, injecting via agent");
            } else {
                System.out.println("[MetallumAgent] Fabric Loader detected - skipping injection (use official MetalUniversal Fabric mod)");
                return;
            }
        }
        try {
            System.out.println("[MetallumAgent] spvc preload skipped (FIX-LWJGL-INIT)");
        }
        catch (Throwable throwable) {
            System.out.println("[MetallumAgent] spirv-cross preload skipped: " + String.valueOf(throwable));
        }
        MetallumAgent.ensureSlf4jOnSystem(instrumentation);
        instrumentation.addTransformer(new MetallumAgent(), true);
        System.out.println("[MetallumAgent] premain active (FIX263-slf4j-first)");
        try {
            MetallumAgent.startCtcInputRetransform(instrumentation);
        }
        catch (Throwable throwable) {
            System.err.println("[MetallumAgent] CTC input retransform watchdog failed: " + String.valueOf(throwable));
        }
        try {
            Thread thread = new Thread(() -> {
                try {
                    Thread.sleep(35000L);
                }
                catch (InterruptedException interruptedException) {
                    // empty catch block
                }
                System.err.println("[MetallumAgent] ===== 35s THREAD DUMP (startup hang diagnosis) =====");
                for (Map.Entry<Thread, StackTraceElement[]> entry : Thread.getAllStackTraces().entrySet()) {
                    Thread thread = entry.getKey();
                    if (thread.getState() != Thread.State.RUNNABLE && thread.getState() != Thread.State.WAITING && thread.getState() != Thread.State.TIMED_WAITING && thread.getState() != Thread.State.BLOCKED) continue;
                    StringBuilder stringBuilder = new StringBuilder();
                    stringBuilder.append("[MetallumAgent] T|").append(thread.getName()).append(" state=").append((Object)thread.getState());
                    StackTraceElement[] stackTraceElementArray = entry.getValue();
                    for (int i = 0; i < Math.min(14, stackTraceElementArray.length); ++i) {
                        stringBuilder.append("\n  at ").append(stackTraceElementArray[i]);
                    }
                    System.err.println(stringBuilder.toString());
                }
                System.err.println("[MetallumAgent] ===== THREAD DUMP END =====");
            }, "metallum-dump");
            thread.setDaemon(true);
            thread.start();
        }
        catch (Throwable throwable) {
            // empty catch block
        }
        try {
            Thread thread = new Thread(() -> {
                for (int i = 1; i <= 24; ++i) {
                    try {
                        Thread.sleep(5000L);
                    }
                    catch (InterruptedException interruptedException) {
                        return;
                    }
                    try {
                        Object object;
                        Class<?> clazz;
                        Object object2;
                        Class<?> clazz2 = MetallumAgent.probeLoadClass("net.minecraft.client.Minecraft");
                        Object object3 = clazz2.getMethod("getInstance", new Class[0]).invoke(null, new Object[0]);
                        StringBuilder stringBuilder = new StringBuilder("[MetallumAgent] STATE t=" + i * 5 + "s");
                        try {
                            object2 = clazz2.getDeclaredField("pause");
                            ((AccessibleObject)object2).setAccessible(true);
                            stringBuilder.append(" pause=").append(((Field)object2).get(object3));
                        }
                        catch (Throwable throwable) {
                            stringBuilder.append(" pause=ERR:").append(throwable.getClass().getSimpleName());
                        }
                        try {
                            object2 = clazz2.getDeclaredField("deltaTracker");
                            ((AccessibleObject)object2).setAccessible(true);
                            clazz = ((Field)object2).get(object3);
                            if (clazz != null) {
                                for (String string : new String[]{"lastMs", "deltaTicks", "deltaTickResidual", "realtimeDeltaTicks", "paused", "frozen", "msPerTick"}) {
                                    try {
                                        Field field = clazz.getClass().getDeclaredField(string);
                                        field.setAccessible(true);
                                        stringBuilder.append(" dt.").append(string).append("=").append(field.get(clazz));
                                    }
                                    catch (Throwable throwable) {
                                        // empty catch block
                                    }
                                }
                            } else {
                                stringBuilder.append(" dt=null");
                            }
                        }
                        catch (Throwable throwable) {
                            stringBuilder.append(" dt=ERR:").append(throwable.getClass().getSimpleName());
                        }
                        object2 = null;
                        try {
                            clazz = clazz2.getDeclaredField("gui");
                            ((AccessibleObject)((Object)clazz)).setAccessible(true);
                            object2 = ((Field)((Object)clazz)).get(object3);
                        }
                        catch (Throwable throwable) {
                            // empty catch block
                        }
                        if (object2 != null) {
                            clazz = null;
                            try {
                                clazz = object2.getClass().getMethod("overlay", new Class[0]).invoke(object2, new Object[0]);
                            }
                            catch (Throwable throwable) {
                                // empty catch block
                            }
                            stringBuilder.append(" overlay=").append(clazz == null ? "null" : clazz.getClass().getSimpleName());
                            if (clazz != null) {
                                Class<?> clazz32;
                                AnnotatedElement annotatedElement;
                                object = null;
                                try {
                                    annotatedElement = clazz.getClass().getDeclaredField("reload");
                                    ((AccessibleObject)annotatedElement).setAccessible(true);
                                    object = ((Field)annotatedElement).get(clazz);
                                }
                                catch (Throwable throwable) {
                                    // empty catch block
                                }
                                if (object != null) {
                                    annotatedElement = MetallumAgent.probeLoadClass("net.minecraft.server.packs.resources.ReloadInstance");
                                    if (annotatedElement == null) {
                                        for (Class<?> clazz32 : object.getClass().getInterfaces()) {
                                            if (!clazz32.getSimpleName().equals("ReloadInstance")) continue;
                                            annotatedElement = clazz32;
                                            break;
                                        }
                                    }
                                    try {
                                        stringBuilder.append(" reload.isDone=").append(((Class)annotatedElement).getMethod("isDone", new Class[0]).invoke(object, new Object[0]));
                                    }
                                    catch (Throwable throwable) {
                                        stringBuilder.append(" reload.isDone=ERR:").append(throwable);
                                    }
                                    try {
                                        stringBuilder.append(" actualProgress=").append(((Class)annotatedElement).getMethod("getActualProgress", new Class[0]).invoke(object, new Object[0]));
                                    }
                                    catch (Throwable throwable) {
                                        // empty catch block
                                    }
                                    try {
                                        Object object4 = ((Class)annotatedElement).getMethod("done", new Class[0]).invoke(object, new Object[0]);
                                        if (object4 instanceof CompletableFuture) {
                                            CompletableFuture completableFuture = (CompletableFuture)object4;
                                            stringBuilder.append(" done.isDone=").append(completableFuture.isDone()).append(" done.exc=").append(completableFuture.isCompletedExceptionally());
                                            if (completableFuture.isCompletedExceptionally()) {
                                                try {
                                                    completableFuture.join();
                                                }
                                                catch (Throwable throwable) {
                                                    clazz32 = new StringWriter();
                                                    throwable.printStackTrace(new PrintWriter((Writer)((Object)clazz32)));
                                                    String string = ((StringWriter)((Object)clazz32)).toString();
                                                    if (string.length() > 4000) {
                                                        string = string.substring(0, 4000);
                                                    }
                                                    System.out.println("[MetallumAgent] ===== RELOAD EXCEPTION =====\n" + string + "\n[MetallumAgent] ===== END RELOAD EXCEPTION =====");
                                                }
                                            }
                                        }
                                    }
                                    catch (Throwable throwable) {
                                        // empty catch block
                                    }
                                }
                                try {
                                    annotatedElement = clazz.getClass().getDeclaredMethod("isReadyToFadeOut", new Class[0]);
                                    ((AccessibleObject)annotatedElement).setAccessible(true);
                                    stringBuilder.append(" isReadyToFadeOut=").append(((java.lang.reflect.Method)annotatedElement).invoke(clazz, new Object[0]));
                                }
                                catch (Throwable throwable) {
                                    stringBuilder.append(" isReadyToFadeOut=ERR:").append(throwable.getClass().getSimpleName());
                                }
                                for (AnnotatedElement annotatedElement2 : new String[]{"currentProgress", "fadeInStart", "fadeOutStart", "fadeIn"}) {
                                    try {
                                        clazz32 = clazz.getClass().getDeclaredField((String)((Object)annotatedElement2));
                                        ((AccessibleObject)((Object)clazz32)).setAccessible(true);
                                        stringBuilder.append(" ").append((String)((Object)annotatedElement2)).append("=").append(((Field)((Object)clazz32)).get(clazz));
                                    }
                                    catch (Throwable throwable) {
                                        // empty catch block
                                    }
                                }
                            }
                            try {
                                stringBuilder.append(" gui.screen=").append(object2.getClass().getMethod("screen", new Class[0]).invoke(object2, new Object[0]));
                            }
                            catch (Throwable throwable) {
                                // empty catch block
                            }
                        }
                        try {
                            clazz = clazz2.getClassLoader();
                            object = Class.forName("com.metallum.client.metal.render.MetalSurface", false, (ClassLoader)((Object)clazz));
                            java.lang.reflect.Method method = ((Class)object).getDeclaredMethod("flowSnapshot", new Class[0]);
                            method.setAccessible(true);
                            stringBuilder.append(" FLOW[").append(method.invoke(null, new Object[0])).append("]");
                        }
                        catch (Throwable throwable) {
                            stringBuilder.append(" FLOW=ERR:").append(throwable);
                        }
                        try {
                            clazz = clazz2.getClassLoader();
                            object = Class.forName("com.metallum.client.metal.render.MetalCommandEncoder", false, (ClassLoader)((Object)clazz));
                            stringBuilder.append(" mce.colorProbe=").append(MetallumAgent.statField(object, "COLOR_PROBE")).append(" mce.probeFrames=").append(MetallumAgent.statField(object, "COLOR_PROBE_FRAMES")).append(" mce.probeErr=").append(MetallumAgent.statField(object, "COLOR_PROBE_ERRORS")).append(" mce.probeNotRt=").append(MetallumAgent.statField(object, "COLOR_PROBE_NOT_RT")).append(" mce.retireTimeouts=").append(MetallumAgent.statField(object, "RETIRE_TIMEOUTS")).append(" mce.submitWaitMaxMs=").append(MetallumAgent.statField(object, "SUBMIT_WAIT_MAX_MS"));
                        }
                        catch (Throwable throwable) {
                            stringBuilder.append(" mce=ERR:").append(throwable);
                        }
                        try {
                            clazz = clazz2.getClassLoader();
                            object = Class.forName("com.metallum.client.metal.render.MetalTransientMemory", false, (ClassLoader)((Object)clazz));
                            stringBuilder.append(" tm.pendingRotations=").append(MetallumAgent.statField(object, "PENDING_ROTATION_COUNT")).append(" tm.forcedRotations=").append(MetallumAgent.statField(object, "FORCED_ROTATIONS"));
                        }
                        catch (Throwable throwable) {
                            stringBuilder.append(" tm=ERR:").append(throwable);
                        }
                        try {
                            clazz = MetallumAgent.probeLoadClass("net.minecraft.util.Util");
                            object = clazz.getDeclaredField("timeSource");
                            ((AccessibleObject)object).setAccessible(true);
                            Object object5 = ((Field)object).get(null);
                            stringBuilder.append(" timeSource=").append(object5 == null ? "null" : object5.getClass().getSimpleName());
                            stringBuilder.append(" getNanos=").append(clazz.getMethod("getNanos", new Class[0]).invoke(null, new Object[0])).append(" getMillis=").append(clazz.getMethod("getMillis", new Class[0]).invoke(null, new Object[0]));
                        }
                        catch (Throwable throwable) {
                            stringBuilder.append(" timeSource=ERR:").append(throwable.getClass().getSimpleName());
                        }
                        System.out.println(stringBuilder.toString());
                        continue;
                    }
                    catch (Throwable throwable) {
                        System.out.println("[MetallumAgent] STATE probe error: " + String.valueOf(throwable));
                    }
                }
            }, "metallum-state");
            thread.setDaemon(true);
            thread.start();
        }
        catch (Throwable throwable) {
            // empty catch block
        }
        try {
            Class<?> clazz = Class.forName("com.metallum.client.metal.render.bridge.MetalNativeBridge");
            clazz.getMethod("ensureSpvcLibraryConfigured", new Class[0]).invoke(null, new Object[0]);
            System.out.println("[MetallumAgent] ensureSpvcLibraryConfigured called OK");
            try {
                Class.forName("org.lwjgl.util.spvc.Spvc", false, ClassLoader.getSystemClassLoader());
                System.out.println("[MetallumAgent] Spvc class loadable (FIX-LWJGL-INIT, init deferred)");
            }
            catch (Throwable throwable) {
                System.out.println("[MetallumAgent] Spvc class init FAILED: " + String.valueOf(throwable));
                throwable.printStackTrace();
                for (Throwable throwable2 = throwable.getCause(); throwable2 != null; throwable2 = throwable2.getCause()) {
                    System.out.println("[MetallumAgent]   spvc cause: " + String.valueOf(throwable2));
                }
            }
        }
        catch (Throwable throwable) {
            System.out.println("[MetallumAgent] ensureSpvcLibraryConfigured failed: " + String.valueOf(throwable));
        }
    }

    private static boolean isFabricLoaderPresent() {
        try {
            Class.forName("net.fabricmc.loader.api.FabricLoader", false, ClassLoader.getSystemClassLoader());
            return true;
        }
        catch (Throwable throwable) {
            return false;
        }
    }

    private static boolean isForgeLoaderPresent() {
        try {
            Class.forName("cpw.mods.modlauncher.Launcher", false, ClassLoader.getSystemClassLoader());
            return true;
        }
        catch (Throwable throwable) {
            return false;
        }
    }

    private static ClassWriter newCW(ClassReader classReader) {
        return new ClassWriter(classReader, 3){

            @Override
            protected String getCommonSuperClass(String string, String string2) {
                return "java/lang/Object";
            }
        };
    }

    private static byte[] patchLevelExtractor263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (string.equals("<init>") || string.equals("close")) {
                    return methodVisitor;
                }
                final String string4 = string;
                final String string5 = string2;
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        if (++EXTRACT_TRACE % 25L != 1L) {
                            return;
                        }
                        super.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                        super.visitTypeInsn(187, "java/lang/StringBuilder");
                        super.visitInsn(89);
                        super.visitMethodInsn(183, "java/lang/StringBuilder", "<init>", "()V", false);
                        super.visitLdcInsn("[MetallumAgent] LevelExtractor." + string4 + " ");
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        super.visitLdcInsn(string5);
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "toString", "()Ljava/lang/String;", false);
                        super.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchWindowFocus263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!string.equals("isFocused") || !string2.equals("()Z")) {
                    return methodVisitor;
                }
                System.out.println("[MetallumAgent] Window.isFocused -> forced true (26.3 iOS)");
                methodVisitor.visitCode();
                methodVisitor.visitInsn(4);
                methodVisitor.visitInsn(172);
                methodVisitor.visitMaxs(1, 1);
                methodVisitor.visitEnd();
                return new MethodVisitor(this, 589824){};
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchCallbackDeviceTracker261(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        final int[] nArray = new int[]{0};
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!string.equals("isSupportedForPlaybackDevice")) {
                    return methodVisitor;
                }
                nArray[0] = nArray[0] + 1;
                System.out.println("[MetallumAgent] CallbackDeviceTracker." + string + string2 + " -> false (26.1 iOS: openal \u7f3a ALC_SOFT_system_events)");
                methodVisitor.visitCode();
                methodVisitor.visitInsn(3);
                methodVisitor.visitInsn(172);
                methodVisitor.visitMaxs(0, 0);
                methodVisitor.visitEnd();
                return new MethodVisitor(this, 589824){};
            }
        }, 0);
        if (nArray[0] == 0) {
            System.out.println("[MetallumAgent] !!! CallbackDeviceTracker: isSupportedForPlaybackDevice \u672a\u627e\u5230 (\u7b7e\u540d\u53d8\u4e86?) \u2014 26.1 \u58f0\u97f3\u521d\u59cb\u5316\u53ef\u80fd\u4ecd\u4f1a\u5d29");
        } else {
            System.out.println("[MetallumAgent] CallbackDeviceTracker \u6253\u4e86 " + nArray[0] + " \u4e2a\u65b9\u6cd5");
        }
        return classWriter.toByteArray();
    }

    private static byte[] patchSoftSystemEvents(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        final int[] nArray = new int[]{0};
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!string.startsWith("alcEvent")) {
                    return methodVisitor;
                }
                nArray[0] = nArray[0] + 1;
                System.out.println("[MetallumAgent] SOFTSystemEvents." + string + string2 + " -> false");
                methodVisitor.visitCode();
                methodVisitor.visitInsn(3);
                methodVisitor.visitInsn(172);
                methodVisitor.visitMaxs(0, 0);
                methodVisitor.visitEnd();
                return new MethodVisitor(this, 589824){};
            }
        }, 0);
        if (nArray[0] == 0) {
            System.out.println("[MetallumAgent] !!! SOFTSystemEvents: \u6ca1\u6709 alcEvent* \u65b9\u6cd5");
        }
        return classWriter.toByteArray();
    }

    private static byte[] patchMinecraftSetScreen261(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!"setScreen".equals(string) || !string2.startsWith("(Lnet/minecraft/client/gui/screens/Screen;")) {
                    return methodVisitor;
                }
                System.out.println("[MetallumAgent] patching Minecraft.setScreen (26.1 \u754c\u9762\u63a2\u9488) desc=" + string2);
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        super.visitVarInsn(25, 1);
                        super.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "logSetScreen", "(Ljava/lang/Object;)V", false);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    public static void logSetScreen(Object object) {
        try {
            if (setScreenLogs++ < 40 || setScreenLogs % 200 == 0) {
                System.err.println("[metallum] SETSCREEN #" + setScreenLogs + " -> " + (object == null ? "null" : object.getClass().getName()));
            }
        }
        catch (Throwable throwable) {
            // empty catch block
        }
    }

    private static byte[] patchMinecraftTickProbe263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (string.equals("pauseIfInactive") && string2.equals("()V")) {
                    System.out.println("[MetallumAgent] Minecraft.pauseIfInactive -> no-op (26.3 iOS)");
                    methodVisitor.visitCode();
                    methodVisitor.visitInsn(177);
                    methodVisitor.visitMaxs(0, 1);
                    methodVisitor.visitEnd();
                    return new MethodVisitor(this, 589824){};
                }
                if (string.equals("runTick") && string2.equals("(Z)V")) {
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(21, 1);
                            super.visitLdcInsn("Minecraft.runTick arg=");
                            super.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "traceBool", "(ZLjava/lang/String;)V", false);
                            super.visitInsn(4);
                            super.visitVarInsn(54, 1);
                        }
                    };
                }
                if (string.equals("pauseGame") && string2.equals("(Z)V")) {
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            super.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                            super.visitTypeInsn(187, "java/lang/StringBuilder");
                            super.visitInsn(89);
                            super.visitMethodInsn(183, "java/lang/StringBuilder", "<init>", "()V", false);
                            super.visitLdcInsn("[MetallumAgent] Minecraft.pauseGame(");
                            super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                            super.visitVarInsn(21, 1);
                            super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Z)Ljava/lang/StringBuilder;", false);
                            super.visitLdcInsn(") called");
                            super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                            super.visitMethodInsn(182, "java/lang/StringBuilder", "toString", "()Ljava/lang/String;", false);
                            super.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
                        }
                    };
                }
                if (!string.equals("tick") || !string2.equals("()V")) {
                    return methodVisitor;
                }
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        super.visitLdcInsn("Minecraft.tick() running");
                        super.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "tickHeartbeat", "(Ljava/lang/String;)V", false);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    public static void tickHeartbeat(String string) {
        MetallumAgent.traceRate("tick:" + string, string);
    }

    private static Object statField(Class<?> clazz, String string) {
        try {
            Field field = clazz.getDeclaredField(string);
            field.setAccessible(true);
            return field.get(null);
        }
        catch (Throwable throwable) {
            return "n/a";
        }
    }

    private static Class<?> probeLoadClass(String string) {
        try {
            return Class.forName(string);
        }
        catch (Throwable throwable) {
            ClassLoader classLoader = Thread.currentThread().getContextClassLoader();
            if (classLoader != null) {
                try {
                    return Class.forName(string, false, classLoader);
                }
                catch (Throwable throwable2) {
                    // empty catch block
                }
            }
            return null;
        }
    }

    /*
     * Exception decompiling
     */
    public static void traceRate(String var0, String var1_1) {
        /*
         * This method has failed to decompile.  When submitting a bug report, please provide this stack trace, and (if you hold appropriate legal rights) the relevant class file.
         * 
         * java.lang.UnsupportedOperationException
         *     at org.benf.cfr.reader.bytecode.analysis.parse.expression.NewAnonymousArray.getDimSize(NewAnonymousArray.java:142)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.op4rewriters.LambdaRewriter.isNewArrayLambda(LambdaRewriter.java:455)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.op4rewriters.LambdaRewriter.rewriteDynamicExpression(LambdaRewriter.java:409)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.op4rewriters.LambdaRewriter.rewriteDynamicExpression(LambdaRewriter.java:167)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.op4rewriters.LambdaRewriter.rewriteExpression(LambdaRewriter.java:105)
         *     at org.benf.cfr.reader.bytecode.analysis.parse.rewriters.ExpressionRewriterHelper.applyForwards(ExpressionRewriterHelper.java:12)
         *     at org.benf.cfr.reader.bytecode.analysis.parse.expression.AbstractMemberFunctionInvokation.applyExpressionRewriterToArgs(AbstractMemberFunctionInvokation.java:101)
         *     at org.benf.cfr.reader.bytecode.analysis.parse.expression.AbstractMemberFunctionInvokation.applyExpressionRewriter(AbstractMemberFunctionInvokation.java:88)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.op4rewriters.LambdaRewriter.rewriteExpression(LambdaRewriter.java:103)
         *     at org.benf.cfr.reader.bytecode.analysis.parse.expression.AssignmentExpression.applyExpressionRewriter(AssignmentExpression.java:68)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.op4rewriters.LambdaRewriter.rewriteExpression(LambdaRewriter.java:103)
         *     at org.benf.cfr.reader.bytecode.analysis.structured.statement.StructuredAssignment.rewriteExpressions(StructuredAssignment.java:146)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.op4rewriters.LambdaRewriter.rewrite(LambdaRewriter.java:88)
         *     at org.benf.cfr.reader.bytecode.analysis.opgraph.Op04StructuredStatement.rewriteLambdas(Op04StructuredStatement.java:1137)
         *     at org.benf.cfr.reader.bytecode.CodeAnalyser.getAnalysisInner(CodeAnalyser.java:912)
         *     at org.benf.cfr.reader.bytecode.CodeAnalyser.getAnalysisOrWrapFail(CodeAnalyser.java:278)
         *     at org.benf.cfr.reader.bytecode.CodeAnalyser.getAnalysis(CodeAnalyser.java:201)
         *     at org.benf.cfr.reader.entities.attributes.AttributeCode.analyse(AttributeCode.java:94)
         *     at org.benf.cfr.reader.entities.Method.analyse(Method.java:531)
         *     at org.benf.cfr.reader.entities.ClassFile.analyseMid(ClassFile.java:1055)
         *     at org.benf.cfr.reader.entities.ClassFile.analyseTop(ClassFile.java:942)
         *     at org.benf.cfr.reader.Driver.doJarVersionTypes(Driver.java:257)
         *     at org.benf.cfr.reader.Driver.doJar(Driver.java:139)
         *     at org.benf.cfr.reader.CfrDriverImpl.analyse(CfrDriverImpl.java:76)
         *     at org.benf.cfr.reader.Main.main(Main.java:54)
         */
        throw new IllegalStateException("Decompilation failed");
    }

    public static void traceInt(int n, String string) {
        MetallumAgent.traceRate("I:" + string, string + n);
    }

    public static void traceBool(boolean bl, String string) {
        MetallumAgent.traceRate("B:" + string, string + bl);
    }

    private static byte[] patchTimerProbe263(byte[] byArray, final String string) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string5, String string2, String string3, String[] stringArray) {
                boolean bl;
                MethodVisitor methodVisitor = super.visitMethod(n, string5, string2, string3, stringArray);
                final boolean bl2 = string5.equals("advanceGameTime") && string2.equals("(J)I");
                boolean bl3 = bl = string5.equals("runTick") && string2.equals("(Z)V");
                if (string5.equals("<init>")) {
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            super.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                            super.visitLdcInsn("[MetallumAgent] DeltaTracker$Timer.<init> (timer created)");
                            super.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
                        }
                    };
                }
                if (!bl2 && !bl) {
                    return methodVisitor;
                }
                final String string4 = string + "." + string5 + (bl2 ? " ret=" : " arg=");
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        if (bl) {
                            this.mv.visitVarInsn(21, 1);
                            this.mv.visitLdcInsn(string4);
                            this.mv.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "traceBool", "(ZLjava/lang/String;)V", false);
                        }
                    }

                    @Override
                    public void visitInsn(int n) {
                        if (bl2 && n == 172) {
                            this.mv.visitInsn(89);
                            this.mv.visitLdcInsn(string4);
                            this.mv.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "traceInt", "(ILjava/lang/String;)V", false);
                        }
                        super.visitInsn(n);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    public static void tickLog(String string) {
        ++TICK_LOG_COUNT;
        MetallumAgent.traceRate("ticklog:" + string, string);
    }

    private static byte[] patchTickTracing263(byte[] byArray, final String string) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string5, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string5, string2, string3, stringArray);
                if (!string5.equals("tick") || !string2.equals("()V")) {
                    return methodVisitor;
                }
                final String string4 = string + ".tick";
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        super.visitLdcInsn(string4 + " ENTER");
                        super.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "tickLog", "(Ljava/lang/String;)V", false);
                    }

                    @Override
                    public void visitInsn(int n) {
                        if (n == 177) {
                            super.visitLdcInsn(string4 + " EXIT");
                            super.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "tickLog", "(Ljava/lang/String;)V", false);
                        }
                        super.visitInsn(n);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchPresenceHandler263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!string.equals("tick") || !string2.equals("()V")) {
                    return methodVisitor;
                }
                System.out.println("[MetallumAgent] PresenceHandler.tick -> no-op (26.3 iOS)");
                methodVisitor.visitCode();
                methodVisitor.visitInsn(177);
                methodVisitor.visitMaxs(0, 1);
                methodVisitor.visitEnd();
                return new MethodVisitor(this, 589824){};
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchGenericMessage263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!string.equals("<init>") || !string2.startsWith("(Lnet/minecraft/network/chat/Component;)")) {
                    return methodVisitor;
                }
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        super.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                        super.visitTypeInsn(187, "java/lang/StringBuilder");
                        super.visitInsn(89);
                        super.visitMethodInsn(183, "java/lang/StringBuilder", "<init>", "()V", false);
                        super.visitLdcInsn("[MetallumAgent] GenericMessageScreen msg=");
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        super.visitVarInsn(25, 1);
                        super.visitMethodInsn(184, "java/lang/String", "valueOf", "(Ljava/lang/Object;)Ljava/lang/String;", false);
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "toString", "()Ljava/lang/String;", false);
                        super.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchGuiSetOverlay263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!string.equals("setOverlay")) {
                    return methodVisitor;
                }
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        super.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                        super.visitTypeInsn(187, "java/lang/StringBuilder");
                        super.visitInsn(89);
                        super.visitMethodInsn(183, "java/lang/StringBuilder", "<init>", "()V", false);
                        super.visitLdcInsn("[MetallumAgent] Gui.setOverlay arg=");
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        super.visitVarInsn(25, 1);
                        super.visitMethodInsn(184, "java/lang/String", "valueOf", "(Ljava/lang/Object;)Ljava/lang/String;", false);
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "toString", "()Ljava/lang/String;", false);
                        super.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchMinecraftProbe263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, final String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!(string.equals("setOverlay") || string.equals("setScreen") || string.equals("loadCriticalShaders"))) {
                    return methodVisitor;
                }
                boolean bl = (n & 8) != 0;
                String string4 = "";
                int n2 = string2.indexOf(41);
                if (n2 > 1) {
                    string4 = string2.substring(1, n2);
                }
                final boolean bl2 = string4.startsWith("L") || string4.startsWith("[");
                final int n3 = bl ? 0 : 1;
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        super.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                        super.visitTypeInsn(187, "java/lang/StringBuilder");
                        super.visitInsn(89);
                        super.visitMethodInsn(183, "java/lang/StringBuilder", "<init>", "()V", false);
                        super.visitLdcInsn("[MetallumAgent] MC." + string + " arg=");
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        if (bl2) {
                            super.visitVarInsn(25, n3);
                            super.visitMethodInsn(184, "java/lang/String", "valueOf", "(Ljava/lang/Object;)Ljava/lang/String;", false);
                            super.visitMethodInsn(182, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", false);
                        }
                        super.visitMethodInsn(182, "java/lang/StringBuilder", "toString", "()Ljava/lang/String;", false);
                        super.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchForgeLoadingOverlay(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = MetallumAgent.newCW(classReader);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!"<init>".equals(string)) {
                    return methodVisitor;
                }
                final Label label = new Label();
                final boolean[] blArray = new boolean[]{false};
                final boolean[] blArray2 = new boolean[]{false};
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitMethodInsn(int n, String string, String string2, String string3, boolean bl) {
                        super.visitMethodInsn(n, string, string2, string3, bl);
                        if (!blArray[0] && "getTexture".equals(string2) && string.endsWith("/AbstractTexture")) {
                            super.visitInsn(87);
                            super.visitJumpInsn(167, label);
                            blArray[0] = true;
                        }
                        if (blArray[0] && !blArray2[0] && "addMojangTexture".equals(string2)) {
                            super.visitLabel(label);
                            blArray2[0] = true;
                        }
                    }
                };
            }
        }, 8);
        System.out.println("[MetallumAgent] ForgeLoadingOverlay patched (Metal-safe logo texture)");
        return classWriter.toByteArray();
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    private static void resolveMcVersionOnce(ClassLoader classLoader) {
        if (gMcVersionResolved) {
            return;
        }
        if (gMcVersionProbeTries >= 40) {
            return;
        }
        Class<MetallumAgent> clazz = MetallumAgent.class;
        synchronized (MetallumAgent.class) {
            ClassLoader[] classLoaderArray;
            if (gMcVersionResolved) {
                // ** MonitorExit[var1_1] (shouldn't be in output)
                return;
            }
            ++gMcVersionProbeTries;
            for (ClassLoader classLoader2 : classLoaderArray = new ClassLoader[]{classLoader, Thread.currentThread().getContextClassLoader(), ClassLoader.getSystemClassLoader()}) {
                if (classLoader2 == null) continue;
                try {
                    if (classLoader2.getResource("com/mojang/renderpearl/api/device/GpuBackend.class") == null) continue;
                    MC_VERSION = "26.3";
                    gMcVersionResolved = true;
                    System.out.println("[MetallumAgent] FIX263-ROUTE: metallum.mc.version \u5c5e\u6027\u4e3a\u7a7a, \u63a2\u6d4b\u5230 com/mojang/renderpearl \u21d2 \u6309 26.3 \u8def\u7531 (loader=" + String.valueOf(classLoader2) + ")");
                    // ** MonitorExit[var1_1] (shouldn't be in output)
                    return;
                }
                catch (Throwable throwable) {
                    // empty catch block
                }
            }
            if (gMcVersionProbeTries == 40) {
                System.out.println("[MetallumAgent] FIX263-ROUTE: \u5c5e\u6027\u4e3a\u7a7a\u4e14\u63a2\u6d4b\u4e0d\u5230 renderpearl \u21d2 \u4fdd\u6301 26.2 \u8def\u5f84(classes262 \u7c7b\u96c6)");
            }
            // ** MonitorExit[var1_1] (shouldn't be in output)
            return;
        }
    }

    private static boolean ameIsMetalRenderer() {
        if ("1".equals(System.getenv("AMETHYST_METAL"))) {
            return true;
        }
        String string = System.getenv("AMETHYST_RENDERER");
        if (string == null) {
            return false;
        }
        return (string = string.toLowerCase(Locale.ROOT)).contains("metallum") || string.equals("metal");
    }

    private static String classes12111Prefix() {
        Object object = MC_VERSION.contains("1.21") ? "classes12111_1_21_11" : (MC_VERSION.contains("26.1") ? "classes261" : (MC_VERSION.contains("26.3") ? "classes263" : "classes262"));
        if (((String)object).startsWith("classes12111") && MetallumAgent.isForgeLoaderPresent()) {
            object = (String)object + "_forge";
        } else if (((String)object).startsWith("classes12111") && MetallumAgent.isFabricLoaderPresent()) {
            object = (String)object + "_fabric";
        }
        return (String)object + "/";
    }

    private static synchronized void ensure12111(ClassLoader classLoader) {
        if (g12111Defined) {
            return;
        }
        try {
            MetallumAgent.defineMetallumClasses(classLoader, MetallumAgent.classes12111Prefix());
            g12111Defined = true;
            System.out.println("[MetallumAgent] 1.21.x metallum classes defined (" + MetallumAgent.classes12111Prefix() + ")");
        }
        catch (Throwable throwable) {
            System.err.println("[MetallumAgent] 1.21.x define failed: " + String.valueOf(throwable));
        }
    }

    public static void rememberCursor(double d, double d2) {
        lastCursorX = d;
        lastCursorY = d2;
        hasCursor = true;
    }

    public static void restoreCursorAfterResync(Object object) {
        if (!hasCursor || object == null) {
            return;
        }
        try {
            Field field = cursorXField;
            Field field2 = cursorYField;
            if (field == null || field2 == null) {
                for (Class<?> clazz = object.getClass(); clazz != null && (field == null || field2 == null); clazz = clazz.getSuperclass()) {
                    if (field == null) {
                        try {
                            field = clazz.getDeclaredField("xpos");
                        }
                        catch (Throwable throwable) {
                            // empty catch block
                        }
                    }
                    if (field2 != null) continue;
                    try {
                        field2 = clazz.getDeclaredField("ypos");
                        continue;
                    }
                    catch (Throwable throwable) {
                        // empty catch block
                    }
                }
                if (field == null || field2 == null) {
                    return;
                }
                field.setAccessible(true);
                field2.setAccessible(true);
                cursorXField = field;
                cursorYField = field2;
            }
            field.setDouble(object, lastCursorX);
            field2.setDouble(object, lastCursorY);
        }
        catch (Throwable throwable) {
            // empty catch block
        }
    }

    private static byte[] patchMouseHandler(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 3);
        final boolean[] blArray = new boolean[]{false, false};
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if ("onMove".equals(string) && "(JDDDD)V".equals(string2)) {
                    blArray[0] = true;
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(24, 3);
                            super.visitVarInsn(24, 5);
                            super.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "rememberCursor", "(DD)V", false);
                        }
                    };
                }
                if ("resyncMousePosition".equals(string) && "()V".equals(string2)) {
                    blArray[1] = true;
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitInsn(int n) {
                            if (n == 177) {
                                super.visitVarInsn(25, 0);
                                super.visitMethodInsn(184, "com/metallum/agent/MetallumAgent", "restoreCursorAfterResync", "(Ljava/lang/Object;)V", false);
                            }
                            super.visitInsn(n);
                        }
                    };
                }
                return methodVisitor;
            }
        }, 0);
        if (!blArray[0] || !blArray[1]) {
            System.err.println("[MetallumAgent] MouseHandler fix: onMove=" + blArray[0] + " resync=" + blArray[1]);
        }
        return classWriter.toByteArray();
    }

    private static byte[] patchCtcAndroidInput(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = MetallumAgent.newCW(classReader);
        final boolean[] blArray = new boolean[]{false};
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if ("receiveData".equals(string) && "(IIIII)V".equals(string2)) {
                    blArray[0] = true;
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            for (int i = 0; i < 5; ++i) {
                                super.visitVarInsn(21, i);
                            }
                            super.visitMethodInsn(184, "com/metallum/agent/SdlInputBridge", "dispatch", "(IIIII)V", false);
                        }
                    };
                }
                return methodVisitor;
            }
        }, 0);
        if (blArray[0]) {
            System.out.println("[MetallumAgent] CTCAndroidInput.receiveData -> SdlInputBridge injected");
        } else {
            System.err.println("[MetallumAgent] CTCAndroidInput.receiveData NOT FOUND in class file (classfileBuffer=" + byArray.length + "B)");
        }
        return classWriter.toByteArray();
    }

    private static void startCtcInputRetransform(final Instrumentation instrumentation) {
        Thread thread = new Thread(new Runnable(){

            @Override
            public void run() {
                for (int i = 0; i < 300; ++i) {
                    try {
                        Class clazz = null;
                        for (Class clazz2 : instrumentation.getAllLoadedClasses()) {
                            if (clazz2 == null || !"com.github.caciocavallosilano.cacio.ctc.CTCAndroidInput".equals(clazz2.getName())) continue;
                            clazz = clazz2;
                            break;
                        }
                        if (clazz != null) {
                            System.out.println("[MetallumAgent] CTC input retransform (v421): class loaded by " + String.valueOf(clazz.getClassLoader()) + " -> retransformClasses()");
                            instrumentation.retransformClasses(clazz);
                            System.out.println("[MetallumAgent] CTC input retransform done (v421)");
                            return;
                        }
                    }
                    catch (Throwable throwable) {
                        System.err.println("[MetallumAgent] CTC input retransform FAILED (v421): " + String.valueOf(throwable));
                        return;
                    }
                    try {
                        Thread.sleep(500L);
                        continue;
                    }
                    catch (InterruptedException interruptedException) {
                        return;
                    }
                }
                System.err.println("[MetallumAgent] CTC input retransform (v421): class never appeared in 150s");
            }
        });
        thread.setDaemon(true);
        thread.setName("metallum-ctc-input");
        thread.start();
    }

    private static byte[] injectHideWindowOnReturn(byte[] byArray, final String string) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 3);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string4, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string4, string2, string3, stringArray);
                if (!string4.equals(string)) {
                    return methodVisitor;
                }
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitInsn(int n) {
                        if (n == 173) {
                            this.mv.visitInsn(92);
                            this.mv.visitMethodInsn(184, "org/lwjgl/sdl/SDLVideo", "SDL_HideWindow", "(J)Z", false);
                            this.mv.visitInsn(87);
                            System.out.println("[MetallumAgent] SDL_HideWindow injected before return of " + string);
                        }
                        super.visitInsn(n);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] injectThrowableTrace(byte[] byArray, final String string) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 3);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string4, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string4, string2, string3, stringArray);
                if (!string4.equals(string)) {
                    return methodVisitor;
                }
                return new MethodVisitor(this, 589824, methodVisitor){
                    private final Label start = new Label();
                    private final Label end = new Label();
                    private final Label handler = new Label();

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        super.visitTryCatchBlock(this.start, this.end, this.handler, "java/lang/Throwable");
                        super.visitLabel(this.start);
                    }

                    @Override
                    public void visitMaxs(int n, int n2) {
                        super.visitLabel(this.end);
                        super.visitLabel(this.handler);
                        super.visitInsn(89);
                        super.visitFieldInsn(178, "java/lang/System", "err", "Ljava/io/PrintStream;");
                        super.visitMethodInsn(182, "java/lang/Throwable", "printStackTrace", "(Ljava/io/PrintStream;)V", false);
                        super.visitInsn(191);
                        super.visitMaxs(Math.max(n, 3), n2);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchRenderSystem(byte[] byArray) {
        if (MC_VERSION.contains("26.1") || MC_VERSION.contains("26.2") || MC_VERSION.contains("26.3")) {
            return null;
        }
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = MetallumAgent.newCW(classReader);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public FieldVisitor visitField(int n, String string, String string2, String string3, Object object) {
                if ("dynamicUniforms".equals(string)) {
                    rsDynamicUniformsDesc = string2;
                }
                return super.visitField(n, string, string2, string3, object);
            }

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!MC_VERSION.contains("26.1") && !MC_VERSION.contains("26.3") && "initRenderer".equals(string) && string2.equals("(Lcom/mojang/blaze3d/systems/GpuDevice;)V")) {
                    System.out.println("[MetallumAgent] patching RenderSystem.initRenderer (26.1 GpuDevice)");
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            Label label = new Label();
                            this.visitMethodInsn(184, "com/metallum/client/metal/render/MetalBackend", "isMetalHost", "()Z", false);
                            this.visitJumpInsn(153, label);
                            this.visitInsn(9);
                            this.visitVarInsn(25, 0);
                            this.visitMethodInsn(184, "com/metallum/client/metal/render/MetalBackend", "createDevice", "(JLcom/mojang/blaze3d/systems/GpuDevice;)Lcom/metallum/client/metal/render/MetalDevice;", false);
                            this.visitFieldInsn(179, "com/mojang/blaze3d/systems/RenderSystem", "DEVICE", "Lcom/mojang/blaze3d/systems/GpuDevice;");
                            this.visitMethodInsn(184, "com/mojang/blaze3d/systems/RenderSystem", "getDevice", "()Lcom/mojang/blaze3d/systems/GpuDevice;", false);
                            this.visitMethodInsn(182, "com/mojang/blaze3d/systems/GpuDevice", "getImplementationInformation", "()Ljava/lang/String;", false);
                            this.visitFieldInsn(179, "com/mojang/blaze3d/systems/RenderSystem", "apiDescription", "Ljava/lang/String;");
                            this.visitTypeInsn(187, "net/minecraft/client/renderer/DynamicUniforms");
                            this.visitInsn(89);
                            this.visitMethodInsn(183, "net/minecraft/client/renderer/DynamicUniforms", "<init>", "()V", false);
                            this.visitFieldInsn(179, "com/mojang/blaze3d/systems/RenderSystem", "dynamicUniforms", "Lnet/minecraft/client/renderer/DynamicUniforms;");
                            this.visitFieldInsn(178, "com/mojang/blaze3d/systems/RenderSystem", "samplerCache", "Lcom/mojang/blaze3d/systems/SamplerCache;");
                            this.visitMethodInsn(182, "com/mojang/blaze3d/systems/SamplerCache", "initialize", "()V", false);
                            this.visitInsn(177);
                            this.visitLabel(label);
                        }
                    };
                }
                if ("initRenderer".equals(string) && string2.startsWith("(JIZL") && string2.endsWith(";Z)V")) {
                    String string4 = string2.substring("(JIZL".length(), string2.length() - ";Z)V".length());
                    System.out.println("[MetallumAgent] patching RenderSystem.initRenderer (param4=" + string4 + ")");
                    final String string5 = string4;
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            Label label = new Label();
                            this.visitMethodInsn(184, "com/metallum/client/metal/render/MetalBackend", "isMetalHost", "()Z", false);
                            this.visitJumpInsn(153, label);
                            this.visitVarInsn(22, 0);
                            this.visitVarInsn(25, 4);
                            this.visitMethodInsn(184, "com/metallum/client/metal/render/MetalBackend", "createDevice", "(JL" + string5 + ";)Lcom/metallum/client/metal/render/MetalDevice;", false);
                            this.visitFieldInsn(179, "com/mojang/blaze3d/systems/RenderSystem", "DEVICE", "Lcom/mojang/blaze3d/systems/GpuDevice;");
                            this.visitMethodInsn(184, "com/mojang/blaze3d/systems/RenderSystem", "getDevice", "()Lcom/mojang/blaze3d/systems/GpuDevice;", false);
                            this.visitMethodInsn(185, "com/mojang/blaze3d/systems/GpuDevice", "getImplementationInformation", "()Ljava/lang/String;", true);
                            this.visitFieldInsn(179, "com/mojang/blaze3d/systems/RenderSystem", "apiDescription", "Ljava/lang/String;");
                            if (rsDynamicUniformsDesc != null) {
                                String string = rsDynamicUniformsDesc.substring(1, rsDynamicUniformsDesc.length() - 1);
                                this.visitTypeInsn(187, string);
                                this.visitInsn(89);
                                this.visitMethodInsn(183, string, "<init>", "()V", false);
                                this.visitFieldInsn(179, "com/mojang/blaze3d/systems/RenderSystem", "dynamicUniforms", rsDynamicUniformsDesc);
                            }
                            if (string5.equals("fyy")) {
                                this.visitFieldInsn(178, "com/mojang/blaze3d/systems/RenderSystem", "samplerCache", "Lfzb;");
                                this.visitMethodInsn(182, "fzb", "a", "()V", false);
                            }
                            this.visitInsn(177);
                            this.visitLabel(label);
                        }
                    };
                }
                if ("setGlobalSettingsUniform".equals(string) && string2.equals("(Lcom/mojang/blaze3d/buffers/GpuBuffer;)V")) {
                    System.out.println("[MetallumAgent] patching RenderSystem.setGlobalSettingsUniform");
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            this.visitVarInsn(25, 0);
                            this.visitMethodInsn(184, "com/metallum/client/metal/render/MetalBackend", "setGlobalSettingsBuffer", "(Lcom/mojang/blaze3d/buffers/GpuBuffer;)V", false);
                        }
                    };
                }
                if (MC_VERSION.startsWith("1.21.") && "flipFrame".equals(string) && (n & 8) != 0) {
                    System.out.println("[MetallumAgent] patching RenderSystem.flipFrame");
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitMethodInsn(int n, String string, String string2, String string3, boolean bl) {
                            if (n == 184 && string.equals("org/lwjgl/glfw/GLFW") && string2.equals("glfwSwapBuffers")) {
                                super.visitInsn(88);
                                System.out.println("[MetallumAgent] flipFrame: glfwSwapBuffers skipped");
                                return;
                            }
                            super.visitMethodInsn(n, string, string2, string3, bl);
                        }
                    };
                }
                return methodVisitor;
            }
        }, 8);
        return classWriter.toByteArray();
    }

    private static byte[] patchMacosUtil(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (string.equals("disableCloseWindowMenuItem") || string.equals("setFullscreenMenuVisibility") || string.equals("setCtrlClickEmulatesRightClick")) {
                    return new MethodVisitor(this, 589824, methodVisitor){
                        private boolean codeDone = false;

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            super.visitInsn(177);
                            super.visitMaxs(0, 0);
                            this.codeDone = true;
                        }

                        @Override
                        public void visitInsn(int n) {
                            if (!this.codeDone) {
                                super.visitInsn(n);
                            }
                        }

                        @Override
                        public void visitIntInsn(int n, int n2) {
                        }

                        @Override
                        public void visitVarInsn(int n, int n2) {
                        }

                        @Override
                        public void visitTypeInsn(int n, String string) {
                        }

                        @Override
                        public void visitFieldInsn(int n, String string, String string2, String string3) {
                        }

                        @Override
                        public void visitMethodInsn(int n, String string, String string2, String string3, boolean bl) {
                        }

                        @Override
                        public void visitInvokeDynamicInsn(String string, String string2, Handle handle, Object ... objectArray) {
                        }

                        @Override
                        public void visitJumpInsn(int n, Label label) {
                        }

                        @Override
                        public void visitLabel(Label label) {
                        }

                        @Override
                        public void visitLdcInsn(Object object) {
                        }

                        @Override
                        public void visitIincInsn(int n, int n2) {
                        }

                        @Override
                        public void visitTableSwitchInsn(int n, int n2, Label label, Label ... labelArray) {
                        }

                        @Override
                        public void visitLookupSwitchInsn(Label label, int[] nArray, Label[] labelArray) {
                        }

                        @Override
                        public void visitMultiANewArrayInsn(String string, int n) {
                        }

                        @Override
                        public void visitTryCatchBlock(Label label, Label label2, Label label3, String string) {
                        }

                        @Override
                        public void visitLineNumber(int n, Label label) {
                        }

                        @Override
                        public void visitFrame(int n, int n2, Object[] objectArray, int n3, Object[] objectArray2) {
                        }

                        @Override
                        public void visitMaxs(int n, int n2) {
                        }
                    };
                }
                return methodVisitor;
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchMinecraftBackend(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 1);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitTypeInsn(int n, String string) {
                        if (n == 187 && string.equals("com/mojang/blaze3d/opengl/GlBackend")) {
                            System.out.println("[MetallumAgent] Minecraft: new GlBackend() -> MetalBackend");
                            super.visitTypeInsn(n, "com/metallum/client/metal/render/MetalBackend");
                            return;
                        }
                        super.visitTypeInsn(n, string);
                    }

                    @Override
                    public void visitMethodInsn(int n, String string, String string2, String string3, boolean bl) {
                        if (n == 183 && string.equals("com/mojang/blaze3d/opengl/GlBackend") && string2.equals("<init>")) {
                            super.visitMethodInsn(n, "com/metallum/client/metal/render/MetalBackend", string2, string3, bl);
                            return;
                        }
                        super.visitMethodInsn(n, string, string2, string3, bl);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchPreferredGraphicsApi263(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = MetallumAgent.newCW(classReader);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitTypeInsn(int n, String string) {
                        if (n == 187 && string.equals("com/mojang/renderpearl/backend/opengl/GlBackend")) {
                            System.out.println("[MetallumAgent] PreferredGraphicsApi: new GlBackend() -> MetalBackend (26.3)");
                            super.visitTypeInsn(n, "com/metallum/client/metal/render/MetalBackend");
                            return;
                        }
                        super.visitTypeInsn(n, string);
                    }

                    @Override
                    public void visitMethodInsn(int n, String string, String string2, String string3, boolean bl) {
                        if (n == 183 && string.equals("com/mojang/renderpearl/backend/opengl/GlBackend") && string2.equals("<init>")) {
                            super.visitMethodInsn(n, "com/metallum/client/metal/render/MetalBackend", string2, string3, bl);
                            return;
                        }
                        super.visitMethodInsn(n, string, string2, string3, bl);
                    }
                };
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static byte[] patchGpuTextureCtor(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 0);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public void visitEnd() {
                super.visitEnd();
                MethodVisitor methodVisitor = super.visitMethod(1, "<init>", "(ILjava/lang/String;Lcom/mojang/blaze3d/textures/TextureFormat;IIII)V", null, null);
                methodVisitor.visitCode();
                methodVisitor.visitVarInsn(25, 0);
                methodVisitor.visitVarInsn(25, 2);
                methodVisitor.visitVarInsn(25, 3);
                methodVisitor.visitVarInsn(21, 4);
                methodVisitor.visitVarInsn(21, 5);
                methodVisitor.visitVarInsn(21, 6);
                methodVisitor.visitMethodInsn(183, "com/mojang/blaze3d/textures/GpuTexture", "<init>", "(Ljava/lang/String;Lcom/mojang/blaze3d/textures/TextureFormat;III)V", false);
                methodVisitor.visitInsn(177);
                methodVisitor.visitMaxs(6, 8);
                methodVisitor.visitEnd();
                System.out.println("[MetallumAgent] GpuTexture 7-arg ctor added");
            }
        }, 0);
        return classWriter.toByteArray();
    }

    private static boolean glfwSkipInjectable() {
        try {
            byte[] byArray = MetallumAgent.readClassResource(MetallumAgent.classes12111Prefix(), "com/metallum/client/metal/render/MetalBackend");
            ClassReader classReader = new ClassReader(byArray);
            String string = classReader.getSuperName();
            if (string != null && !"java/lang/Object".equals(string)) {
                System.out.println("[MetallumAgent] glfw probe: MetalBackend \u7ee7\u627f " + string + " \u21d2 \u4e0d\u6ce8\u5165");
                return false;
            }
            for (String string2 : classReader.getInterfaces()) {
                if (string2.startsWith("java/") || string2.startsWith("javax/")) continue;
                System.out.println("[MetallumAgent] glfw probe: MetalBackend \u5b9e\u73b0\u975e JDK \u63a5\u53e3 " + string2 + " \u21d2 \u4e0d\u6ce8\u5165");
                return false;
            }
            final boolean[] blArray = new boolean[]{false};
            classReader.accept(new ClassVisitor(589824){

                @Override
                public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                    if ("isMetalHost".equals(string) && "()Z".equals(string2) && (n & 8) != 0 && (n & 1) != 0) {
                        blArray[0] = true;
                    }
                    return null;
                }
            }, 7);
            if (!blArray[0]) {
                System.out.println("[MetallumAgent] glfw probe: MetalBackend \u65e0 public static isMetalHost()Z \u21d2 \u4e0d\u6ce8\u5165");
            }
            return blArray[0];
        }
        catch (Throwable throwable) {
            System.out.println("[MetallumAgent] glfw probe failed (" + String.valueOf(throwable) + ") \u21d2 \u4e0d\u6ce8\u5165");
            return false;
        }
    }

    private static byte[] patchGLFW(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = MetallumAgent.newCW(classReader);
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (("glfwSwapBuffers".equals(string) || "glfwTerminate".equals(string)) && (n & 8) != 0) {
                    System.out.println("[MetallumAgent] patching GLFW." + string);
                    return new MethodVisitor(this, 589824, methodVisitor){

                        @Override
                        public void visitCode() {
                            super.visitCode();
                            Label label = new Label();
                            this.visitMethodInsn(184, "com/metallum/client/metal/render/MetalBackend", "isMetalHost", "()Z", false);
                            this.visitJumpInsn(153, label);
                            this.visitInsn(177);
                            this.visitLabel(label);
                        }
                    };
                }
                return methodVisitor;
            }
        }, 8);
        return classWriter.toByteArray();
    }

    @Override
    public byte[] transform(ClassLoader classLoader, String string, Class<?> clazz, ProtectionDomain protectionDomain, byte[] byArray) {
        MetallumAgent.resolveMcVersionOnce(classLoader);
        if ("net/minecraft/client/MouseHandler".equals(string)) {
            try {
                return MetallumAgent.patchMouseHandler(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] MouseHandler probe patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ("com/github/caciocavallosilano/cacio/ctc/CTCAndroidInput".equals(string)) {
            try {
                return MetallumAgent.patchCtcAndroidInput(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] CTCAndroidInput patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if (MC_VERSION.contains("26.1") && "com/mojang/blaze3d/audio/CallbackDeviceTracker".equals(string)) {
            try {
                return MetallumAgent.patchCallbackDeviceTracker261(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] CallbackDeviceTracker patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if (!IS_METAL_RENDERER) {
            if (string != null && string.startsWith("net/minecraft/")) {
                MetallumAgent.ensure12111(classLoader);
            }
            return null;
        }
        if ("com/mojang/blaze3d/platform/Window".equals(string)) {
            try {
                return MetallumAgent.patchWindowFocus263(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] Window focus patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if (MC_VERSION.contains("26.1") && "net/minecraft/client/Minecraft".equals(string)) {
            try {
                MetallumAgent.ensure12111(classLoader);
                byte[] byArray2 = MetallumAgent.patchMinecraftBackend(byArray);
                return MetallumAgent.patchMinecraftSetScreen261(MetallumAgent.patchMinecraftTickProbe263(byArray2));
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] 26.1 Minecraft(backend+ios) patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && "net/minecraft/client/Minecraft".equals(string)) {
            try {
                return MetallumAgent.patchMinecraftTickProbe263(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] Minecraft tick probe failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && "net/minecraft/client/gui/screens/social/PresenceHandler".equals(string)) {
            try {
                return MetallumAgent.patchPresenceHandler263(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] PresenceHandler patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && "net/minecraft/client/gui/screens/GenericMessageScreen".equals(string)) {
            try {
                return MetallumAgent.patchGenericMessage263(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] GenericMessageScreen patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && "net/minecraft/client/DeltaTracker$Timer".equals(string)) {
            try {
                return MetallumAgent.patchTimerProbe263(byArray, string.substring(string.lastIndexOf(47) + 1));
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] timer probe failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && ("net/minecraft/client/gui/screens/LoadingOverlay".equals(string) || "net/minecraft/client/gui/Gui".equals(string))) {
            try {
                return MetallumAgent.patchTickTracing263(byArray, string.substring(string.lastIndexOf(47) + 1));
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] tick tracing patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && "net/minecraft/client/gui/Gui".equals(string)) {
            try {
                return MetallumAgent.patchGuiSetOverlay263(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] Gui patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && "net/minecraft/client/renderer/extract/LevelExtractor".equals(string)) {
            try {
                return MetallumAgent.patchLevelExtractor263(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] LevelExtractor probe patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ((MC_VERSION.contains("26.3") || MC_VERSION.contains("26.")) && "net/minecraft/client/Minecraft".equals(string)) {
            try {
                return MetallumAgent.patchMinecraftProbe263(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] Minecraft probe263 patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ("net/minecraftforge/client/loading/ForgeLoadingOverlay".equals(string)) {
            try {
                return MetallumAgent.patchForgeLoadingOverlay(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] ForgeLoadingOverlay patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if (MC_VERSION.contains("26.1") && "net/minecraft/client/Minecraft".equals(string)) {
            try {
                MetallumAgent.ensure12111(classLoader);
                return MetallumAgent.patchMinecraftBackend(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] Minecraft backend patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ("com/mojang/blaze3d/systems/RenderSystem".equals(string)) {
            try {
                MetallumAgent.ensure12111(classLoader);
                return MetallumAgent.patchRenderSystem(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] RenderSystem patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ("com/mojang/blaze3d/textures/GpuTexture".equals(string) && MC_VERSION.contains("1.21.") && !MC_VERSION.contains("1.21.11")) {
            return null;
        }
        if ("org/lwjgl/glfw/GLFW".equals(string)) {
            try {
                if (!MetallumAgent.glfwSkipInjectable()) {
                    System.out.println("[MetallumAgent] GLFW skip patch disabled for class set '" + MetallumAgent.classes12111Prefix() + "' (\u65e0 isMetalHost \u6216\u975e\u7eaf JDK \u7c7b)");
                    return null;
                }
                MetallumAgent.ensure12111(classLoader);
                return MetallumAgent.patchGLFW(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] GLFW patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ("net/minecraftforge/fml/loading/ImmediateWindowHandler".equals(string) && MetallumAgent.isForgeLoaderPresent() && !MC_VERSION.contains("1.21") && !MC_VERSION.contains("26.1") && !MC_VERSION.contains("26.3")) {
            try {
                return MetallumAgent.patchForgeEarlyWindowDummy(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] FIX462 earlydisplay dummy patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if ("com/mojang/blaze3d/platform/MacosUtil".equals(string)) {
            try {
                MetallumAgent.ensure12111(classLoader);
                return MetallumAgent.patchMacosUtil(byArray);
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] MacosUtil patch failed: " + String.valueOf(throwable));
                return null;
            }
        }
        if (ACCESSIBLE_CLASSES.contains(string)) {
            try {
                ClassReader classReader = new ClassReader(byArray);
                ClassWriter classWriter = new ClassWriter(classReader, 0);
                classReader.accept(new ClassVisitor(this, 589824, classWriter){

                    @Override
                    public void visit(int n, int n2, String string, String string2, String string3, String[] stringArray) {
                        super.visit(n, MetallumAgent.pub(n2), string, string2, string3, stringArray);
                    }

                    @Override
                    public FieldVisitor visitField(int n, String string, String string2, String string3, Object object) {
                        return super.visitField(MetallumAgent.pub(n), string, string2, string3, object);
                    }

                    @Override
                    public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                        return super.visitMethod(MetallumAgent.pub(n), string, string2, string3, stringArray);
                    }
                }, 0);
                System.out.println("[MetallumAgent] accesswidener applied: " + string);
                return classWriter.toByteArray();
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] accesswidener failed for " + string + ": " + String.valueOf(throwable));
                return null;
            }
        }
        if (!TARGET.equals(string)) {
            return null;
        }
        try {
            ClassLoader classLoader2;
            ClassLoader classLoader3 = classLoader2 = protectionDomain != null ? protectionDomain.getClassLoader() : null;
            MetallumAgent.ensureDefineAccess();
            if (MetallumAgent.isForgeLoaderPresent()) {
                if (classLoader != null) {
                    classLoader3 = classLoader;
                }
                System.out.println("[MetallumAgent] FIX460 forge define target: transformLoader=" + String.valueOf(classLoader) + " pdLoader=" + String.valueOf(classLoader2));
            }
            if (classLoader3 != null) {
                MetallumAgent.defineMetallumClasses(classLoader3, MetallumAgent.classes12111Prefix());
            }
            if (MC_VERSION.contains("26.3")) {
                return MetallumAgent.patchPreferredGraphicsApi263(byArray);
            }
            ClassReader classReader = new ClassReader(byArray);
            ClassWriter classWriter = MetallumAgent.newCW(classReader);
            final boolean bl = MetallumAgent.isForgeLoaderPresent();
            classReader.accept(new ClassVisitor(this, 589824, classWriter){

                @Override
                public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                    MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                    System.out.println("[MetallumAgent] method: " + string + " " + string2);
                    if ("getBackendsToTry".equals(string) && string2.startsWith("()[L") && string2.endsWith("GpuBackend;")) {
                        if (bl) {
                            return MetallumAgent.injectGuarded(methodVisitor, n, string, string2, "getBackendsToTry", "(Ljava/lang/Object;)[Ljava/lang/Object;");
                        }
                        return MetallumAgent.inject(methodVisitor, n, string, string2, "getBackendsToTry", "(Ljava/lang/Object;)[Ljava/lang/Object;");
                    }
                    if ("caption".equals(string) && string2.startsWith("()L") && string2.endsWith("Component;")) {
                        if (bl) {
                            return MetallumAgent.injectGuarded(methodVisitor, n, string, string2, "caption", "(Ljava/lang/Object;)Lnet/minecraft/network/chat/Component;");
                        }
                        return MetallumAgent.inject(methodVisitor, n, string, string2, "caption", "(Ljava/lang/Object;)Lnet/minecraft/network/chat/Component;");
                    }
                    return methodVisitor;
                }
            }, 8);
            System.out.println("[MetallumAgent] injected net/minecraft/client/PreferredGraphicsApi");
            return classWriter.toByteArray();
        }
        catch (Throwable throwable) {
            System.err.println("[MetallumAgent] transform failed: " + String.valueOf(throwable));
            throwable.printStackTrace(System.err);
            return null;
        }
    }

    private static boolean shouldInjectBundledSlf4j(ClassLoader classLoader, String string) {
        if (string == null || string.isEmpty()) {
            return false;
        }
        if (MetallumAgent.isForgeLoaderPresent()) {
            System.out.println("[MetallumAgent] FIX457 skip bundled slf4j: Forge/ModLauncher present (module path \u81ea\u5e26 org.slf4j, \u6ce8\u5165\u4f1a\u9020\u6210 loader constraint violation)");
            return false;
        }
        ClassLoader classLoader2 = classLoader != null ? classLoader : ClassLoader.getSystemClassLoader();
        try {
            Class.forName("org.slf4j.LoggerFactory", false, classLoader2);
            System.out.println("[MetallumAgent] FIX457 skip bundled slf4j: org.slf4j.LoggerFactory already visible on target loader " + String.valueOf(classLoader2));
            return false;
        }
        catch (Throwable throwable) {
            System.out.println("[MetallumAgent] FIX457 bundled slf4j needed: org.slf4j.LoggerFactory not visible on target loader " + String.valueOf(classLoader2));
            return true;
        }
    }

    private static void defineMetallumClasses(ClassLoader classLoader) {
        MetallumAgent.defineMetallumClasses(classLoader, "");
    }

    private static void defineMetallumClasses(ClassLoader classLoader, String string) {
        try {
            java.lang.reflect.Method method = ClassLoader.class.getDeclaredMethod("defineClass", String.class, byte[].class, Integer.TYPE, Integer.TYPE);
            method.setAccessible(true);
            gDefineClassMethod = method;
            ArrayList<String> arrayList = new ArrayList<String>();
            int n = arrayList.size();
            if (MetallumAgent.shouldInjectBundledSlf4j(classLoader, string)) {
                MetallumAgent.collectClassNames(string + "org/slf4j/", arrayList, string);
            }
            System.out.println("[MetallumAgent] FIX263 slf4j classes queued first: " + (arrayList.size() - n) + " (resPrefix=" + string + ")");
            int n2 = 0;
            for (String object22 : new String[]{"net/fabricmc/api/ModInitializer", "net/fabricmc/api/EnvType", "net/fabricmc/api/Environment", "net/fabricmc/loader/api/entrypoint/PreLaunchEntrypoint"}) {
                boolean string2;
                if (MetallumAgent.readClassResource(string, object22) == null) {
                    System.out.println("[MetallumAgent] FIX461 fabric stub absent (skip, not fatal): " + object22);
                    continue;
                }
                try {
                    Class.forName(object22.replace('/', '.'), false, classLoader == null ? ClassLoader.getSystemClassLoader() : classLoader);
                    string2 = true;
                }
                catch (Throwable throwable) {
                    string2 = false;
                }
                if (string2) continue;
                arrayList.add(object22);
                ++n2;
                System.out.println("[MetallumAgent] FIX407 fabricmc type not visible on target loader -> bundled copy queued first: " + object22);
            }
            System.out.println("[MetallumAgent] FIX407 fabricmc api probe done: bundled stubs queued = " + n2 + " (0 = loader/classpath \u5df2\u63d0\u4f9b, \u539f\u7248\u8def\u7ebf\u4e5f\u4e0d\u518d\u7f3a\u63a5\u53e3)");
            arrayList.add("com/metallum/client/metal/render/mtl/MTLCommandEncoder");
            MetallumAgent.collectClassNames(string + "com/mojang/blaze3d/", arrayList, string);
            boolean bl = false;
            try {
                Class.forName("org.lwjgl.sdl.SDL", false, classLoader);
                bl = true;
            }
            catch (Throwable throwable) {
                // empty catch block
            }
            if (bl) {
                System.out.println("[MetallumAgent] real org.lwjgl.sdl binding detected - SDL stubs skipped");
            } else {
                System.out.println("[MetallumAgent] no real org.lwjgl.sdl - falling back to SDL stubs");
                MetallumAgent.collectClassNames(string + "org/lwjgl/sdl/", arrayList, string);
            }
            MetallumAgent.collectClassNames(string + "com/metallum/shims/", arrayList, string);
            MetallumAgent.collectClassNames(string + "com/metallum/client/", arrayList, string);
            if (MetallumAgent.readClassResource(string, "com/metallum/Metallum") != null) {
                arrayList.add("com/metallum/Metallum");
                System.out.println("[MetallumAgent] bundled com.metallum.Metallum found, will define");
            } else {
                System.out.println("[MetallumAgent] no bundled com.metallum.Metallum in " + string + " (fabric mod provides it)");
            }
            if (!MC_VERSION.contains("1.21.11") && MC_VERSION.contains("1.21.")) {
                arrayList.add("net/minecraft/class_12137");
            }
            if (!(MC_VERSION.contains("1.21.") || MC_VERSION.contains("26.1") || MC_VERSION.contains("26.3"))) {
                arrayList.add("com/metallum/agent/MetallumAgentHelper");
            }
            ArrayList<String> arrayList2 = new ArrayList<String>();
            HashSet<String> hashSet = new HashSet<String>();
            for (String string2 : new ArrayList<String>(arrayList)) {
                if (!hashSet.add(string2)) continue;
                arrayList2.add(string2);
            }
            ArrayList<String> arrayList3 = arrayList = arrayList2;
            int n3 = arrayList.size();
            System.out.println("[MetallumAgent] define target loader = " + String.valueOf(classLoader) + " parent=" + String.valueOf(classLoader == null ? null : classLoader.getParent()));
            boolean[] blArray = new boolean[]{true};
            for (int i = 0; i < 8 && !arrayList3.isEmpty(); ++i) {
                Object object = arrayList3.iterator();
                while (object.hasNext()) {
                    Object object2;
                    String string3 = (String)object.next();
                    try {
                        byte[] byArray = MetallumAgent.readClassResource(string, string3);
                        if (byArray == null) {
                            System.out.println("[MetallumAgent] FIX461 class resource missing, skipped: " + string3 + " (resPrefix=" + string + ")");
                            object.remove();
                            continue;
                        }
                        if (string3.endsWith("com/metallum/client/metal/render/MetalDevice$2")) {
                            try {
                                byArray = MetallumAgent.injectThrowableTrace(byArray, "finishCompile");
                                System.out.println("[MetallumAgent] injected stack trace into " + string3 + ".finishCompile");
                            }
                            catch (Throwable throwable) {
                                System.err.println("[MetallumAgent] stack-trace injection failed: " + String.valueOf(throwable));
                            }
                        }
                        if (((String)(object2 = new String(byArray, StandardCharsets.ISO_8859_1))).contains("net/caffeinemc/mods/sodium")) {
                            System.out.println("[MetallumAgent] skip sodium-dependent class: " + string3);
                            object.remove();
                            continue;
                        }
                        String string4 = string3.replace('/', '.');
                        String string5 = System.identityHashCode(classLoader) + "|" + string4;
                        if (gDefinedClasses.contains(string5)) {
                            object.remove();
                            continue;
                        }
                        try {
                            method.invoke(classLoader, string4, byArray, 0, byArray.length);
                            gDefinedClasses.add(string5);
                            object.remove();
                        }
                        catch (InvocationTargetException invocationTargetException) {
                            String string6;
                            Throwable throwable = invocationTargetException.getCause();
                            String string7 = string6 = throwable == null ? "" : String.valueOf(throwable.getMessage());
                            if (throwable instanceof LinkageError && string6.contains("duplicate class definition")) {
                                System.out.println("[MetallumAgent] define skipped (already defined here): " + string3);
                                gDefinedClasses.add(string5);
                                object.remove();
                                continue;
                            }
                            if (throwable instanceof LinkageError) {
                                if (i >= 2) continue;
                                System.err.println("[MetallumAgent] define deferred (round " + i + "): " + string3 + " -> " + String.valueOf(throwable));
                                continue;
                            }
                            throw invocationTargetException;
                        }
                    }
                    catch (Throwable throwable) {
                        if (!blArray[0]) continue;
                        object2 = throwable instanceof InvocationTargetException && throwable.getCause() != null ? throwable.getCause() : throwable;
                        System.err.println("[MetallumAgent] define failed (round1): " + string3 + " -> " + String.valueOf(object2));
                        ((Throwable)object2).printStackTrace(System.err);
                    }
                }
                blArray[0] = false;
            }
            if (!arrayList3.isEmpty()) {
                System.err.println("[MetallumAgent] defineClass incomplete, still missing: " + String.valueOf(arrayList3));
                gDeferLoader = classLoader;
                gDeferPrefix = string;
                for (Object object : arrayList3) {
                    gDeferredDefine.add((String)object);
                }
                System.err.println("[MetallumAgent] FIX407 deferred define scheduled: " + gDeferredDefine.size() + " class(es) pending; target loader = " + String.valueOf(classLoader) + ", prefix = " + string);
                MetallumAgent.startDeferRetryThread();
            } else {
                System.out.println("[MetallumAgent] defined metallum classes into MC loader (" + arrayList.size() + ")");
            }
        }
        catch (Throwable throwable) {
            System.err.println("[MetallumAgent] defineMetallumClasses failed: " + String.valueOf(throwable));
        }
    }

    private static void startDeferRetryThread() {
        if (!gDeferRetryStarted.compareAndSet(false, true)) {
            return;
        }
        Thread thread = new Thread(new Runnable(){

            @Override
            public void run() {
                long l = System.currentTimeMillis();
                int n = 0;
                while (n < 300 && !gDeferredDefine.isEmpty()) {
                    String string;
                    ++n;
                    try {
                        Thread.sleep(n <= 10 ? 25L : 100L);
                    }
                    catch (InterruptedException interruptedException) {
                        return;
                    }
                    java.lang.reflect.Method method = gDefineClassMethod;
                    ClassLoader classLoader = gDeferLoader;
                    String string2 = string = gDeferPrefix == null ? "" : gDeferPrefix;
                    if (method == null || classLoader == null) continue;
                    ArrayList<String> arrayList = new ArrayList<String>();
                    for (String string3 : new ArrayList<String>(gDeferredDefine)) {
                        String string4 = string3.replace('/', '.');
                        String string5 = System.identityHashCode(classLoader) + "|" + string4;
                        if (gDefinedClasses.contains(string5)) {
                            gDeferredDefine.remove(string3);
                            continue;
                        }
                        try {
                            byte[] byArray = MetallumAgent.readClassResource(string, string3);
                            if (byArray == null) {
                                gDeferredDefine.remove(string3);
                                continue;
                            }
                            method.invoke(classLoader, string4, byArray, 0, byArray.length);
                            gDefinedClasses.add(string5);
                            gDeferredDefine.remove(string3);
                        }
                        catch (Throwable throwable) {
                            arrayList.add(string3);
                        }
                    }
                    if (arrayList.isEmpty()) {
                        System.out.println("[MetallumAgent] FIX407 deferred define completed after " + n + " attempt(s) (~" + (System.currentTimeMillis() - l) + " ms): all pending classes now defined (loader=" + String.valueOf(classLoader) + ")");
                        continue;
                    }
                    if (n < 300) continue;
                    System.err.println("[MetallumAgent] FIX407 deferred define gave up after " + n + " attempt(s) (~" + (System.currentTimeMillis() - l) + " ms), still missing: " + String.valueOf(arrayList));
                }
            }
        }, "MetallumAgent-DeferDefine");
        thread.setDaemon(true);
        thread.start();
        System.out.println("[MetallumAgent] FIX407 defer-define retry thread started (25ms x10 then 100ms, max 300)");
    }

    private static void collectClassNames(String string, List<String> list, String string2) {
        try {
            URL uRL = MetallumAgent.class.getProtectionDomain().getCodeSource().getLocation();
            if (uRL == null) {
                return;
            }
            File file = new File(uRL.toURI());
            if (!file.isFile()) {
                return;
            }
            try (JarFile jarFile = new JarFile(file);){
                Enumeration<JarEntry> enumeration = jarFile.entries();
                while (enumeration.hasMoreElements()) {
                    String string3 = enumeration.nextElement().getName();
                    if (!string3.startsWith(string) || !string3.endsWith(".class") || string3.equals("com/metallum/client/metal/render/mtl/MTLCommandEncoder.class")) continue;
                    list.add(string3.substring(string2.length(), string3.length() - 6));
                }
            }
        }
        catch (Throwable throwable) {
            System.err.println("[MetallumAgent] collectClassNames failed: " + String.valueOf(throwable));
        }
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    private static byte[] readAgentResourceOrNull(String string) {
        byte[] byArray;
        InputStream inputStream = MetallumAgent.class.getClassLoader().getResourceAsStream(string);
        if (inputStream == null) {
            return null;
        }
        try {
            int n;
            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            byte[] byArray2 = new byte[8192];
            while ((n = inputStream.read(byArray2)) > 0) {
                byteArrayOutputStream.write(byArray2, 0, n);
            }
            byArray = byteArrayOutputStream.toByteArray();
        }
        catch (Throwable throwable) {
            try {
                inputStream.close();
                throw throwable;
            }
            catch (Throwable throwable2) {
                return null;
            }
        }
        inputStream.close();
        return byArray;
    }

    private static byte[] readClassResource(String string, String string2) {
        String string3 = string == null ? "" : string;
        byte[] byArray = MetallumAgent.readAgentResourceOrNull(string3 + string2 + ".class");
        if (byArray != null) {
            return byArray;
        }
        if (!string3.isEmpty() && (byArray = MetallumAgent.readAgentResourceOrNull(string2 + ".class")) != null) {
            System.out.println("[MetallumAgent] FIX461 classset(" + string3 + ") miss -> root fallback: " + string2);
        }
        return byArray;
    }

    private static byte[] readAgentResource(String string) throws Exception {
        byte[] byArray = MetallumAgent.readAgentResourceOrNull(string);
        if (byArray == null) {
            throw new FileNotFoundException(string);
        }
        return byArray;
    }

    private static MethodVisitor inject(MethodVisitor methodVisitor, int n, String string, String string2, final String string3, final String string4) {
        final Type type = Type.getReturnType(string2);
        final boolean bl = type.getSort() == 9;
        return new AdviceAdapter(589824, methodVisitor, n, string, string2){

            @Override
            protected void onMethodEnter() {
                this.loadThis();
                this.invokeStatic(Type.getObjectType("com/metallum/agent/MetallumAgentHelper"), new Method(string3, string4));
                this.dup();
                Label label = new Label();
                this.ifNull(label);
                if (bl) {
                    this.checkCast(type);
                }
                this.returnValue();
                this.visitLabel(label);
                this.pop();
            }
        };
    }

    private static MethodVisitor injectGuarded(MethodVisitor methodVisitor, int n, String string, String string2, final String string3, final String string4) {
        final Type type = Type.getReturnType(string2);
        final boolean bl = type.getSort() == 9;
        final int n2 = Type.getArgumentsAndReturnSizes(string2) >> 2;
        return new MethodVisitor(589824, methodVisitor){

            @Override
            public void visitCode() {
                super.visitCode();
                Label label = new Label();
                Label label2 = new Label();
                Label label3 = new Label();
                Label label4 = new Label();
                this.visitTryCatchBlock(label, label2, label3, "java/lang/Throwable");
                this.visitLabel(label);
                this.visitVarInsn(25, 0);
                this.visitMethodInsn(184, "com/metallum/agent/MetallumAgentHelper", string3, string4, false);
                this.visitVarInsn(58, n2);
                this.visitVarInsn(25, n2);
                Label label5 = new Label();
                this.visitJumpInsn(198, label5);
                this.visitVarInsn(25, n2);
                if (bl) {
                    this.visitTypeInsn(192, type.getInternalName());
                }
                this.visitInsn(176);
                this.visitLabel(label5);
                this.visitLabel(label2);
                this.visitJumpInsn(167, label4);
                this.visitLabel(label3);
                this.visitFieldInsn(178, "java/lang/System", "err", "Ljava/io/PrintStream;");
                this.visitLdcInsn("[MetallumAgent] FIX460 forge: helper call failed, fallback to vanilla: ");
                this.visitMethodInsn(182, "java/io/PrintStream", "print", "(Ljava/lang/String;)V", false);
                this.visitFieldInsn(178, "java/lang/System", "err", "Ljava/io/PrintStream;");
                this.visitInsn(95);
                this.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/Object;)V", false);
                this.visitLabel(label4);
            }
        };
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    private static boolean ensureDefineAccess() {
        if (gDefineAccessOpened) {
            return true;
        }
        Instrumentation instrumentation = gInst;
        if (instrumentation == null) {
            return false;
        }
        Class<MetallumAgent> clazz = MetallumAgent.class;
        synchronized (MetallumAgent.class) {
            if (gDefineAccessOpened) {
                // ** MonitorExit[var1_1] (shouldn't be in output)
                return true;
            }
            try {
                Module module = MetallumAgent.class.getModule();
                System.out.println("[MetallumAgent] FIX460 agent module = " + String.valueOf(module) + " named=" + module.isNamed() + " loader=" + String.valueOf(MetallumAgent.class.getClassLoader()));
                if (!module.isNamed()) {
                    gDefineAccessOpened = true;
                    // ** MonitorExit[var1_1] (shouldn't be in output)
                    return true;
                }
                Set set = Set.of();
                Map map = Map.of();
                Set set2 = Set.of((Object)"java.lang", (Object)"java.lang.reflect");
                Map map2 = Map.of((Object)"java.base", (Object)set2);
                Set set3 = Set.of();
                Map map3 = Map.of();
                instrumentation.redefineModule(module, set, map, map2, set3, map3);
                gDefineAccessOpened = true;
                System.out.println("[MetallumAgent] FIX460 opened java.base/java.lang to module " + module.getName() + " (defineClass now accessible)");
                // ** MonitorExit[var1_1] (shouldn't be in output)
                return true;
            }
            catch (Throwable throwable) {
                System.err.println("[MetallumAgent] FIX460 redefineModule failed: " + String.valueOf(throwable));
                // ** MonitorExit[var1_1] (shouldn't be in output)
                return false;
            }
        }
    }

    private static byte[] patchGLMakeCurrentForge(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = MetallumAgent.newCW(classReader);
        final boolean[] blArray = new boolean[]{false};
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!"createCapabilities".equals(string) || !string2.startsWith("(Z")) {
                    return methodVisitor;
                }
                final int n2 = Type.getArgumentsAndReturnSizes(string2) >> 2;
                blArray[0] = true;
                return new MethodVisitor(this, 589824, methodVisitor){

                    @Override
                    public void visitCode() {
                        super.visitCode();
                        Label label = new Label();
                        Label label2 = new Label();
                        Label label3 = new Label();
                        Label label4 = new Label();
                        this.visitTryCatchBlock(label, label2, label3, "java/lang/Throwable");
                        this.visitLabel(label);
                        this.visitFieldInsn(178, "org/lwjgl/glfw/GLFW", "mainContext", "J");
                        this.visitVarInsn(55, n2);
                        this.visitVarInsn(22, n2);
                        this.visitInsn(9);
                        this.visitInsn(148);
                        Label label5 = new Label();
                        this.visitJumpInsn(153, label5);
                        this.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                        this.visitLdcInsn("[MetallumAgent] FIX460 forge: makeCurrent(earlydisplay thread) ctx=");
                        this.visitMethodInsn(182, "java/io/PrintStream", "print", "(Ljava/lang/String;)V", false);
                        this.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                        this.visitVarInsn(22, n2);
                        this.visitMethodInsn(182, "java/io/PrintStream", "println", "(J)V", false);
                        this.visitVarInsn(22, n2);
                        this.visitMethodInsn(184, "org/lwjgl/glfw/GLFW", "glfwMakeContextCurrent", "(J)V", false);
                        this.visitLabel(label5);
                        this.visitLabel(label2);
                        this.visitJumpInsn(167, label4);
                        this.visitLabel(label3);
                        this.visitInsn(87);
                        this.visitLabel(label4);
                    }
                };
            }
        }, 8);
        if (!blArray[0]) {
            System.out.println("[MetallumAgent] FIX460 GL: createCapabilities(Z...) not found, nothing patched");
            return null;
        }
        System.out.println("[MetallumAgent] FIX460 GL patched: makeContextCurrent before createCapabilities (Forge)");
        return classWriter.toByteArray();
    }

    private static byte[] patchForgeEarlyWindowDummy(byte[] byArray) {
        ClassReader classReader = new ClassReader(byArray);
        ClassWriter classWriter = new ClassWriter(classReader, 0);
        final boolean[] blArray = new boolean[]{false};
        classReader.accept(new ClassVisitor(589824, classWriter){

            @Override
            public MethodVisitor visitMethod(int n, String string, String string2, String string3, String[] stringArray) {
                final MethodVisitor methodVisitor = super.visitMethod(n, string, string2, string3, stringArray);
                if (!"load".equals(string) || !"(Ljava/lang/String;[Ljava/lang/String;)V".equals(string2)) {
                    return methodVisitor;
                }
                blArray[0] = true;
                return new MethodVisitor(this, 589824){

                    @Override
                    public void visitEnd() {
                        methodVisitor.visitCode();
                        methodVisitor.visitFieldInsn(178, "java/lang/System", "out", "Ljava/io/PrintStream;");
                        methodVisitor.visitLdcInsn("[MetallumAgent] FIX462 forge: earlydisplay -> dummyprovider (NoVizFallback; no GL thread; fml.toml / JVM args untouched)");
                        methodVisitor.visitMethodInsn(182, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
                        methodVisitor.visitMethodInsn(184, "net/minecraftforge/fml/loading/ImmediateWindowProvider", "getFallbackHandler", "()Lnet/minecraftforge/fml/loading/ImmediateWindowProvider;", true);
                        methodVisitor.visitFieldInsn(179, "net/minecraftforge/fml/loading/ImmediateWindowHandler", "provider", "Lnet/minecraftforge/fml/loading/ImmediateWindowProvider;");
                        methodVisitor.visitFieldInsn(178, "net/minecraftforge/fml/loading/ImmediateWindowHandler", "provider", "Lnet/minecraftforge/fml/loading/ImmediateWindowProvider;");
                        methodVisitor.visitVarInsn(25, 1);
                        methodVisitor.visitMethodInsn(185, "net/minecraftforge/fml/loading/ImmediateWindowProvider", "initialize", "([Ljava/lang/String;)Ljava/lang/Runnable;", true);
                        methodVisitor.visitFieldInsn(179, "net/minecraftforge/fml/loading/FMLLoader", "progressWindowTick", "Ljava/lang/Runnable;");
                        methodVisitor.visitLdcInsn("EARLY");
                        methodVisitor.visitInsn(3);
                        methodVisitor.visitMethodInsn(184, "net/minecraftforge/fml/loading/progress/StartupNotificationManager", "addProgressBar", "(Ljava/lang/String;I)Lnet/minecraftforge/fml/loading/progress/ProgressMeter;", false);
                        methodVisitor.visitFieldInsn(179, "net/minecraftforge/fml/loading/ImmediateWindowHandler", "earlyProgress", "Lnet/minecraftforge/fml/loading/progress/ProgressMeter;");
                        methodVisitor.visitFieldInsn(178, "net/minecraftforge/fml/loading/ImmediateWindowHandler", "earlyProgress", "Lnet/minecraftforge/fml/loading/progress/ProgressMeter;");
                        methodVisitor.visitLdcInsn("Bootstrapping Minecraft");
                        methodVisitor.visitMethodInsn(182, "net/minecraftforge/fml/loading/progress/ProgressMeter", "label", "(Ljava/lang/String;)V", false);
                        methodVisitor.visitInsn(177);
                        methodVisitor.visitMaxs(4, 2);
                        methodVisitor.visitEnd();
                    }
                };
            }
        }, 0);
        if (!blArray[0]) {
            System.out.println("[MetallumAgent] FIX462 earlydisplay: ImmediateWindowHandler.load(String,String[]) not found, nothing patched");
            return null;
        }
        System.out.println("[MetallumAgent] FIX462 earlydisplay patched: provider forced to dummyprovider (no earlydisplay thread, no GL context needed)");
        return classWriter.toByteArray();
    }

    static {
        TICK_TRACE = 0L;
        HEARTBEAT_COUNT = 0L;
        HEARTBEAT_LAST_MS = 0L;
        TRACE2 = 0L;
        RATE_STATE = new ConcurrentHashMap();
        TICK_LOG_COUNT = 0L;
        g12111Defined = false;
        gDefinedClasses = ConcurrentHashMap.newKeySet();
        gDeferredDefine = ConcurrentHashMap.newKeySet();
        gDeferRetryStarted = new AtomicBoolean(false);
        gDeferLoader = null;
        gDeferPrefix = null;
        gDefineClassMethod = null;
        MC_VERSION = MC_VERSION_PROP = System.getProperty("metallum.mc.version", "");
        gMcVersionResolved = MC_VERSION_PROP != null && !MC_VERSION_PROP.isEmpty();
        gMcVersionProbeTries = 0;
        IS_METAL_RENDERER = MetallumAgent.ameIsMetalRenderer();
        lastCursorX = Double.NaN;
        lastCursorY = Double.NaN;
        hasCursor = false;
        cursorXField = null;
        cursorYField = null;
    }
}

