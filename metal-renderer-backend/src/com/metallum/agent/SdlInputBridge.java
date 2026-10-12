/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.agent;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.HashSet;
import java.util.Set;

public final class SdlInputBridge {
    private static final int EVENT_TYPE_CHAR = 1000;
    private static final int EVENT_TYPE_CURSOR_POS = 1003;
    private static final int EVENT_TYPE_KEY = 1005;
    private static final int EVENT_TYPE_MOUSE_BUTTON = 1006;
    private static final int SDL_EVENT_MOUSE_MOTION = 1024;
    private static final int SDL_EVENT_MOUSE_BUTTON_DOWN = 1025;
    private static final int SDL_EVENT_MOUSE_BUTTON_UP = 1026;
    private static final int SDL_EVENT_KEY_DOWN = 768;
    private static final int SDL_EVENT_KEY_UP = 769;
    private static final int SDL_EVENT_TEXT_INPUT = 771;
    private static long sdlWindow = 0L;
    private static int sdlWindowId = 0;
    private static boolean inited = false;
    private static boolean unavailable = false;
    private static boolean winIdLogged = false;
    private static Class<?> cSdl;
    private static Class<?> cSdlVideo;
    private static Object bufEvent;
    private static long eventAddr;
    private static int eventSize;
    private static float lastX;
    private static float lastY;
    private static boolean hasLast;
    private static double scale;
    private static long lastMoveLog;
    private static int dispatchHits;
    private static boolean firstHitLogged;
    private static long injectedMouse;
    private static long injectedButton;
    private static long injectedKey;
    private static long injectedText;
    private static long droppedNoWindow;
    private static long droppedNoWindowId;
    private static long lastStatLog;
    private static final Set<Integer> SEEN_TYPES;
    private static final Set<Integer> SEEN_KEYCODES;
    private static volatile int buttonStateMask;
    private static final int SDL_SCANCODE_A = 4;
    private static final int SDL_SCANCODE_1 = 30;
    private static final int SDL_SCANCODE_0 = 39;

    private SdlInputBridge() {
    }

    public static void setWindowFromProperty() {
        try {
            long l;
            String string = System.getProperty("metallum.sdl.window");
            if (string != null && !string.isBlank() && (l = Long.parseLong(string.trim())) != sdlWindow) {
                sdlWindow = l;
                sdlWindowId = 0;
                winIdLogged = false;
            }
        }
        catch (Throwable throwable) {
            // empty catch block
        }
    }

    private static int resolveWindowId() {
        block7: {
            if (sdlWindowId != 0) {
                return sdlWindowId;
            }
            if (sdlWindow == 0L) {
                SdlInputBridge.setWindowFromProperty();
                if (sdlWindow == 0L) {
                    return 0;
                }
            }
            try {
                Method method = cSdlVideo.getMethod("SDL_GetWindowID", Long.TYPE);
                Object object = method.invoke(null, sdlWindow);
                if (object instanceof Number) {
                    sdlWindowId = ((Number)object).intValue();
                }
            }
            catch (Throwable throwable) {
                if (winIdLogged) break block7;
                winIdLogged = true;
                System.out.println("[MetallumAgent] SdlInputBridge SDL_GetWindowID failed: " + String.valueOf(throwable));
            }
        }
        if (sdlWindowId != 0 && !winIdLogged) {
            winIdLogged = true;
            System.out.println("[MetallumAgent] SdlInputBridge windowID resolved = " + sdlWindowId + " (SDL window = 0x" + Long.toHexString(sdlWindow) + ") [v421]");
        }
        return sdlWindowId;
    }

