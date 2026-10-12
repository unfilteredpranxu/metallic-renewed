/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.systems.GpuQueryPool
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.NonNull
 */
package com.metallum.client.metal.render;

import com.mojang.blaze3d.systems.GpuQueryPool;
import java.util.OptionalLong;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.NonNull;

@Environment(value=EnvType.CLIENT)
final class MetalGpuQueryPool
implements GpuQueryPool {
    private final OptionalLong[] values;

    MetalGpuQueryPool(int size) {
        this.values = new OptionalLong[size];
        for (int i = 0; i < size; ++i) {
            this.values[i] = OptionalLong.empty();
        }
    }

    void setValue(int index, long value) {
        this.values[index] = OptionalLong.of(value);
    }

    public int size() {
        return this.values.length;
    }

    public @NonNull OptionalLong getValue(int index) {
        return this.values[index];
    }

    public OptionalLong @NonNull [] getValues(int index, int count) {
        OptionalLong[] result = new OptionalLong[count];
        System.arraycopy(this.values, index, result, 0, count);
        return result;
    }

    public void close() {
        for (int i = 0; i < this.values.length; ++i) {
            this.values[i] = OptionalLong.empty();
        }
    }
}

