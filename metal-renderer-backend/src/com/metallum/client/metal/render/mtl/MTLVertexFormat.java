/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.GpuFormat
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.GpuFormat;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLVertexFormat {
    Invalid(0L),
    UChar2(1L),
    UChar3(2L),
    UChar4(3L),
    Char2(4L),
    Char3(5L),
    Char4(6L),
    UChar2Normalized(7L),
    UChar3Normalized(8L),
    UChar4Normalized(9L),
    Char2Normalized(10L),
    Char3Normalized(11L),
    Char4Normalized(12L),
    UShort2(13L),
    UShort3(14L),
    UShort4(15L),
    Short2(16L),
    Short3(17L),
    Short4(18L),
    UShort2Normalized(19L),
    UShort3Normalized(20L),
    UShort4Normalized(21L),
    Short2Normalized(22L),
    Short3Normalized(23L),
    Short4Normalized(24L),
    Half2(25L),
    Half3(26L),
    Half4(27L),
    Float(28L),
    Float2(29L),
    Float3(30L),
    Float4(31L),
    Int(32L),
    Int2(33L),
    Int3(34L),
    Int4(35L),
    UInt(36L),
    UInt2(37L),
    UInt3(38L),
    UInt4(39L),
    Int1010102Normalized(40L),
    UInt1010102Normalized(41L),
    UChar4Normalized_bgra(42L),
    UChar(45L),
    Char(46L),
    UCharNormalized(47L),
    CharNormalized(48L),
    UShort(49L),
    Short(50L),
    UShortNormalized(51L),
    ShortNormalized(52L),
    Half(53L),
    FloatRG11B10(54L),
    FloatRGB9E5(55L);

    public final long value;

    private MTLVertexFormat(long value) {
        this.value = value;
    }

    public static MTLVertexFormat from(GpuFormat format) {
        return switch (format) {
            case GpuFormat.R32_FLOAT -> Float;
            case GpuFormat.RG32_FLOAT -> Float2;
            case GpuFormat.RGB32_FLOAT -> Float3;
            case GpuFormat.RGBA32_FLOAT -> Float4;
            case GpuFormat.RGBA8_UNORM -> UChar4Normalized;
            case GpuFormat.RGBA8_UINT -> UChar4;
            case GpuFormat.RG16_UINT -> UShort2;
            case GpuFormat.RG16_UNORM -> UShort2Normalized;
            case GpuFormat.RG16_SINT -> Short2;
            case GpuFormat.RG16_SNORM -> Short2Normalized;
            case GpuFormat.RGBA16_UINT -> UShort4;
            case GpuFormat.RGBA16_SINT -> Short4;
            case GpuFormat.RGBA16_UNORM -> UShort4Normalized;
            case GpuFormat.RGBA16_SNORM -> Short4Normalized;
            case GpuFormat.R32_UINT -> UInt;
            case GpuFormat.RG32_UINT -> UInt2;
            case GpuFormat.RGB32_UINT -> UInt3;
            case GpuFormat.RGBA32_UINT -> UInt4;
            case GpuFormat.R32_SINT -> Int;
            case GpuFormat.RG32_SINT -> Int2;
            case GpuFormat.RGB32_SINT -> Int3;
            case GpuFormat.RGBA32_SINT -> Int4;
            case GpuFormat.R16_FLOAT -> Half;
            case GpuFormat.R16_UINT -> UShort;
            case GpuFormat.R16_SINT -> Short;
            case GpuFormat.R16_UNORM -> UShortNormalized;
            case GpuFormat.R16_SNORM -> ShortNormalized;
            case GpuFormat.R8_UINT -> UChar;
            case GpuFormat.R8_SINT -> Char;
            case GpuFormat.R8_UNORM -> UCharNormalized;
            case GpuFormat.R8_SNORM -> CharNormalized;
            case GpuFormat.RG16_FLOAT -> Half2;
            case GpuFormat.RGBA16_FLOAT -> Half4;
            case GpuFormat.RGBA8_SNORM -> Char4Normalized;
            case GpuFormat.RGBA8_SINT -> Char4;
            case GpuFormat.RGB8_UNORM -> UChar3Normalized;
            case GpuFormat.RGB8_SNORM -> Char3Normalized;
            case GpuFormat.RGB8_UINT -> UChar3;
            case GpuFormat.RGB8_SINT -> Char3;
            case GpuFormat.RGB16_UINT -> UShort3;
            case GpuFormat.RGB16_SINT -> Short3;
            case GpuFormat.RGB16_UNORM -> UShort3Normalized;
            case GpuFormat.RGB16_SNORM -> Short3Normalized;
            case GpuFormat.RGB16_FLOAT -> Half3;
            default -> Invalid;
        };
    }
}

