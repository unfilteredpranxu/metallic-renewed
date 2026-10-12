/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.HintsAndWorkarounds
 */
package com.metallum.shims;

public record HintsAndWorkarounds(boolean needClientStorageWorkaround, boolean avoidSparseBuffers) {
    private final boolean needClientStorageWorkaround;
    private final boolean avoidSparseBuffers;

    public HintsAndWorkarounds(boolean bl, boolean bl2) {
        this.needClientStorageWorkaround = bl;
        this.avoidSparseBuffers = bl2;
    }

    public boolean needClientStorageWorkaround() {
        return this.needClientStorageWorkaround;
    }

    public boolean avoidSparseBuffers() {
        return this.avoidSparseBuffers;
    }
}

