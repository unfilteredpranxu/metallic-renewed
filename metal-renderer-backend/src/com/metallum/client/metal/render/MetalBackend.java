/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.GLFWErrorCapture$Error
 *  com.mojang.blaze3d.shaders.GpuDebugOptions
 *  com.mojang.blaze3d.shaders.ShaderSource
 *  com.mojang.blaze3d.systems.BackendCreationException
 *  com.mojang.blaze3d.systems.BackendCreationException$Reason
 *  com.mojang.blaze3d.systems.GpuBackend
 *  com.mojang.blaze3d.systems.GpuDevice
 *  com.mojang.blaze3d.systems.GpuDeviceBackend
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.NonNull
 *  org.lwjgl.glfw.GLFW
 *  org.lwjgl.glfw.GLFWNativeCocoa
 */
package com.metallum.client.metal.render;

import com.metallum.Metallum;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.mojang.blaze3d.GLFWErrorCapture;
import com.mojang.blaze3d.shaders.GpuDebugOptions;
import com.mojang.blaze3d.shaders.ShaderSource;
import com.mojang.blaze3d.systems.BackendCreationException;
import com.mojang.blaze3d.systems.GpuBackend;
import com.mojang.blaze3d.systems.GpuDevice;
import com.mojang.blaze3d.systems.GpuDeviceBackend;
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.NonNull;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.glfw.GLFWNativeCocoa;

@Environment(value=EnvType.CLIENT)
public class MetalBackend
implements GpuBackend {
    public @NonNull String getName() {
        return "Metal";
    }

    public void setWindowHints() {
        GLFW.glfwWindowHint((int)139265, (int)0);
    }

    public void handleWindowCreationErrors(GLFWErrorCapture.Error error) throws BackendCreationException {
        throw new BackendCreationException(error.toString(), BackendCreationException.Reason.GLFW_ERROR);
    }

    public @NonNull GpuDevice createDevice(long window, @NonNull ShaderSource defaultShaderSource, @NonNull GpuDebugOptions debugOptions, @NonNull Runnable criticalShaderLoader) throws BackendCreationException {
        MemorySegment metalLayer;
        double scale;
        MemorySegment cocoaView;
        MetalNativeBridge.ensureSpvcLibraryConfigured();
        MemorySegment deviceHandle = MetalNativeBridge.metallum_create_system_default_device();
        if (MetalNativeBridge.isNullHandle(deviceHandle)) {
            throw new BackendCreationException("MTLCreateSystemDefaultDevice returned null", BackendCreationException.Reason.OTHER);
        }
        String deviceName = MetalNativeBridge.metallum_copy_device_name(deviceHandle);
        if (deviceName.isBlank()) {
            deviceName = "<unknown Metal device>";
        }
        if (MetalNativeBridge.isIOS()) {
            MemorySegment cocoaWindow = MemorySegment.NULL;
            cocoaView = MetalBackend.readIOSSurfacePointer();
            scale = MetalBackend.readIOSScreenScale();
        } else {
            MemorySegment cocoaWindow = MemorySegment.ofAddress((long)GLFWNativeCocoa.glfwGetCocoaWindow((long)window));
            if (MetalNativeBridge.isNullHandle(cocoaWindow)) {
                throw new BackendCreationException("glfwGetCocoaWindow returned null", BackendCreationException.Reason.GLFW_ERROR);
            }
            cocoaView = MemorySegment.ofAddress((long)GLFWNativeCocoa.glfwGetCocoaView((long)window));
            if (MetalNativeBridge.isNullHandle(cocoaView)) {
                throw new BackendCreationException("glfwGetCocoaView returned null", BackendCreationException.Reason.GLFW_ERROR);
            }
            scale = MetalNativeBridge.metallum_NSWindow_backingScaleFactor(cocoaWindow);
        }
        if (scale <= 0.0) {
            scale = 1.0;
        }
        if (MetalNativeBridge.isIOS()) {
            metalLayer = MetalNativeBridge.metallum_ios_get_view_metal_layer(cocoaView, deviceHandle, scale);
            if (MetalNativeBridge.isNullHandle(metalLayer)) {
                throw new BackendCreationException("metallum_ios_get_view_metal_layer returned null", BackendCreationException.Reason.OTHER);
            }
        } else {
            metalLayer = MetalNativeBridge.metallum_create_metal_layer(deviceHandle, scale);
            if (MetalNativeBridge.isNullHandle(metalLayer)) {
                throw new BackendCreationException("Failed to create CAMetalLayer", BackendCreationException.Reason.OTHER);
            }
            MetalNativeBridge.metallum_NSView_setMetalLayer(cocoaView, metalLayer);
        }
        Metallum.LOGGER.info("Metal device: {}", (Object)deviceName);
        try {
            return new GpuDevice((GpuDeviceBackend)new MetalDevice(defaultShaderSource, debugOptions, deviceHandle, metalLayer, deviceName, cocoaView), criticalShaderLoader);
        }
        catch (Throwable throwable) {
            throw new BackendCreationException("Metal device initialization failed: " + throwable.getMessage(), BackendCreationException.Reason.OTHER);
        }
    }

    private static MemorySegment readIOSSurfacePointer() throws BackendCreationException {
        long address;
        String raw = System.getProperty("metallum.ios.view.pointer");
        if (raw == null || raw.isBlank()) {
            raw = System.getProperty("pojav.view.pointer");
        }
        if (raw == null || raw.isBlank()) {
            MemorySegment nativeView = MetalNativeBridge.metallum_ios_find_surface_view();
            if (!MetalNativeBridge.isNullHandle(nativeView)) {
                return nativeView;
            }
            throw new BackendCreationException("Could not locate the iOS surface view. Neither the 'metallum.ios.view.pointer'/'pojav.view.pointer' system property nor the +[SurfaceViewController surface] class method returned a UIView. If you are using a launcher other than Amethyst/PojavLauncher, set '-Dmetallum.ios.view.pointer=<hex>' to the UIView address.", BackendCreationException.Reason.OTHER);
        }
        String hex = (raw = raw.trim()).startsWith("0x") || raw.startsWith("0X") ? raw.substring(2) : raw;
        try {
            address = Long.parseUnsignedLong(hex, 16);
        }
        catch (NumberFormatException e) {
            throw new BackendCreationException("Invalid UIView pointer '" + raw + "': expected a hex address", BackendCreationException.Reason.OTHER);
        }
        MemorySegment view = MemorySegment.ofAddress((long)address);
        if (MetalNativeBridge.isNullHandle(view)) {
            throw new BackendCreationException("Host-provided UIView pointer is null", BackendCreationException.Reason.OTHER);
        }
        return view;
    }

    private static double readIOSScreenScale() {
        String raw = System.getProperty("metallum.ios.screen.scale");
        if (raw == null || raw.isBlank()) {
            return 2.0;
        }
        try {
            return Double.parseDouble(raw.trim());
        }
        catch (NumberFormatException e) {
            return 2.0;
        }
    }
}

