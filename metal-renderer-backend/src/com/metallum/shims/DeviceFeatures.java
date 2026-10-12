/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.DeviceFeatures
 */
package com.metallum.shims;

public record DeviceFeatures(boolean shaderClipDistance, boolean shaderCullDistance, boolean storageBuffers, boolean fillModeNonSolid, boolean seamlessCubemap, boolean timerQueries, boolean anisotropicFilter) {
    private final boolean shaderClipDistance;
    private final boolean shaderCullDistance;
    private final boolean storageBuffers;
    private final boolean fillModeNonSolid;
    private final boolean seamlessCubemap;
    private final boolean timerQueries;
    private final boolean anisotropicFilter;

    public DeviceFeatures(boolean bl, boolean bl2, boolean bl3, boolean bl4, boolean bl5, boolean bl6, boolean bl7) {
        this.shaderClipDistance = bl;
        this.shaderCullDistance = bl2;
        this.storageBuffers = bl3;
        this.fillModeNonSolid = bl4;
        this.seamlessCubemap = bl5;
        this.timerQueries = bl6;
        this.anisotropicFilter = bl7;
    }

    public boolean shaderClipDistance() {
        return this.shaderClipDistance;
    }

    public boolean shaderCullDistance() {
        return this.shaderCullDistance;
    }

    public boolean storageBuffers() {
        return this.storageBuffers;
    }

    public boolean fillModeNonSolid() {
        return this.fillModeNonSolid;
    }

    public boolean seamlessCubemap() {
        return this.seamlessCubemap;
    }

    public boolean timerQueries() {
        return this.timerQueries;
    }

    public boolean anisotropicFilter() {
        return this.anisotropicFilter;
    }
}