    private static synchronized boolean ensureInit() {
        if (inited) {
            return !unavailable;
        }
        inited = true;
        try {
            SdlInputBridge.setWindowFromProperty();
            ClassLoader classLoader = ClassLoader.getSystemClassLoader();
            cSdl = Class.forName("org.lwjgl.sdl.SDL", true, classLoader);
            cSdlVideo = Class.forName("org.lwjgl.sdl.SDLVideo", true, classLoader);
            Class<?> clazz = Class.forName("org.lwjgl.sdl.SDL_Event", true, classLoader);
            Field field = clazz.getField("SIZEOF");
            eventSize = field.getInt(null);
            if (eventSize < 52 || eventSize > 256) {
                unavailable = true;
                System.out.println("[MetallumAgent] SdlInputBridge: unexpected SDL_Event size " + eventSize + " - disabling input bridge (would corrupt events)");
                return false;
            }
            Class<?> clazz2 = Class.forName("org.lwjgl.system.MemoryUtil", true, classLoader);
            Method method = clazz2.getMethod("memAlloc", Integer.TYPE);
            Object object = method.invoke(null, eventSize * 2);
            if (object instanceof Long) {
                eventAddr = (Long)object;
            } else {
                Method method2 = clazz2.getMethod("memAddress", ByteBuffer.class);
                bufEvent = object;
                eventAddr = (Long)method2.invoke(null, object);
            }
            int n = SdlInputBridge.resolveWindowId();
            System.out.println("[MetallumAgent] SdlInputBridge ready (window=0x" + Long.toHexString(sdlWindow) + ", windowID=" + n + ", SDL_Event size=" + eventSize + ") [v421]");
            return true;
        }
        catch (Throwable throwable) {
            unavailable = true;
            System.out.println("[MetallumAgent] SdlInputBridge unavailable: " + String.valueOf(throwable));
            return false;
        }
    }

    public static void dispatch(int n, int n2, int n3, int n4, int n5) {
        try {
            if (unavailable) {
                return;
            }
            ++dispatchHits;
            if (!firstHitLogged) {
                firstHitLogged = true;
                System.out.println("[MetallumAgent] SdlInputBridge HIT#1 type=" + n + " args=(" + n2 + "," + n3 + "," + n4 + "," + n5 + ") [v421] \u6865\u786e\u5b9e\u88ab\u8c03\u7528");
            }
            if (SEEN_TYPES.add(n)) {
                System.out.println("[MetallumAgent] SdlInputBridge first event type=" + n + " args=(" + n2 + "," + n3 + "," + n4 + "," + n5 + ")");
            }
            if (!SdlInputBridge.ensureInit()) {
                return;
            }
            if (SdlInputBridge.resolveWindowId() == 0) {
                if (++droppedNoWindowId <= 3L) {
                    System.out.println("[MetallumAgent] SdlInputBridge drop type=" + n + " (windowID=0, window=0x" + Long.toHexString(sdlWindow) + ")");
                }
                return;
            }
            switch (n) {
                case 1003: {
                    SdlInputBridge.warpMouse(n2, n3);
                    break;
                }
                case 1006: {
                    SdlInputBridge.pushMouseButton(n2, n3 == 1, lastX, lastY);
                    break;
                }
                case 1005: {
                    SdlInputBridge.pushKey(n3, n4 == 1);
                    break;
                }
                case 1000: {
                    SdlInputBridge.pushText((char)n2);
                    break;
                }
            }
            long l = System.currentTimeMillis();
            if (l - lastStatLog > 5000L) {
                lastStatLog = l;
                System.out.println("[MetallumAgent] SdlInputBridge stats hits=" + dispatchHits + " mouse=" + injectedMouse + " button=" + injectedButton + " key=" + injectedKey + " text=" + injectedText + " winID=" + sdlWindowId + " dropNoWin=" + droppedNoWindow + " dropNoWinId=" + droppedNoWindowId);
            }
        }
        catch (Throwable throwable) {
            // empty catch block
        }
    }

    private static void warpMouse(int n, int n2) throws Exception {
        Method method = cSdlVideo.getMethod("SDL_WarpMouseInWindow", Long.TYPE, Float.TYPE, Float.TYPE);
        float f = (float)((double)n / scale);
        float f2 = (float)((double)n2 / scale);
        method.invoke(null, sdlWindow, Float.valueOf(f), Float.valueOf(f2));
        float f3 = hasLast ? f - lastX : 0.0f;
        float f4 = hasLast ? f2 - lastY : 0.0f;
        hasLast = true;
        lastX = f;
        lastY = f2;
        SdlInputBridge.pushMouseMotion(f, f2, f3, f4);
        long l = System.currentTimeMillis();
        if (l - lastMoveLog > 2000L) {
            lastMoveLog = l;
            System.out.println("[MetallumAgent] input->SDL cursor (" + n + "," + n2 + ") -> (" + f + "," + f2 + ") rel=(" + f3 + "," + f4 + ") winID=" + sdlWindowId + " [v421]");
        }
    }

