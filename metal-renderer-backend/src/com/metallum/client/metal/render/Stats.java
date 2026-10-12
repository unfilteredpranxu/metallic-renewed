/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.client.metal.render;

import com.metallum.Metallum;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

public class Stats {
    private static final AtomicLong CREATED_BUFFERS = new AtomicLong();
    private static final ConcurrentHashMap<Integer, UsageStats> USAGE_STATS = new ConcurrentHashMap();
    private static final boolean RENDER_STATS = Boolean.getBoolean("metallum.renderStats");
    private static final AtomicLong INDEXED_DRAWS = new AtomicLong();
    private static final AtomicLong BATCHED_MULTI_DRAWS = new AtomicLong();
    private static final AtomicLong TEXEL_VIEW_ALLOCATIONS = new AtomicLong();
    private static final AtomicLong FRAME = new AtomicLong();

    public static void recordUsage(int usage, long requestedSize, long allocatedSize) {
        UsageStats stats = USAGE_STATS.computeIfAbsent(usage, k -> new UsageStats());
        stats.count.incrementAndGet();
        stats.requestedBytes.addAndGet(requestedSize);
        stats.allocatedBytes.addAndGet(allocatedSize);
        CREATED_BUFFERS.incrementAndGet();
    }

    public static void recordIndexedDraw() {
        if (RENDER_STATS) {
            INDEXED_DRAWS.incrementAndGet();
        }
    }

    public static void recordBatchedMultiDraw() {
        if (RENDER_STATS) {
            BATCHED_MULTI_DRAWS.incrementAndGet();
        }
    }

    public static void recordTexelViewAllocation() {
        if (RENDER_STATS) {
            TEXEL_VIEW_ALLOCATIONS.incrementAndGet();
        }
    }

    public static void tickRenderStats() {
        if (!RENDER_STATS) {
            return;
        }
        long frame = FRAME.incrementAndGet();
        if (frame % 120L == 0L) {
            Metallum.LOGGER.info("[metallum:renderStats] frame={} indexedDraws={} batchedMultiDraws={} texelViewAlloc={}", new Object[]{frame, INDEXED_DRAWS.get(), BATCHED_MULTI_DRAWS.get(), TEXEL_VIEW_ALLOCATIONS.get()});
        }
    }

    private static final class UsageStats {
        final AtomicLong count = new AtomicLong();
        final AtomicLong requestedBytes = new AtomicLong();
        final AtomicLong allocatedBytes = new AtomicLong();

        private UsageStats() {
        }
    }
}

