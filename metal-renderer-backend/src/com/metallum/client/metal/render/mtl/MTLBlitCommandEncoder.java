/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLCommandEncoder;
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class MTLBlitCommandEncoder
extends MTLCommandEncoder {
    MTLBlitCommandEncoder(MemorySegment handle) {
        super(handle);
    }

    public void copyFromBufferToBuffer(MemorySegment sourceBuffer, long sourceOffset, MemorySegment destinationBuffer, long destinationOffset, long length) {
        MetalNativeBridge.MTLBlitCommandEncoder_copyFromBufferToBuffer(this.handle(), sourceBuffer, sourceOffset, destinationBuffer, destinationOffset, length);
    }

    public void copyFromBufferToTexture(MemorySegment sourceBuffer, long sourceOffset, MemorySegment texture, long mipLevel, long slice, long x, long y, long width, long height, long bytesPerRow, long bytesPerImage) {
        MetalNativeBridge.MTLBlitCommandEncoder_copyFromBufferToTexture(this.handle(), sourceBuffer, sourceOffset, texture, mipLevel, slice, x, y, width, height, bytesPerRow, bytesPerImage);
    }

    public void copyFromTextureToTexture(MemorySegment sourceTexture, MemorySegment destinationTexture, long mipLevel, long sourceX, long sourceY, long destX, long destY, long width, long height) {
        MetalNativeBridge.MTLBlitCommandEncoder_copyFromTextureToTexture(this.handle(), sourceTexture, destinationTexture, mipLevel, sourceX, sourceY, destX, destY, width, height);
    }

    public void copyFromTextureToBuffer(MemorySegment sourceTexture, MemorySegment destinationBuffer, long destinationOffset, long mipLevel, long slice, long x, long y, long width, long height, long bytesPerRow, long bytesPerImage) {
        MetalNativeBridge.MTLBlitCommandEncoder_copyFromTextureToBuffer(this.handle(), sourceTexture, destinationBuffer, destinationOffset, mipLevel, slice, x, y, width, height, bytesPerRow, bytesPerImage);
    }

    public void updateFence(MemorySegment fence) {
        MetalNativeBridge.MTLBlitCommandEncoder_updateFence(this.handle(), fence);
    }

    public void waitForFence(MemorySegment fence) {
        MetalNativeBridge.MTLBlitCommandEncoder_waitForFence(this.handle(), fence);
    }
}

