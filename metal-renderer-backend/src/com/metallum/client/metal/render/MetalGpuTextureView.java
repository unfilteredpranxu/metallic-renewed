/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.textures.GpuTexture
 *  com.mojang.blaze3d.textures.GpuTextureView
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalGpuTexture;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.mojang.blaze3d.textures.GpuTexture;
import com.mojang.blaze3d.textures.GpuTextureView;
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
final class MetalGpuTextureView
extends GpuTextureView {
    private boolean closed;
    private @Nullable MemorySegment nativeHandle;

    MetalGpuTextureView(GpuTexture texture, int baseMipLevel, int mipLevels) {
        super(texture, baseMipLevel, mipLevels);
        ((MetalGpuTexture)texture).addView();
    }

    MemorySegment nativeHandle() {
        if (this.closed) {
            throw new IllegalStateException("Texture view is closed");
        }
        MetalGpuTexture texture = (MetalGpuTexture)this.texture();
        if (this.baseMipLevel() == 0 && this.mipLevels() >= texture.getMipLevels()) {
            return texture.nativeHandle();
        }
        if (this.nativeHandle == null) {
            MemorySegment viewHandle = MetalNativeBridge.metallum_create_texture_view(texture.nativeHandle(), this.baseMipLevel(), this.mipLevels());
            if (MetalNativeBridge.isNullHandle(viewHandle)) {
                throw new IllegalStateException("Failed to create Metal texture view for mip range " + this.baseMipLevel() + "+" + this.mipLevels());
            }
            this.nativeHandle = viewHandle;
        }
        return this.nativeHandle;
    }

    public void close() {
        if (this.closed) {
            return;
        }
        if (this.nativeHandle != null) {
            MemorySegment handle = this.nativeHandle;
            this.nativeHandle = null;
            ((MetalGpuTexture)this.texture()).queueNativeRelease(handle);
        }
        this.closed = true;
        ((MetalGpuTexture)this.texture()).removeView();
    }

    public boolean isClosed() {
        return this.closed;
    }
}

