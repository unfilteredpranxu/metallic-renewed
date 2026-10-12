/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.MetalGlBufferRegistry
 *  com.metallum.client.metal.render.sodium.MetalGlBufferRegistry$MetalGlBufferEntry
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.sodium.MetalGlBufferRegistry;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
public final class MetalGlBufferRegistry {
    private static long resizeCount;
    private static long resizeBytes;
    private static long resizeReportUs;
    private static long resizeLastUs;
    private static final AtomicInteger NEXT_HANDLE;
    private static final ConcurrentHashMap<Integer, MetalGlBufferEntry> BUFFERS;

    private MetalGlBufferRegistry() {
    }

    public static int nextHandle() {
        return NEXT_HANDLE.getAndIncrement();
    }

    public static void put(int handle, MetalGlBufferEntry entry) {
        BUFFERS.put(handle, entry);
    }

    public static // Could not load outer class - annotation placement on inner may be incorrect
    @Nullable MetalGlBufferRegistry.MetalGlBufferEntry get(int handle) {
        return (MetalGlBufferEntry)BUFFERS.get(handle);
    }

    public static // Could not load outer class - annotation placement on inner may be incorrect
    @Nullable MetalGlBufferRegistry.MetalGlBufferEntry remove(int handle) {
        return (MetalGlBufferEntry)BUFFERS.remove(handle);
    }

    static {
        NEXT_HANDLE = new AtomicInteger(1);
        BUFFERS = new ConcurrentHashMap();
    }
}

