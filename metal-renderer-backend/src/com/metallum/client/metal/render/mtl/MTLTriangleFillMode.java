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
public enum MTLTriangleFillMode {
    Fill(0),
    Lines(1);

    public final int value;

    private MTLTriangleFillMode(int value) {
        this.value = value;
    }
}

