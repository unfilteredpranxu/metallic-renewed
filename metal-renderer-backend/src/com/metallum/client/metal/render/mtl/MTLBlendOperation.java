/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.platform.BlendOp
 *  java.lang.MatchException
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.platform.BlendOp;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLBlendOperation {
    Add(0L),
    Subtract(1L),
    ReverseSubtract(2L),
    Min(3L),
    Max(4L);

    public final long value;

    private MTLBlendOperation(long value) {
        this.value = value;
    }

    public static MTLBlendOperation from(BlendOp op) {
        return switch (op) {
            default -> throw new MatchException(null, null);
            case BlendOp.ADD -> Add;
            case BlendOp.SUBTRACT -> Subtract;
            case BlendOp.REVERSE_SUBTRACT -> ReverseSubtract;
            case BlendOp.MIN -> Min;
            case BlendOp.MAX -> Max;
        };
    }
}

