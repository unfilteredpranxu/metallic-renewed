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
public enum MTLCullMode {
    None(0L),
    Front(1L),
    Back(2L);

    public final long value;

    private MTLCullMode(long value) {
        this.value = value;
    }
}

