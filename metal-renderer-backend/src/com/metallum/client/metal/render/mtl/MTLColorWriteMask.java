/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.pipeline.ColorTargetState$WriteMask
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.pipeline.ColorTargetState;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLColorWriteMask {
    None(0L),
    Alpha(1L),
    Blue(2L),
    Green(4L),
    Red(8L),
    All(15L);

    public final long value;

    private MTLColorWriteMask(long value) {
        this.value = value;
    }

    public static long from(@ColorTargetState.WriteMask int blazeMask) {
        long mask = 0L;
        if ((blazeMask & 1) != 0) {
            mask |= MTLColorWriteMask.Red.value;
        }
        if ((blazeMask & 2) != 0) {
            mask |= MTLColorWriteMask.Green.value;
        }
        if ((blazeMask & 4) != 0) {
            mask |= MTLColorWriteMask.Blue.value;
        }
        if ((blazeMask & 8) != 0) {
            mask |= MTLColorWriteMask.Alpha.value;
        }
        return mask;
    }
}

