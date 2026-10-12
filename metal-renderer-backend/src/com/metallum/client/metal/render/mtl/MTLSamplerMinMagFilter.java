/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.textures.FilterMode
 *  java.lang.MatchException
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.mojang.blaze3d.textures.FilterMode;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public enum MTLSamplerMinMagFilter {
    Nearest(0L),
    Linear(1L);

    public final long value;

    private MTLSamplerMinMagFilter(long value) {
        this.value = value;
    }

    public static MTLSamplerMinMagFilter from(FilterMode filterMode) {
        return switch (filterMode) {
            default -> throw new MatchException(null, null);
            case FilterMode.NEAREST -> Nearest;
            case FilterMode.LINEAR -> Linear;
        };
    }
}

