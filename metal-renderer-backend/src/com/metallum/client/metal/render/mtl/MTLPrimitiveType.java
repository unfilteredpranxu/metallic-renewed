/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.PrimitiveTopology
 *  java.lang.MatchException
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.PrimitiveTopology;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLPrimitiveType {
    Point(0L),
    Line(1L),
    LineStrip(2L),
    Triangle(3L),
    TriangleStrip(4L),
    TriangleFan(5L);

    public final long value;

    private MTLPrimitiveType(long value) {
        this.value = value;
    }

    public static MTLPrimitiveType from(PrimitiveTopology mode) {
        return switch (mode) {
            default -> throw new MatchException(null, null);
            case PrimitiveTopology.TRIANGLES, PrimitiveTopology.QUADS, PrimitiveTopology.LINES -> Triangle;
            case PrimitiveTopology.TRIANGLE_STRIP -> TriangleStrip;
            case PrimitiveTopology.DEBUG_LINES -> Line;
            case PrimitiveTopology.DEBUG_LINE_STRIP -> LineStrip;
            case PrimitiveTopology.POINTS -> Point;
            case PrimitiveTopology.TRIANGLE_FAN -> TriangleFan;
        };
    }
}

