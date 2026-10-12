/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.GpuFormat
 *  com.mojang.blaze3d.textures.GpuTexture
 *  com.mojang.blaze3d.textures.GpuTexture$Usage
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.joml.Vector4fc
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLPixelFormat;
import com.metallum.client.metal.render.mtl.MTLStorageMode;
import com.metallum.client.metal.render.mtl.MTLTextureUsage;
import com.mojang.blaze3d.GpuFormat;
import com.mojang.blaze3d.textures.GpuTexture;
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.joml.Vector4fc;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
final class MetalGpuTexture
extends GpuTexture {
    private final MetalDevice device;
    private final MTLPixelFormat mtlPixelFormat;
    private boolean closed;
    private @Nullable Vector4fc materializedColorClear;
    private @Nullable Double materializedDepthClear;
    private int views = 1;
    private @Nullable MemorySegment nativeHandle;

    MetalGpuTexture(MetalDevice device, @GpuTexture.Usage int usage, String label, GpuFormat format, int width, int height, int depthOrLayers, int mipLevels) {
        super(usage, label, format, width, height, depthOrLayers, mipLevels);
        this.device = device;
        this.mtlPixelFormat = MTLPixelFormat.from(format);
        this.nativeHandle = MetalNativeBridge.metallum_create_texture_2d(device.metalDeviceHandle(), this.mtlPixelFormat, width, height, depthOrLayers, mipLevels, (usage & 0x10) != 0 ? 1L : 0L, MetalGpuTexture.toMtlTextureUsage(usage), MTLStorageMode.Private, label);
    }

    int pixelSize() {
        return this.getFormat().blockSize();
    }

    void recordMaterializedClear(@Nullable Vector4fc color, @Nullable Double depth) {
        if (color != null) {
            this.materializedColorClear = color;
        }
        if (depth != null) {
            this.materializedDepthClear = depth;
        }
    }

    boolean clearIsRedundant(@Nullable Vector4fc color, @Nullable Double depth) {
        return !(color != null && !color.equals((Object)this.materializedColorClear) || depth != null && !depth.equals(this.materializedDepthClear));
    }

    void markContentsDirty() {
        this.materializedColorClear = null;
        this.materializedDepthClear = null;
    }

    MemorySegment nativeHandle() {
        if (this.nativeHandle == null) {
            throw new IllegalStateException("Native Metal texture is closed");
        }
        return this.nativeHandle;
    }

    void queueNativeRelease(MemorySegment handle) {
        this.device.queueResourceRelease(handle);
    }

    void addView() {
        ++this.views;
    }

    void removeView() {
        --this.views;
        if (this.views < 0) {
            throw new IllegalStateException("Too many views removed from texture");
        }
        if (this.closed && this.views == 0 && this.nativeHandle != null) {
            MemorySegment handle = this.nativeHandle;
            this.nativeHandle = null;
            this.device.queueResourceRelease(handle);
        }
    }

    MTLPixelFormat mtlPixelFormat() {
        return this.mtlPixelFormat;
    }

    MTLPixelFormat mtlStencilPixelFormat() {
        return this.mtlPixelFormat.hasStencil() ? this.mtlPixelFormat : MTLPixelFormat.Invalid;
    }

    public void close() {
        if (this.closed) {
            return;
        }
        this.closed = true;
        this.removeView();
    }

    public boolean isClosed() {
        return this.closed;
    }

    private static long toMtlTextureUsage(@GpuTexture.Usage int usage) {
        long result = 0L;
        if ((usage & 4) != 0 || (usage & 1) != 0 || (usage & 2) != 0) {
            result |= MTLTextureUsage.ShaderRead.value;
        }
        if ((usage & 8) != 0) {
            result |= MTLTextureUsage.RenderTarget.value;
            result |= MTLTextureUsage.ShaderRead.value;
        }
        return result == 0L ? MTLTextureUsage.ShaderRead.value : result;
    }
}

