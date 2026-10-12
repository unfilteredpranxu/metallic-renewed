/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.MetalSodiumFence
 *  net.caffeinemc.mods.sodium.client.gl.sync.GlFence
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.sodium;

import net.caffeinemc.mods.sodium.client.gl.sync.GlFence;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class MetalSodiumFence
extends GlFence {
    private boolean disposed;

    public MetalSodiumFence() {
        super(0L);
    }

    public boolean isCompleted() {
        this.checkDisposed();
        return true;
    }

    public void sync() {
        this.checkDisposed();
    }

    public void sync(long timeout) {
        this.checkDisposed();
    }

    public void delete() {
        this.disposed = true;
    }

    private void checkDisposed() {
        if (this.disposed) {
            throw new IllegalStateException("Fence object has been disposed");
        }
    }
}

