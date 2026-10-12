/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.platform.BlendFactor
 *  java.lang.MatchException
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.platform.BlendFactor;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLBlendFactor {
    Zero(0L),
    One(1L),
    SourceColor(2L),
    OneMinusSourceColor(3L),
    SourceAlpha(4L),
    OneMinusSourceAlpha(5L),
    DestinationColor(6L),
    OneMinusDestinationColor(7L),
    DestinationAlpha(8L),
    OneMinusDestinationAlpha(9L),
    SourceAlphaSaturated(10L),
    BlendColor(11L),
    OneMinusBlendColor(12L),
    BlendAlpha(13L),
    OneMinusBlendAlpha(14L),
    Source1Color(15L),
    OneMinusSource1Color(16L),
    Source1Alpha(17L),
    OneMinusSource1Alpha(18L),
    Unspecialized(19L);

    public final long value;

    private MTLBlendFactor(long value) {
        this.value = value;
    }

    public static MTLBlendFactor from(BlendFactor factor) {
        return switch (factor) {
            default -> throw new MatchException(null, null);
            case BlendFactor.ZERO -> Zero;
            case BlendFactor.ONE -> One;
            case BlendFactor.SRC_COLOR -> SourceColor;
            case BlendFactor.ONE_MINUS_SRC_COLOR -> OneMinusSourceColor;
            case BlendFactor.SRC_ALPHA -> SourceAlpha;
            case BlendFactor.ONE_MINUS_SRC_ALPHA -> OneMinusSourceAlpha;
            case BlendFactor.DST_COLOR -> DestinationColor;
            case BlendFactor.ONE_MINUS_DST_COLOR -> OneMinusDestinationColor;
            case BlendFactor.DST_ALPHA -> DestinationAlpha;
            case BlendFactor.ONE_MINUS_DST_ALPHA -> OneMinusDestinationAlpha;
            case BlendFactor.SRC_ALPHA_SATURATE -> SourceAlphaSaturated;
            case BlendFactor.CONSTANT_COLOR -> BlendColor;
            case BlendFactor.ONE_MINUS_CONSTANT_COLOR -> OneMinusBlendColor;
            case BlendFactor.CONSTANT_ALPHA -> BlendAlpha;
            case BlendFactor.ONE_MINUS_CONSTANT_ALPHA -> OneMinusBlendAlpha;
        };
    }
}

