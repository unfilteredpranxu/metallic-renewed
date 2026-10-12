/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.GcMonitor
 */
package com.metallum.client.metal.render;

import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.List;

public final class GcMonitor {
    private static final List<GarbageCollectorMXBean> BEANS;
    private static long lastCount;
    private static long lastTimeMs;

    private GcMonitor() {
    }

    public static long pauseDeltaMs() {
        long count = 0L;
        long timeMs = 0L;
        for (GarbageCollectorMXBean bean : BEANS) {
            try {
                count += bean.getCollectionCount();
                timeMs += bean.getCollectionTime();
            }
            catch (Throwable throwable) {}
        }
        long deltaCount = count - lastCount;
        long deltaMs = timeMs - lastTimeMs;
        lastCount = count;
        lastTimeMs = timeMs;
        return deltaCount > 0L ? deltaMs : 0L;
    }

    static {
        List beans;
        try {
            beans = ManagementFactory.getGarbageCollectorMXBeans();
        }
        catch (Throwable t) {
            beans = List.of();
        }
        BEANS = beans;
        for (GarbageCollectorMXBean bean : BEANS) {
            try {
                lastCount += bean.getCollectionCount();
                lastTimeMs += bean.getCollectionTime();
            }
            catch (Throwable throwable) {}
        }
    }
}

