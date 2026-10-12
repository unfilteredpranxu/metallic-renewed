/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.SodiumUsageMapper
 *  com.metallum.client.metal.render.sodium.SodiumUsageMapper$1
 *  java.lang.MatchException
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferMapFlags
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferStorageFlags
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferUsage
 *  net.caffeinemc.mods.sodium.client.gl.util.EnumBitField
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.sodium.SodiumUsageMapper;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferMapFlags;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferStorageFlags;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferUsage;
import net.caffeinemc.mods.sodium.client.gl.util.EnumBitField;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class SodiumUsageMapper {
    private SodiumUsageMapper() {
    }

    public static int toMinecraftUsage(GlBufferUsage usage) {
        return switch (1.$SwitchMap$net$caffeinemc$mods$sodium$client$gl$buffer$GlBufferUsage[usage.ordinal()]) {
            default -> throw new MatchException(null, null);
            case 1 -> 42;
            case 2 -> 40;
            case 3 -> 20;
            case 4 -> 9;
            case 5, 6 -> 40;
            case 7 -> 9;
            case 8 -> 24;
            case 9 -> 9;
        };
    }

    public static int toMapUsage(EnumBitField<GlBufferMapFlags> flags) {
        int usage = 0;
        if (flags.contains((Enum)GlBufferMapFlags.READ)) {
            usage |= 1;
        }
        if (flags.contains((Enum)GlBufferMapFlags.WRITE)) {
            usage |= 2;
        }
        return usage;
    }

    public static int toStorageUsage(EnumBitField<GlBufferStorageFlags> flags) {
        int usage = 0;
        if (flags.contains((Enum)GlBufferStorageFlags.MAP_READ)) {
            usage |= 1;
        }
        if (flags.contains((Enum)GlBufferStorageFlags.MAP_WRITE)) {
            usage |= 2;
        }
        if (flags.contains((Enum)GlBufferStorageFlags.CLIENT_STORAGE)) {
            usage |= 4;
        }
        return usage;
    }
}

