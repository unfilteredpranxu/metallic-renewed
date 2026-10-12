/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.GpuQueryPool
 */
package com.metallum.shims;

import java.util.OptionalLong;

public interface GpuQueryPool {
    public int size();

    public OptionalLong getValue(int var1);

    public OptionalLong[] getValues(int var1, int var2);

    public void close();
}

