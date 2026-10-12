/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.IndexType
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.IndexType;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLIndexType {
    UInt16(0L, 2),
    UInt32(1L, 4);

    public final long value;
    public final int bytes;

    private MTLIndexType(long value, int bytes) {
        this.value = value;
        this.bytes = bytes;
    }

    public static MTLIndexType from(IndexType indexType) {
        return indexType == IndexType.INT ? UInt32 : UInt16;
    }
}

