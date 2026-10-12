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
public enum MTLRenderStages {
    Vertex(1L),
    Fragment(2L),
    VertexAndFragment(3L),
    Tile(4L),
    Object(8L),
    Mesh(16L);

    public final long value;

    private MTLRenderStages(long value) {
        this.value = value;
    }
}

