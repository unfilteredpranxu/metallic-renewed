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
public enum MTLSamplerMipFilter {
    NotMipmapped(0L),
    Nearest(1L),
    Linear(2L);

    public final long value;

    private MTLSamplerMipFilter(long value) {
        this.value = value;
    }
}

