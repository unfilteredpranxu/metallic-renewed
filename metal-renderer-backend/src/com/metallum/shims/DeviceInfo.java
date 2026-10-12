/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.DeviceFeatures
 *  com.metallum.shims.DeviceInfo
 *  com.metallum.shims.DeviceLimits
 *  com.metallum.shims.DeviceType
 *  com.metallum.shims.HintsAndWorkarounds
 */
package com.metallum.shims;

import com.metallum.shims.DeviceFeatures;
import com.metallum.shims.DeviceLimits;
import com.metallum.shims.DeviceType;
import com.metallum.shims.HintsAndWorkarounds;
import java.util.Set;

public class DeviceInfo {
    public final String vendor;
    public final String renderer;
    public final String driverDescription;
    public final boolean dedicated;
    public final String graphicsApi;
    public final float apiVersion;
    public final DeviceLimits limits;
    public final DeviceFeatures features;
    public final Set<String> underlyingExtensions;
    public final HintsAndWorkarounds hints;
    public final DeviceType type;

    public DeviceInfo(String string, String string2, String string3, boolean bl, String string4, float f, DeviceLimits deviceLimits, DeviceFeatures deviceFeatures, Set<String> set, HintsAndWorkarounds hintsAndWorkarounds, DeviceType deviceType) {
        this.vendor = string;
        this.renderer = string2;
        this.driverDescription = string3;
        this.dedicated = bl;
        this.graphicsApi = string4;
        this.apiVersion = f;
        this.limits = deviceLimits;
        this.features = deviceFeatures;
        this.underlyingExtensions = set;
        this.hints = hintsAndWorkarounds;
        this.type = deviceType;
    }

    public DeviceLimits limits() {
        return this.limits;
    }

    public DeviceFeatures features() {
        return this.features;
    }

    public HintsAndWorkarounds hints() {
        return this.hints;
    }
}