    private static void putEventHeader(int n) throws Exception {
        SdlInputBridge.putInt(0, n);
        SdlInputBridge.putInt(4, 0);
        SdlInputBridge.putLong(8, 0L);
        SdlInputBridge.putInt(16, SdlInputBridge.resolveWindowId());
        SdlInputBridge.putInt(20, 1);
    }

    private static void pushMouseMotion(float f, float f2, float f3, float f4) throws Exception {
        SdlInputBridge.putEventHeader(1024);
        SdlInputBridge.putInt(24, buttonStateMask);
        SdlInputBridge.putFloat(28, f);
        SdlInputBridge.putFloat(32, f2);
        SdlInputBridge.putFloat(36, f3);
        SdlInputBridge.putFloat(40, f4);
        SdlInputBridge.pushEvent();
        ++injectedMouse;
    }

    private static void pushMouseButton(int n, boolean bl, float f, float f2) throws Exception {
        SdlInputBridge.putEventHeader(bl ? 1025 : 1026);
        buttonStateMask = bl ? (buttonStateMask |= 1 << n) : (buttonStateMask &= ~(1 << n));
        SdlInputBridge.putByte(24, (byte)(n + 1));
        SdlInputBridge.putByte(25, (byte)(bl ? 1 : 0));
        SdlInputBridge.putByte(26, (byte)1);
        SdlInputBridge.putByte(27, (byte)0);
        SdlInputBridge.putFloat(28, f);
        SdlInputBridge.putFloat(32, f2);
        SdlInputBridge.pushEvent();
        ++injectedButton;
    }

    private static void pushKey(int n, boolean bl) throws Exception {
        int n2 = SdlInputBridge.keycodeToScancode(n);
        SdlInputBridge.putEventHeader(bl ? 768 : 769);
        SdlInputBridge.putInt(24, n2);
        SdlInputBridge.putInt(28, n);
        SdlInputBridge.putShort(32, (short)0);
        SdlInputBridge.putShort(34, (short)0);
        SdlInputBridge.putByte(36, (byte)(bl ? 1 : 0));
        SdlInputBridge.putByte(37, (byte)0);
        SdlInputBridge.pushEvent();
        ++injectedKey;
        if (bl && SEEN_KEYCODES.size() < 30 && SEEN_KEYCODES.add(n)) {
            System.out.println("[MetallumAgent] key inject keycode=" + n + " -> scancode=" + n2 + " (" + (n2 != 0 ? "mapped" : "UNMAPPED") + ") [v421]");
        }
    }

    private static void pushText(char c) throws Exception {
        SdlInputBridge.putEventHeader(771);
        SdlInputBridge.putByte(24, (byte)(c & 0xFF));
        SdlInputBridge.putByte(25, (byte)0);
        SdlInputBridge.pushEvent();
        ++injectedText;
    }

