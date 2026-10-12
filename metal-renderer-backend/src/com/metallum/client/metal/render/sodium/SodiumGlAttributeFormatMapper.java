/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.SodiumGlAttributeFormatMapper
 *  com.mojang.blaze3d.vertex.VertexFormatElement$Type
 *  net.caffeinemc.mods.sodium.client.gl.attribute.GlVertexAttributeFormat
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.sodium;

import com.mojang.blaze3d.vertex.VertexFormatElement;
import net.caffeinemc.mods.sodium.client.gl.attribute.GlVertexAttributeFormat;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

/*
 * Exception performing whole class analysis ignored.
 */
@Environment(value=EnvType.CLIENT)
public final class SodiumGlAttributeFormatMapper {
    private SodiumGlAttributeFormatMapper() {
    }

    public static VertexFormatElement.Type toMinecraftType(GlVertexAttributeFormat format) {
        return SodiumGlAttributeFormatMapper.toMinecraftType((int)format.typeId());
    }

    public static VertexFormatElement.Type toMinecraftType(int typeId) {
        return switch (typeId) {
            case 5126 -> VertexFormatElement.Type.FLOAT;
            case 5124 -> VertexFormatElement.Type.INT;
            case 5122 -> VertexFormatElement.Type.SHORT;
            case 5120 -> VertexFormatElement.Type.BYTE;
            case 5123 -> VertexFormatElement.Type.USHORT;
            case 5121 -> VertexFormatElement.Type.UBYTE;
            case 5125 -> VertexFormatElement.Type.UINT;
            default -> throw new IllegalArgumentException("Unsupported Sodium attribute format typeId=" + typeId);
        };
    }
}

