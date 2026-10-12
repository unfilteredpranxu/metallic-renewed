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
public enum MTLPixelFormat {
    R8Unorm(10L),
    R8Snorm(12L),
    R8Uint(13L),
    R8Sint(14L),
    R16Unorm(20L),
    R16Snorm(22L),
    R16Uint(23L),
    R16Sint(24L),
    R16Float(25L),
    RG8Unorm(30L),
    RG8Snorm(32L),
    RG8Uint(33L),
    RG8Sint(34L),
    R32Uint(53L),
    R32Sint(54L),
    R32Float(55L),
    RG16Unorm(60L),
    RG16Snorm(62L),
    RG16Uint(63L),
    RG16Sint(64L),
    RG16Float(65L),
    RGBA8Unorm(70L),
    BGRA8Unorm(80L),
    RGBA8Snorm(72L),
    RGBA8Uint(73L),
    RGBA8Sint(74L),
    RGB10A2Unorm(90L),
    RG11B10Float(92L),
    RG32Uint(103L),
    RG32Sint(104L),
    RG32Float(105L),
    RGBA16Unorm(110L),
    RGBA16Snorm(112L),
    RGBA16Uint(113L),
    RGBA16Sint(114L),
    RGBA16Float(115L),
    RGBA32Uint(123L),
    RGBA32Sint(124L),
    RGBA32Float(125L),
    Depth16Unorm(250L),
    Depth32Float(252L),
    Stencil8(253L),
    Depth24Unorm_Stencil8(255L),
    Depth32Float_Stencil8(260L),
    Invalid(0L);

    public final long value;

    private MTLPixelFormat(long value) {
        this.value = value;
    }

    public boolean hasStencil() {
        return this == Depth24Unorm_Stencil8 || this == Depth32Float_Stencil8;
    }

    public static MTLPixelFormat from(GpuFormat format) {
        return switch (format) {
            case GpuFormat.R8_UNORM -> R8Unorm;
            case GpuFormat.R8_SNORM -> R8Snorm;
            case GpuFormat.R8_UINT -> R8Uint;
            case GpuFormat.R8_SINT -> R8Sint;
            case GpuFormat.R16_UNORM -> R16Unorm;
            case GpuFormat.R16_SNORM -> R16Snorm;
            case GpuFormat.R16_UINT -> R16Uint;
            case GpuFormat.R16_SINT -> R16Sint;
            case GpuFormat.R16_FLOAT -> R16Float;
            case GpuFormat.RG8_UNORM -> RG8Unorm;
            case GpuFormat.RG8_SNORM -> RG8Snorm;
            case GpuFormat.RG8_UINT -> RG8Uint;
            case GpuFormat.RG8_SINT -> RG8Sint;
            case GpuFormat.R32_UINT -> R32Uint;
            case GpuFormat.R32_SINT -> R32Sint;
            case GpuFormat.R32_FLOAT -> R32Float;
            case GpuFormat.RG16_UNORM -> RG16Unorm;
            case GpuFormat.RG16_SNORM -> RG16Snorm;
            case GpuFormat.RG16_UINT -> RG16Uint;
            case GpuFormat.RG16_SINT -> RG16Sint;
            case GpuFormat.RG16_FLOAT -> RG16Float;
            case GpuFormat.RGBA8_UNORM -> RGBA8Unorm;
            case GpuFormat.RGBA8_SNORM -> RGBA8Snorm;
            case GpuFormat.RGBA8_UINT -> RGBA8Uint;
            case GpuFormat.RGBA8_SINT -> RGBA8Sint;
            case GpuFormat.RGB10A2_UNORM -> RGB10A2Unorm;
            case GpuFormat.RG11B10_FLOAT -> RG11B10Float;
            case GpuFormat.RG32_UINT -> RG32Uint;
            case GpuFormat.RG32_SINT -> RG32Sint;
            case GpuFormat.RG32_FLOAT -> RG32Float;
            case GpuFormat.RGBA16_UNORM -> RGBA16Unorm;
            case GpuFormat.RGBA16_SNORM -> RGBA16Snorm;
            case GpuFormat.RGBA16_UINT -> RGBA16Uint;
            case GpuFormat.RGBA16_SINT -> RGBA16Sint;
            case GpuFormat.RGBA16_FLOAT -> RGBA16Float;
            case GpuFormat.RGBA32_UINT -> RGBA32Uint;
            case GpuFormat.RGBA32_SINT -> RGBA32Sint;
            case GpuFormat.RGBA32_FLOAT -> RGBA32Float;
            case GpuFormat.D16_UNORM -> Depth16Unorm;
            case GpuFormat.D32_FLOAT -> Depth32Float;
            case GpuFormat.S8_UINT -> Stencil8;
            case GpuFormat.D24_UNORM_S8_UINT -> Depth24Unorm_Stencil8;
            case GpuFormat.D32_FLOAT_S8_UINT -> Depth32Float_Stencil8;
            default -> throw new IllegalStateException("Unsupported Metal texel buffer format: " + String.valueOf(format));
        };
    }
}

