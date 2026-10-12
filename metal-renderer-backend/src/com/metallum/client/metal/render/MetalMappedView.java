/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.MetalMappedView
 *  com.mojang.renderpearl.api.buffers.GpuBufferSlice
 */
package com.metallum.client.metal.render;

import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import java.nio.ByteBuffer;

public final class MetalMappedView {
    private final ByteBuffer data;
    private final GpuBufferSlice slice;
    private final Runnable onClose;

    public MetalMappedView(ByteBuffer byteBuffer, GpuBufferSlice gpuBufferSlice, Runnable runnable) {
        this.data = byteBuffer;
        this.slice = gpuBufferSlice;
        this.onClose = runnable;
    }

    public ByteBuffer data() {
        return this.data;
    }

    public GpuBufferSlice slice() {
        return this.slice;
    }

    public void close() {
        if (this.onClose != null) {
            this.onClose.run();
        }
    }
}

