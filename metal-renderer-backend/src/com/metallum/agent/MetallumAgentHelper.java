/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  net.minecraft.network.chat.Component
 */
package com.metallum.agent;

import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Arrays;
import net.minecraft.network.chat.Component;

public final class MetallumAgentHelper {
    private static final String CLS_GPU_BACKEND = "com.mojang.blaze3d.systems.GpuBackend";
    private static final String CLS_METAL = "com.metallum.client.metal.render.MetalBackend";
    private static final String CLS_VULKAN = "com.mojang.blaze3d.vulkan.VulkanBackend";
    private static final String CLS_GL = "com.mojang.blaze3d.opengl.GlBackend";

    public static Object[] getBackendsToTry(Object object) {
        try {
            ClassLoader[] classLoaderArray;
            System.out.println("[MetallumAgent] getBackendsToTry called, self=" + String.valueOf(object));
            ?[] objArray = object.getClass().getEnumConstants();
            if (objArray != null) {
                for (Object obj : objArray) {
                    System.out.println("[MetallumAgent]   enum const: " + ((Enum)obj).name());
                }
            }
            try {
                for (Field field : object.getClass().getDeclaredFields()) {
                    if (field.isEnumConstant()) continue;
                    field.setAccessible(true);
                    System.out.println("[MetallumAgent]   field " + field.getName() + " = " + String.valueOf(field.get(object)));
                }
            }
            catch (Throwable throwable) {
                // empty catch block
            }
            String string = (String)object.getClass().getMethod("name", new Class[0]).invoke(object, new Object[0]);
            System.out.println("[MetallumAgent]   self.name() = " + string);
            if (!"DEFAULT".equals(string) && !"OPENGL".equals(string)) {
                System.out.println("[MetallumAgent]   -> not DEFAULT/OPENGL, falling through");
                return null;
            }
            ClassLoader classLoader = object.getClass().getClassLoader();
            Class<?> clazz = MetallumAgentHelper.load(classLoader, CLS_GPU_BACKEND);
            if (clazz == null) {
                System.out.println("[MetallumAgent]   -> GpuBackend \u5728\u8c03\u7528\u8005\u52a0\u8f7d\u5668(" + String.valueOf(classLoader) + ")\u89e3\u6790\u4e0d\u5230, fallback(\u539f\u7248\u5217\u8868)");
                return null;
            }
            ClassLoader classLoader2 = MetallumAgentHelper.class.getClassLoader();
            for (ClassLoader classLoader3 : classLoaderArray = new ClassLoader[]{classLoader2, classLoader, Thread.currentThread().getContextClassLoader(), ClassLoader.getSystemClassLoader()}) {
                Object[] objectArray;
                Class<?> clazz2;
                if (classLoader3 == null || (clazz2 = MetallumAgentHelper.load(classLoader3, CLS_GPU_BACKEND)) == null || clazz2 != clazz || (objectArray = MetallumAgentHelper.build(clazz2, classLoader3)) == null) continue;
                System.out.println("[MetallumAgent]   -> returning " + Arrays.toString(objectArray) + " (loader=" + String.valueOf(classLoader3) + ")");
                return objectArray;
            }
            System.out.println("[MetallumAgent]   -> \u540e\u7aef\u7c7b\u5728\u5019\u9009\u52a0\u8f7d\u5668\u91cc\u90fd\u4e0d\u53ef\u7528, fallback(\u539f\u7248\u5217\u8868)");
            return null;
        }
        catch (Throwable throwable) {
            System.err.println("[MetallumAgent] backend list fallback: " + String.valueOf(throwable));
            throwable.printStackTrace(System.err);
            return null;
        }
    }

    private static Object[] build(Class<?> clazz, ClassLoader classLoader) {
        Object object;
        Object object2 = MetallumAgentHelper.instantiate(classLoader, CLS_METAL);
        if (object2 == null || !clazz.isInstance(object2)) {
            return null;
        }
        ArrayList<Object> arrayList = new ArrayList<Object>();
        arrayList.add(object2);
        Object object3 = MetallumAgentHelper.instantiate(classLoader, CLS_VULKAN);
        if (object3 != null && clazz.isInstance(object3)) {
            arrayList.add(object3);
        }
        if ((object = MetallumAgentHelper.instantiate(classLoader, CLS_GL)) != null && clazz.isInstance(object)) {
            arrayList.add(object);
        }
        Object object4 = Array.newInstance(clazz, arrayList.size());
        for (int i = 0; i < arrayList.size(); ++i) {
            Array.set(object4, i, arrayList.get(i));
        }
        return (Object[])object4;
    }

    private static Object instantiate(ClassLoader classLoader, String string) {
        try {
            Class<?> clazz = Class.forName(string, true, classLoader);
            return clazz.getDeclaredConstructor(new Class[0]).newInstance(new Object[0]);
        }
        catch (Throwable throwable) {
            System.out.println("[MetallumAgent]   (skip " + string + ": " + String.valueOf(throwable) + ")");
            return null;
        }
    }

    private static Class<?> load(ClassLoader classLoader, String string) {
        try {
            return Class.forName(string, false, classLoader);
        }
        catch (Throwable throwable) {
            return null;
        }
    }

    public static Component caption(Object object) {
        try {
            String string = (String)object.getClass().getMethod("name", new Class[0]).invoke(object, new Object[0]);
            if ("DEFAULT".equals(string) || "OPENGL".equals(string)) {
                return Component.literal((String)"Prefer Metal");
            }
        }
        finally {
            return null;
        }
        {
        }
    }
}