    private static int keycodeToScancode(int n) {
        if (n >= 97 && n <= 122) {
            return 4 + (n - 97);
        }
        if (n >= 65 && n <= 90) {
            return 4 + (n - 65);
        }
        if (n >= 49 && n <= 57) {
            return 30 + (n - 49);
        }
        if (n == 48) {
            return 39;
        }
        switch (n) {
            case 8: {
                return 42;
            }
            case 9: {
                return 43;
            }
            case 10: 
            case 13: {
                return 40;
            }
            case 27: {
                return 41;
            }
            case 32: {
                return 44;
            }
            case 42: {
                return 85;
            }
            case 43: {
                return 87;
            }
            case 44: {
                return 54;
            }
            case 45: {
                return 45;
            }
            case 46: {
                return 55;
            }
            case 47: {
                return 56;
            }
            case 58: {
                return 51;
            }
            case 59: {
                return 51;
            }
            case 60: {
                return 54;
            }
            case 61: {
                return 46;
            }
            case 62: {
                return 55;
            }
            case 63: {
                return 56;
            }
            case 91: {
                return 47;
            }
            case 92: {
                return 49;
            }
            case 93: {
                return 48;
            }
            case 96: {
                return 53;
            }
            case 16: {
                return 225;
            }
            case 17: {
                return 224;
            }
            case 18: {
                return 226;
            }
            case 19: {
                return 72;
            }
            case 20: {
                return 57;
            }
            case 33: {
                return 75;
            }
            case 34: {
                return 78;
            }
            case 35: {
                return 77;
            }
            case 36: {
                return 74;
            }
            case 37: {
                return 80;
            }
            case 38: {
                return 82;
            }
            case 39: {
                return 79;
            }
            case 40: {
                return 81;
            }
            case 127: {
                return 76;
            }
            case 144: {
                return 83;
            }
            case 145: {
                return 71;
            }
            case 154: {
                return 73;
            }
            case 155: {
                return 75;
            }
            case 156: {
                return 78;
            }
            case 224: 
            case 225: 
            case 226: 
            case 227: 
            case 228: 
            case 229: 
            case 230: 
            case 231: {
                return n;
            }
            case 240: {
                return 224;
            }
            case 241: {
                return 225;
            }
            case 242: {
                return 226;
            }
            case 243: {
                return 228;
            }
            case 1073741881: {
                return 57;
            }
            case 1073741882: {
                return 58;
            }
            case 1073741883: {
                return 59;
            }
            case 1073741884: {
                return 60;
            }
            case 1073741885: {
                return 61;
            }
            case 1073741886: {
                return 62;
            }
            case 1073741887: {
                return 63;
            }
            case 0x40000040: {
                return 64;
            }
            case 0x40000041: {
                return 65;
            }
            case 0x40000042: {
                return 66;
            }
            case 0x40000043: {
                return 67;
            }
            case 0x40000044: {
                return 68;
            }
            case 0x40000045: {
                return 69;
            }
            case 0x40000046: {
                return 70;
            }
            case 0x40000047: {
                return 71;
            }
            case 0x40000048: {
                return 72;
            }
            case 0x40000049: {
                return 73;
            }
            case 0x4000004A: {
                return 74;
            }
            case 0x4000004B: {
                return 75;
            }
            case 0x4000004C: {
                return 76;
            }
            case 0x4000004D: {
                return 77;
            }
            case 0x4000004E: {
                return 78;
            }
            case 0x4000004F: {
                return 79;
            }
            case 0x40000050: {
                return 80;
            }
            case 1073741905: {
                return 81;
            }
            case 1073741906: {
                return 82;
            }
            case 1073741907: {
                return 83;
            }
            case 0x40000054: {
                return 84;
            }
            case 0x40000055: {
                return 85;
            }
            case 1073741910: {
                return 86;
            }
            case 1073741911: {
                return 87;
            }
            case 1073741912: {
                return 88;
            }
            case 1073741913: {
                return 89;
            }
            case 1073741914: {
                return 90;
            }
            case 1073741915: {
                return 91;
            }
            case 1073741916: {
                return 92;
            }
            case 1073741917: {
                return 93;
            }
            case 1073741918: {
                return 94;
            }
            case 1073741919: {
                return 95;
            }
            case 0x40000060: {
                return 96;
            }
            case 1073741921: {
                return 97;
            }
            case 1073741922: {
                return 98;
            }
            case 1073741923: {
                return 99;
            }
            case 0x400000E0: {
                return 224;
            }
            case 1073742049: {
                return 225;
            }
            case 1073742050: {
                return 226;
            }
            case 1073742051: {
                return 227;
            }
            case 0x400000E4: {
                return 228;
            }
            case 1073742053: {
                return 229;
            }
            case 1073742054: {
                return 230;
            }
            case 1073742055: {
                return 231;
            }
            case 256: {
                return 41;
            }
            case 257: {
                return 40;
            }
            case 258: {
                return 43;
            }
            case 259: {
                return 42;
            }
            case 260: {
                return 73;
            }
            case 261: {
                return 76;
            }
            case 262: {
                return 79;
            }
            case 263: {
                return 80;
            }
            case 264: {
                return 81;
            }
            case 265: {
                return 82;
            }
            case 266: {
                return 75;
            }
            case 267: {
                return 78;
            }
            case 268: {
                return 74;
            }
            case 269: {
                return 77;
            }
            case 280: {
                return 57;
            }
            case 290: {
                return 58;
            }
            case 291: {
                return 59;
            }
            case 292: {
                return 60;
            }
            case 293: {
                return 61;
            }
            case 294: {
                return 62;
            }
            case 295: {
                return 63;
            }
            case 296: {
                return 64;
            }
            case 297: {
                return 65;
            }
            case 298: {
                return 66;
            }
            case 299: {
                return 67;
            }
            case 300: {
                return 68;
            }
            case 301: {
                return 69;
            }
            case 340: {
                return 225;
            }
            case 341: {
                return 224;
            }
            case 342: {
                return 226;
            }
            case 343: {
                return 227;
            }
            case 344: {
                return 229;
            }
            case 345: {
                return 228;
            }
            case 346: {
                return 230;
            }
            case 347: {
                return 231;
            }
        }
        return 0;
    }

