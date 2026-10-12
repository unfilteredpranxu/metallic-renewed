/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.MetalTimerQuery
 *  com.mojang.renderpearl.api.commands.GpuQuery
 */
package com.metallum.client.metal.render;

import com.mojang.renderpearl.api.commands.GpuQuery;
import java.util.OptionalLong;

final class MetalTimerQuery
implements GpuQuery {
    private boolean ready = false;

    MetalTimerQuery() {
    }

    public OptionalLong getValue() {
        return this.ready ? OptionalLong.of(0L) : OptionalLong.empty();
    }

    public void close() {
        this.ready = true;
    }
}

