/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.textures.AddressMode
 *  com.mojang.blaze3d.textures.FilterMode
 *  com.mojang.blaze3d.textures.GpuSampler
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.NonNull
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLSamplerAddressMode;
import com.metallum.client.metal.render.mtl.MTLSamplerMinMagFilter;
import com.metallum.client.metal.render.mtl.MTLSamplerMipFilter;
import com.mojang.blaze3d.textures.AddressMode;
import com.mojang.blaze3d.textures.FilterMode;
import com.mojang.blaze3d.textures.GpuSampler;
import java.lang.foreign.MemorySegment;
import java.util.OptionalDouble;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.NonNull;

@Environment(value=EnvType.CLIENT)
final class MetalGpuSampler
extends GpuSampler {
    private final MetalDevice device;
    private final MemorySegment nativeHandle;
    private final AddressMode addressModeU;
    private final AddressMode addressModeV;
    private final FilterMode minFilter;
    private final FilterMode magFilter;
    private final int maxAnisotropy;
    private final OptionalDouble maxLod;
    private boolean closed;

    MetalGpuSampler(MetalDevice device, AddressMode addressModeU, AddressMode addressModeV, FilterMode minFilter, FilterMode magFilter, int maxAnisotropy, OptionalDouble maxLod) {
        this.device = device;
        this.nativeHandle = MetalNativeBridge.metallum_create_sampler(device.metalDeviceHandle(), MTLSamplerAddressMode.from(addressModeU), MTLSamplerAddressMode.from(addressModeV), MTLSamplerMinMagFilter.from(minFilter), MTLSamplerMinMagFilter.from(magFilter), MetalGpuSampler.toMtlMipFilter(maxLod), Math.max(1, maxAnisotropy), MetalGpuSampler.toMtlMaxLodClamp(maxLod));
        this.addressModeU = addressModeU;
        this.addressModeV = addressModeV;
        this.minFilter = minFilter;
        this.magFilter = magFilter;
        this.maxAnisotropy = maxAnisotropy;
        this.maxLod = maxLod;
    }

    public @NonNull AddressMode getAddressModeU() {
        return this.addressModeU;
    }

    public @NonNull AddressMode getAddressModeV() {
        return this.addressModeV;
    }

    public @NonNull FilterMode getMinFilter() {
        return this.minFilter;
    }

    public @NonNull FilterMode getMagFilter() {
        return this.magFilter;
    }

    public int getMaxAnisotropy() {
        return this.maxAnisotropy;
    }

    public @NonNull OptionalDouble getMaxLod() {
        return this.maxLod;
    }

    public void close() {
        if (this.closed) {
            return;
        }
        this.closed = true;
        this.device.queueResourceRelease(this.nativeHandle);
    }

    boolean isClosed() {
        return this.closed;
    }

    MemorySegment nativeHandle() {
        return this.nativeHandle;
    }

    private static MTLSamplerMipFilter toMtlMipFilter(OptionalDouble maxLod) {
        return maxLod.orElse(1000.0) > 0.25 ? MTLSamplerMipFilter.Linear : MTLSamplerMipFilter.Nearest;
    }

    private static double toMtlMaxLodClamp(OptionalDouble maxLod) {
        return Math.max(0.25, maxLod.orElse(1000.0));
    }
}

