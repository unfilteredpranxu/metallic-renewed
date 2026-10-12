/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.TransientMemory
 *  com.mojang.blaze3d.buffers.GpuBuffer$MappedView
 *  com.mojang.blaze3d.buffers.GpuBufferSlice
 */
package com.metallum.shims;

import com.mojang.blaze3d.buffers.GpuBuffer;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import java.nio.ByteBuffer;
import java.util.List;

public interface TransientMemory
extends AutoCloseable {
    public ByteBuffer allocateCpu(long var1, long var3, long var5, long var7);

    public GpuBuffer.MappedView allocateStaging(long var1, long var3, int var5, long var6, long var8);

    public GpuBufferSlice allocateGpu(long var1, long var3, int var5, long var6, long var8);

    public GpuBuffer.MappedView allocateGpuMapped(long var1, long var3, int var5, long var6, long var8);

    default public GpuBuffer.MappedView allocateGpuMapped(long l, long l2, int n) {
        return this.allocateGpuMapped(l, l2, n, 0L, 1L);
    }

    public GpuBufferSlice uploadStaging(List<ByteBuffer> var1, long var2, int var4, long var5, long var7);

    public GpuBufferSlice uploadGpu(List<ByteBuffer> var1, long var2, int var4, long var5, long var7);

    default public GpuBufferSlice uploadStaging(ByteBuffer byteBuffer, long l, int n) {
        return this.uploadStaging(List.of((Object)byteBuffer), l, n, 0L, 1L);
    }

    default public GpuBufferSlice uploadStaging(List<ByteBuffer> list, long l, int n) {
        return this.uploadStaging(list, l, n, 0L, 1L);
    }

    public List<GpuBufferSlice> multiUploadStaging(List<ByteBuffer> var1, long var2, int var4);

    public List<GpuBufferSlice> multiUploadGpu(List<ByteBuffer> var1, long var2, int var4);
}

