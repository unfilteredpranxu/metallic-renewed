/*
 * Decompiled with CFR 0.152.
 */
package dev.metalsodium;

import java.lang.reflect.Method;

public final class MetalSodium {
    private static final String DRAW_BACKEND = "net.caffeinemc.mods.sodium.client.gpu.device.backend.DrawBackend";
    private static final String METAL_DRAW_CONTEXT = "com.metallum.client.metal.render.MetalDrawContext";
    private static final String METAL_PACKAGE = "com.metallum.";
    private static volatile Boolean metal;
    private static boolean loggedBackend;
    private static boolean loggedContext;

    private MetalSodium() {
    }

    public static boolean isMetal() {
        Boolean bl = metal;
        if (bl != null) {
            return bl;
        }
        try {
            ClassLoader classLoader = MetalSodium.class.getClassLoader();
            Object object = Class.forName("com.mojang.blaze3d.systems.RenderSystem", false, classLoader).getMethod("getDevice", new Class[0]).invoke(null, new Object[0]);
            if (object == null) {
                return false;
            }
            Method method = object.getClass().getMethod("sodium$getBackend", new Class[0]);
            Object object2 = method.invoke(object, new Object[0]);
            boolean bl2 = object2 != null && object2.getClass().getName().startsWith(METAL_PACKAGE);
            metal = bl2;
            System.out.println("[MetalSodium] backend = " + (object2 == null ? "null" : object2.getClass().getName()) + " -> metal=" + bl2);
            return bl2;
        }
        catch (Throwable throwable) {
            System.out.println("[MetalSodium] could not detect backend: " + String.valueOf(throwable));
            return false;
        }
    }

    public static Object vkIndirect() {
        try {
            Class<?> clazz = Class.forName(DRAW_BACKEND, false, MetalSodium.class.getClassLoader());
            Object obj = Enum.valueOf(clazz, "VK_INDIRECT");
            if (!loggedBackend) {
                loggedBackend = true;
                System.out.println("[MetalSodium] Sodium DrawBackend -> VK_INDIRECT");
            }
            return obj;
        }
        catch (Throwable throwable) {
            throw new IllegalStateException("[MetalSodium] cannot resolve DrawBackend.VK_INDIRECT", throwable);
        }
    }

    public static Object newMetalDrawContext() {
        try {
            Class<?> clazz = Class.forName(METAL_DRAW_CONTEXT, true, MetalSodium.class.getClassLoader());
            Object obj = clazz.getDeclaredConstructor(new Class[0]).newInstance(new Object[0]);
            if (!loggedContext) {
                loggedContext = true;
                System.out.println("[MetalSodium] DrawContext -> " + clazz.getName());
            }
            return obj;
        }
        catch (Throwable throwable) {
            throw new IllegalStateException("[MetalSodium] cannot create MetalDrawContext", throwable);
        }
    }
}

