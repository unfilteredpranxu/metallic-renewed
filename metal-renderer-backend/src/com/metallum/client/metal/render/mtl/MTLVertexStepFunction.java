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
public enum MTLVertexStepFunction {
    Constant(0L),
    PerVertex(1L),
    PerInstance(2L),
    PerPatch(3L),
    PerPatchControlPoint(4L);

    public final long value;

    private MTLVertexStepFunction(long value) {
        this.value = value;
    }
}

