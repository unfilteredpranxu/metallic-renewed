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
public enum MTLTextureUsage {
    Unknown(0L),
    ShaderRead(1L),
    ShaderWrite(2L),
    RenderTarget(4L),
    PixelFormatView(8L),
    ShaderAtomic(16L);

    public final long value;

    private MTLTextureUsage(long value) {
        this.value = value;
    }
}

