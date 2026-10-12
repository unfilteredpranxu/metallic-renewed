/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render.mtl;

import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLCommandBuffer;
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
public final class MTLCommandQueue {
    private MemorySegment handle;

    private MTLCommandQueue(MemorySegment handle) {
        this.handle = handle;
    }

    public static MTLCommandQueue create(MemorySegment device) {
        MemorySegment handle = MetalNativeBridge.MTLDevice_makeCommandQueue(device);
        if (MetalNativeBridge.isNullHandle(handle)) {
            throw new IllegalStateException("Failed to create Metal command queue");
        }
        return new MTLCommandQueue(handle);
    }

    public MTLCommandBuffer makeCommandBuffer(@Nullable String label) {
        MemorySegment commandBuffer = MetalNativeBridge.MTLCommandQueue_makeCommandBuffer(this.handle, label);
        if (MetalNativeBridge.isNullHandle(commandBuffer)) {
            throw new IllegalStateException("Failed to create MTLCommandBuffer");
        }
        return new MTLCommandBuffer(commandBuffer);
    }

    public void close() {
        if (MetalNativeBridge.isNullHandle(this.handle)) {
            return;
        }
        MetalNativeBridge.metallum_release_object(this.handle);
        this.handle = MemorySegment.NULL;
    }
}

