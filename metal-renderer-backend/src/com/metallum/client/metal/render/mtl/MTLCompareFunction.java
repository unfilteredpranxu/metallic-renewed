/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.platform.CompareOp
 *  java.lang.MatchException
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.platform.CompareOp;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLCompareFunction {
    Never(0L),
    Less(1L),
    Equal(2L),
    LessEqual(3L),
    Greater(4L),
    NotEqual(5L),
    GreaterEqual(6L),
    Always(7L);

    public final long value;

    private MTLCompareFunction(long value) {
        this.value = value;
    }

    public static MTLCompareFunction from(CompareOp op) {
        return switch (op) {
            default -> throw new MatchException(null, null);
            case CompareOp.NEVER_PASS -> Never;
            case CompareOp.LESS_THAN -> Less;
            case CompareOp.EQUAL -> Equal;
            case CompareOp.LESS_THAN_OR_EQUAL -> LessEqual;
            case CompareOp.GREATER_THAN -> Greater;
            case CompareOp.NOT_EQUAL -> NotEqual;
            case CompareOp.GREATER_THAN_OR_EQUAL -> GreaterEqual;
            case CompareOp.ALWAYS_PASS -> Always;
        };
    }
}

