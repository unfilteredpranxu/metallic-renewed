/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.textures.AddressMode
 *  java.lang.MatchException
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.textures.AddressMode;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLSamplerAddressMode {
    ClampToEdge(0L),
    MirrorClampToEdge(1L),
    Repeat(2L),
    MirrorRepeat(3L),
    ClampToZero(4L),
    ClampToBorderColor(5L);

    public final long value;

    private MTLSamplerAddressMode(long value) {
        this.value = value;
    }

    public static MTLSamplerAddressMode from(AddressMode addressMode) {
        return switch (addressMode) {
            default -> throw new MatchException(null, null);
            case AddressMode.REPEAT -> Repeat;
            case AddressMode.CLAMP_TO_EDGE -> ClampToEdge;
        };
    }
}

