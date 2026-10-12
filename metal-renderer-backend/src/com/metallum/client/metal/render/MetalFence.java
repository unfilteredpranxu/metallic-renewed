/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.buffers.GpuFence
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalCommandEncoder;
import com.mojang.blaze3d.buffers.GpuFence;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
final class MetalFence
implements GpuFence {
    private final MetalCommandEncoder encoder;
    private final long submitIndex;
    private boolean closed;

    MetalFence(MetalCommandEncoder encoder, long submitIndex) {
        this.encoder = encoder;
        this.submitIndex = submitIndex;
    }

    public void close() {
        this.closed = true;
    }

    public boolean awaitCompletion(long timeoutNS) {
        return this.closed || this.encoder.awaitSubmitCompletion(this.submitIndex, timeoutNS / 1000000L);
    }
}

