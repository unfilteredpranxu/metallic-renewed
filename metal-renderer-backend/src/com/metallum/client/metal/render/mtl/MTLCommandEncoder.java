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
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public abstract class MTLCommandEncoder {
    MemorySegment handle;

    MTLCommandEncoder(MemorySegment handle) {
        this.handle = handle;
    }

    public MemorySegment handle() {
        if (MetalNativeBridge.isNullHandle(this.handle)) {
            throw new IllegalStateException(this.getClass().getSimpleName() + " is closed");
        }
        return this.handle;
    }

    public void endEncoding() {
        if (MetalNativeBridge.isNullHandle(this.handle)) {
            return;
        }
        MetalNativeBridge.MTLCommandEncoder_endEncoding(this.handle);
        MetalNativeBridge.metallum_release_object(this.handle);
        this.handle = MemorySegment.NULL;
    }
}

