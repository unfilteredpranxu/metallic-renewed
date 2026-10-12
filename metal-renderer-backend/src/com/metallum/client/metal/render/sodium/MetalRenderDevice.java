/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.DiagLog
 *  com.metallum.client.metal.render.sodium.MetalRenderDevice
 *  com.metallum.client.metal.render.sodium.MetalRenderDevice$1
 *  com.metallum.client.metal.render.sodium.MetalSodiumCommandList
 *  net.caffeinemc.mods.sodium.client.gl.device.CommandList
 *  net.caffeinemc.mods.sodium.client.gl.device.RenderDevice
 *  net.caffeinemc.mods.sodium.client.gl.functions.DeviceFunctions
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.lwjgl.PointerBuffer
 *  org.lwjgl.opengl.GLCapabilities
 *  org.lwjgl.system.FunctionProvider
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.DiagLog;
import com.metallum.client.metal.render.sodium.MetalRenderDevice;
import com.metallum.client.metal.render.sodium.MetalSodiumCommandList;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.util.Set;
import java.util.function.IntFunction;
import net.caffeinemc.mods.sodium.client.gl.device.CommandList;
import net.caffeinemc.mods.sodium.client.gl.device.RenderDevice;
import net.caffeinemc.mods.sodium.client.gl.functions.DeviceFunctions;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.lwjgl.PointerBuffer;
import org.lwjgl.opengl.GLCapabilities;
import org.lwjgl.system.FunctionProvider;
import sun.misc.Unsafe;

/*
 * Exception performing whole class analysis ignored.
 */
@Environment(value=EnvType.CLIENT)
public final class MetalRenderDevice
implements RenderDevice {
    private static final GLCapabilities FAKE_CAPABILITIES = MetalRenderDevice.createFakeCapabilities();
    public static final RenderDevice INSTANCE = new MetalRenderDevice();
    private final CommandList commandList = new MetalSodiumCommandList();
    private final DeviceFunctions functions = new DeviceFunctions((RenderDevice)this);
    private boolean isActive;

    public static GLCapabilities getFakeCapabilities() {
        return FAKE_CAPABILITIES;
    }

    public CommandList createCommandList() {
        this.checkDeviceActive();
        return this.commandList;
    }

    public void makeActive() {
        this.isActive = true;
    }

    public void makeInactive() {
        this.isActive = false;
    }

    private static GLCapabilities createFakeCapabilities() {
        1 provider = new /* Unavailable Anonymous Inner Class!! */;
        try {
            Constructor ctor = GLCapabilities.class.getDeclaredConstructor(FunctionProvider.class, Set.class, Boolean.TYPE, IntFunction.class);
            ctor.setAccessible(true);
            return (GLCapabilities)ctor.newInstance(provider, Set.of(), false, i -> PointerBuffer.allocateDirect((int)2228));
        }
        catch (ReflectiveOperationException e) {
            DiagLog.log((String)"createFakeCapabilities reflection failed (%s) - Unsafe fallback", (Object[])new Object[]{e.toString()});
            return MetalRenderDevice.allocateUninitializedCapabilities();
        }
    }

    private static GLCapabilities allocateUninitializedCapabilities() {
        try {
            Field theUnsafe = Unsafe.class.getDeclaredField("theUnsafe");
            theUnsafe.setAccessible(true);
            Unsafe unsafe = (Unsafe)theUnsafe.get(null);
            return (GLCapabilities)unsafe.allocateInstance(GLCapabilities.class);
        }
        catch (ReflectiveOperationException ex) {
            throw new RuntimeException("Failed to allocate uninitialized GLCapabilities", ex);
        }
    }

    public GLCapabilities getCapabilities() {
        return FAKE_CAPABILITIES;
    }

    public DeviceFunctions getDeviceFunctions() {
        return this.functions;
    }

    public int getSubTexelPrecisionBits() {
        return 4;
    }

    private void checkDeviceActive() {
        if (!this.isActive) {
            throw new IllegalStateException("Tried to access device from unmanaged context");
        }
    }
}

