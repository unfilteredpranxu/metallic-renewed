/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLStorageMode {
    Shared(0L),
    Managed(1L),
    Private(2L),
    Memoryless(3L);

    public final long value;

    private MTLStorageMode(long value) {
        this.value = value;
    }
}

