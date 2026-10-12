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
import com.metallum.client.metal.render.mtl.MTLBlitCommandEncoder;
import com.metallum.client.metal.render.mtl.MTLRenderCommandEncoder;
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class MTLCommandBuffer {
    private MemorySegment handle;

    MTLCommandBuffer(MemorySegment handle) {
        this.handle = handle;
    }

    public MTLBlitCommandEncoder makeBlitCommandEncoder() {
        MemorySegment encoder = MetalNativeBridge.MTLCommandBuffer_makeBlitCommandEncoder(this.handle());
        if (MetalNativeBridge.isNullHandle(encoder)) {
            throw new IllegalStateException("Failed to create MTLBlitCommandEncoder");
        }
        return new MTLBlitCommandEncoder(encoder);
    }

    public MTLRenderCommandEncoder makeRenderCommandEncoder(MemorySegment colorTexture, MemorySegment depthTexture, double viewportWidth, double viewportHeight, int clearColorEnabled, float clearColorRed, float clearColorGreen, float clearColorBlue, float clearColorAlpha, int clearDepthEnabled, double clearDepth) {
        MemorySegment encoder = MetalNativeBridge.MTLCommandBuffer_makeRenderCommandEncoder(this.handle(), colorTexture, depthTexture, viewportWidth, viewportHeight, clearColorEnabled, clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, clearDepthEnabled, clearDepth);
        if (MetalNativeBridge.isNullHandle(encoder)) {
            throw new IllegalStateException("Failed to create MTLRenderCommandEncoder");
        }
        return new MTLRenderCommandEncoder(encoder);
    }

    public void clearColorDepthTexturesRegion(MemorySegment colorTexture, float clearColorRed, float clearColorGreen, float clearColorBlue, float clearColorAlpha, MemorySegment depthTexture, double clearDepth, int regionX, int regionY, int regionWidth, int regionHeight, MemorySegment globalFence) {
        MetalNativeBridge.MTLCommandBuffer_clearColorDepthTexturesRegion(this.handle(), colorTexture, clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, depthTexture, clearDepth, regionX, regionY, regionWidth, regionHeight, globalFence);
    }

    public void encodePresentTextureToDrawable(MemorySegment layer, MemorySegment sourceTexture, MemorySegment globalFence) {
        MetalNativeBridge.MTLCommandBuffer_encodePresentTextureToDrawable(this.handle(), layer, sourceTexture, globalFence);
    }

    public void commit() {
        MetalNativeBridge.MTLCommandBuffer_commit(this.handle());
    }

    public void commitWithSignal(MemorySegment semaphore) {
        MetalNativeBridge.MTLCommandBuffer_commitWithSignal(this.handle(), semaphore);
    }

    public boolean isCompleted() {
        if (MetalNativeBridge.isNullHandle(this.handle)) {
            return true;
        }
        return MetalNativeBridge.MTLCommandBuffer_isCompleted(this.handle()) == 1;
    }

    public boolean waitUntilCompleted(long timeoutMs) {
        if (MetalNativeBridge.isNullHandle(this.handle)) {
            return true;
        }
        return MetalNativeBridge.MTLCommandBuffer_waitUntilCompleted(this.handle(), Math.max(timeoutMs, 0L)) == 0;
    }

    public void pushDebugGroup(String label) {
        MetalNativeBridge.MTLCommandBuffer_pushDebugGroup(this.handle(), label);
    }

    public void popDebugGroup() {
        MetalNativeBridge.MTLCommandBuffer_popDebugGroup(this.handle());
    }

    public void close() {
        if (MetalNativeBridge.isNullHandle(this.handle)) {
            return;
        }
        MetalNativeBridge.metallum_release_object(this.handle);
        this.handle = MemorySegment.NULL;
    }

    private MemorySegment handle() {
        if (MetalNativeBridge.isNullHandle(this.handle)) {
            throw new IllegalStateException("MTLCommandBuffer is closed");
        }
        return this.handle;
    }
}