    private static void putLong(int n, long l) throws Exception {
        Class<?> clazz = Class.forName("org.lwjgl.system.MemoryUtil", true, ClassLoader.getSystemClassLoader());
        Method method = clazz.getMethod("memPutLong", Long.TYPE, Long.TYPE);
        method.invoke(null, eventAddr + (long)n, l);
    }

    private static void putInt(int n, int n2) throws Exception {
        Class<?> clazz = Class.forName("org.lwjgl.system.MemoryUtil", true, ClassLoader.getSystemClassLoader());
        Method method = clazz.getMethod("memPutInt", Long.TYPE, Integer.TYPE);
        method.invoke(null, eventAddr + (long)n, n2);
    }

    private static void putShort(int n, short s) throws Exception {
        Class<?> clazz = Class.forName("org.lwjgl.system.MemoryUtil", true, ClassLoader.getSystemClassLoader());
        Method method = clazz.getMethod("memPutShort", Long.TYPE, Short.TYPE);
        method.invoke(null, eventAddr + (long)n, s);
    }

    private static void putByte(int n, byte by) throws Exception {
        Class<?> clazz = Class.forName("org.lwjgl.system.MemoryUtil", true, ClassLoader.getSystemClassLoader());
        Method method = clazz.getMethod("memPutByte", Long.TYPE, Byte.TYPE);
        method.invoke(null, eventAddr + (long)n, by);
    }

    private static void putFloat(int n, float f) throws Exception {
        Class<?> clazz = Class.forName("org.lwjgl.system.MemoryUtil", true, ClassLoader.getSystemClassLoader());
        Method method = clazz.getMethod("memPutFloat", Long.TYPE, Float.TYPE);
        method.invoke(null, eventAddr + (long)n, Float.valueOf(f));
    }

    private static void pushEvent() throws Exception {
        Method method = cSdl.getMethod("SDL_PushEvent", Long.TYPE);
        method.invoke(null, eventAddr);
    }

    static {
        eventAddr = 0L;
        eventSize = 0;
        lastX = 0.0f;
        lastY = 0.0f;
        hasLast = false;
        scale = 3.0;
        lastMoveLog = 0L;
        dispatchHits = 0;
        firstHitLogged = false;
        injectedMouse = 0L;
        injectedButton = 0L;
        injectedKey = 0L;
        injectedText = 0L;
        droppedNoWindow = 0L;
        droppedNoWindowId = 0L;
        lastStatLog = 0L;
        SEEN_TYPES = new HashSet<Integer>();
        SEEN_KEYCODES = new HashSet<Integer>();
        buttonStateMask = 0;
    }
}

