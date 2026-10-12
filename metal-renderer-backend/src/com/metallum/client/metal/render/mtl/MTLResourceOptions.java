/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.metallum.client.metal.render.mtl.MTLHazardTrackingMode;
import com.metallum.client.metal.render.mtl.MTLStorageMode;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class MTLResourceOptions {
    private MTLResourceOptions() {
    }

    public static long of(MTLStorageMode storageMode, MTLHazardTrackingMode hazardTrackingMode) {
        return storageMode.value << 4 | hazardTrackingMode.value << 8;
    }
}

