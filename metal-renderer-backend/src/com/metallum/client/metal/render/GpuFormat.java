/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.GpuFormat
 */
package com.metallum.client.metal.render;

public final class GpuFormat {
    public final int value;

    public GpuFormat(int n) {
        this.value = n;
    }

    public int blockSize() {
        return 4;
    }
}

