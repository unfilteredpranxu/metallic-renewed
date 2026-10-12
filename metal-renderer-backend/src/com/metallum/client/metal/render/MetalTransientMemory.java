/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.buffers.GpuBuffer
 *  com.mojang.blaze3d.buffers.GpuBuffer$Usage
 *  com.mojang.blaze3d.buffers.GpuBufferSlice
 *  com.mojang.blaze3d.buffers.GpuBufferSlice$MappedView
 *  com.mojang.blaze3d.systems.TransientMemory
 *  com.mojang.blaze3d.util.TransientBlockAllocator
 *  com.mojang.blaze3d.util.TransientBlockAllocator$Allocation
 *  com.mojang.blaze3d.util.TransientBlockAllocator$Allocator
 *  it.unimi.dsi.fastutil.ints.IntArrayList
 *  it.unimi.dsi.fastutil.ints.IntComparator
 *  it.unimi.dsi.fastutil.objects.ReferenceArrayList
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  net.minecraft.util.Mth
 *  org.jspecify.annotations.NonNull
 *  org.lwjgl.system.MemoryUtil
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.MetalGpuBuffer;
import com.mojang.blaze3d.buffers.GpuBuffer;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import com.mojang.blaze3d.systems.TransientMemory;
import com.mojang.blaze3d.util.TransientBlockAllocator;
import it.unimi.dsi.fastutil.ints.IntArrayList;
import it.unimi.dsi.fastutil.ints.IntComparator;
import it.unimi.dsi.fastutil.objects.ReferenceArrayList;
import java.lang.foreign.MemorySegment;
import java.nio.ByteBuffer;
import java.util.List;
import java.util.stream.IntStream;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import net.minecraft.util.Mth;
import org.jspecify.annotations.NonNull;
import org.lwjgl.system.MemoryUtil;

@Environment(value=EnvType.CLIENT)
final class MetalTransientMemory
implements TransientMemory {
    private static final long BLOCK_SIZE = 524288L;
    private static final long MAX_CPU_ALIGNMENT = 16L;
    private static final long MAX_GPU_ALIGNMENT = 256L;
    private static final int BLOCK_USAGE = 3;
    private final MetalDevice device;
    private final MetalCommandEncoder encoder;
    private final TransientBlockAllocator<Long> cpuBlockAllocator = new TransientBlockAllocator(524288L, 16L, TransientBlockAllocator.Allocator.create(MemoryUtil::nmemAlloc, MemoryUtil::nmemFree));
    private final TransientBlockAllocator<MetalGpuBuffer> gpuBlockAllocator;
    private long submitIndex = 0L;

    MetalTransientMemory(MetalDevice device, MetalCommandEncoder encoder) {
        this.device = device;
        this.encoder = encoder;
        this.gpuBlockAllocator = new TransientBlockAllocator(524288L, 256L, TransientBlockAllocator.Allocator.create(this::allocateGpuBlock, this::freeGpuBlock));
    }

    void rotate() {
        this.cpuBlockAllocator.rotate().run();
        this.encoder.queueForDestroy(this.gpuBlockAllocator.rotate());
        ++this.submitIndex;
    }

    void close() {
        this.cpuBlockAllocator.close();
        this.gpuBlockAllocator.close();
    }

    private MetalGpuBuffer allocateGpuBlock(long size) {
        return new MetalGpuBuffer(this.device, 3, size);
    }

    private void freeGpuBlock(MetalGpuBuffer block) {
        block.close();
    }

    public @NonNull ByteBuffer allocateCpu(long size, long alignment, long minimumAllocation, long elementSize) {
        TransientBlockAllocator.Allocation alloc = this.cpuBlockAllocator.allocate(size, alignment, minimumAllocation, elementSize);
        return MemoryUtil.memByteBuffer((long)((Long)alloc.block() + alloc.offset()), (int)((int)alloc.size()));
    }

    public // Could not load outer class - annotation placement on inner may be incorrect
    @NonNull GpuBufferSlice.MappedView allocateStaging(long size, long alignment, @GpuBuffer.Usage int usage, long minimumAllocation, long elementSize) {
        return this.allocateMapped(size, alignment, usage, minimumAllocation, elementSize);
    }

    public @NonNull GpuBufferSlice allocateGpu(long size, long alignment, @GpuBuffer.Usage int usage, long minimumAllocation, long elementSize) {
        TransientBlockAllocator.Allocation alloc = this.gpuBlockAllocator.allocate(size, alignment, minimumAllocation, elementSize);
        return new GpuBufferSlice((GpuBuffer)this.wrap((MetalGpuBuffer)((Object)alloc.block()), usage), alloc.offset(), alloc.size());
    }

    public // Could not load outer class - annotation placement on inner may be incorrect
    @NonNull GpuBufferSlice.MappedView allocateGpuMapped(long size, long alignment, @GpuBuffer.Usage int usage, long minimumAllocation, long elementSize) {
        return this.allocateMapped(size, alignment, usage, minimumAllocation, elementSize);
    }

    private GpuBufferSlice.MappedView allocateMapped(long size, long alignment, @GpuBuffer.Usage int usage, long minimumAllocation, long elementSize) {
        TransientBlockAllocator.Allocation alloc = this.gpuBlockAllocator.allocate(size, alignment, minimumAllocation, elementSize);
        GpuBufferSlice slice = new GpuBufferSlice((GpuBuffer)this.wrap((MetalGpuBuffer)((Object)alloc.block()), usage), alloc.offset(), alloc.size());
        ByteBuffer hostView = ((MetalGpuBuffer)((Object)alloc.block())).sliceStorage(alloc.offset(), alloc.size());
        return new GpuBufferSlice.MappedView(slice, hostView, () -> {});
    }

    private MetalGpuBuffer wrap(MetalGpuBuffer block, @GpuBuffer.Usage int usage) {
        return new TransientGpuBuffer(this.device, block.nativeHandle(), usage, block.size(), this, this.submitIndex);
    }

    public @NonNull GpuBufferSlice uploadStaging(@NonNull List<ByteBuffer> data, long alignment, @GpuBuffer.Usage int usage, long minimumAllocation, long elementSize) {
        return this.upload(data, alignment, usage, minimumAllocation, elementSize);
    }

    public @NonNull GpuBufferSlice uploadGpu(@NonNull List<ByteBuffer> data, long alignment, @GpuBuffer.Usage int usage, long minimumAllocation, long elementSize) {
        return this.upload(data, alignment, usage, minimumAllocation, elementSize);
    }

    private GpuBufferSlice upload(List<ByteBuffer> data, long alignment, @GpuBuffer.Usage int usage, long minimumAllocation, long elementSize) {
        GpuBufferSlice result;
        long totalSize = 0L;
        for (ByteBuffer buffer : data) {
            totalSize += (long)buffer.remaining();
            totalSize = Mth.roundToward((long)totalSize, (long)alignment);
        }
        try (GpuBufferSlice.MappedView mapped = this.allocateMapped(totalSize, alignment, usage, minimumAllocation, elementSize);){
            long mappedPtr = MemoryUtil.memAddress((ByteBuffer)mapped.data());
            long offset = 0L;
            for (ByteBuffer buffer : data) {
                MemoryUtil.memCopy((long)MemoryUtil.memAddress((ByteBuffer)buffer), (long)(mappedPtr + offset), (long)Math.min(mapped.slice().length() - offset, (long)buffer.remaining()));
                offset += (long)buffer.remaining();
                if ((offset = Mth.roundToward((long)offset, (long)alignment)) < mapped.slice().length()) continue;
                break;
            }
            result = mapped.slice();
        }
        return result;
    }

    public @NonNull List<GpuBufferSlice> multiUploadStaging(@NonNull List<ByteBuffer> data, long alignment, @GpuBuffer.Usage int usage) {
        return this.multiUpload(data, alignment, usage);
    }

    public @NonNull List<GpuBufferSlice> multiUploadGpu(@NonNull List<ByteBuffer> data, long alignment, @GpuBuffer.Usage int usage) {
        return this.multiUpload(data, alignment, usage);
    }

    private List<GpuBufferSlice> multiUpload(List<ByteBuffer> data, long alignment, @GpuBuffer.Usage int usage) {
        ReferenceArrayList uploaded = new ReferenceArrayList();
        uploaded.size(data.size());
        IntArrayList sortedIndices = IntArrayList.toList((IntStream)IntStream.range(0, data.size()));
        sortedIndices.sort(IntComparator.comparingInt(index -> ((ByteBuffer)data.get(index)).remaining()));
        while (!sortedIndices.isEmpty()) {
            boolean allocatedAnything = false;
            for (int i = sortedIndices.size() - 1; i >= 0; --i) {
                int bufferIndex = sortedIndices.getInt(i);
                ByteBuffer currentBuffer = data.get(bufferIndex);
                if (!this.gpuBlockAllocator.canAllocateInCurrentBlock((long)currentBuffer.remaining(), alignment)) continue;
                sortedIndices.removeInt(i);
                try (GpuBufferSlice.MappedView view = this.allocateGpuMapped(currentBuffer.remaining(), alignment, usage);){
                    MemoryUtil.memCopy((ByteBuffer)currentBuffer, (ByteBuffer)view.data());
                    uploaded.set(bufferIndex, (Object)view.slice());
                }
                allocatedAnything = true;
                break;
            }
            if (allocatedAnything) continue;
            int bufferIndex = sortedIndices.popInt();
            ByteBuffer currentBuffer = data.get(bufferIndex);
            GpuBufferSlice.MappedView view = this.allocateGpuMapped(currentBuffer.remaining(), alignment, usage);
            try {
                MemoryUtil.memCopy((ByteBuffer)currentBuffer, (ByteBuffer)view.data());
                uploaded.set(bufferIndex, (Object)view.slice());
            }
            finally {
                if (view == null) continue;
                view.close();
            }
        }
        return uploaded;
    }

    private static final class TransientGpuBuffer
    extends MetalGpuBuffer {
        private final MetalTransientMemory owner;
        private final long bufferSubmitIndex;
        private boolean closed;

        TransientGpuBuffer(MetalDevice device, MemorySegment handle, @GpuBuffer.Usage int usage, long size, MetalTransientMemory owner, long submitIndex) {
            super(device, usage, size, handle);
            this.owner = owner;
            this.bufferSubmitIndex = submitIndex;
        }

        @Override
        public boolean isClosed() {
            if (this.closed) {
                return true;
            }
            this.closed = this.bufferSubmitIndex < this.owner.submitIndex;
            return this.closed;
        }

        @Override
        public void close() {
            this.closed = true;
        }

        @Override
        public // Could not load outer class - annotation placement on inner may be incorrect
        @NonNull GpuBufferSlice.MappedView map(long offset, long length, boolean read, boolean write) {
            throw new IllegalStateException("Cannot map transient buffer");
        }

        public @NonNull GpuBufferSlice slice(long offset, long length) {
            throw new IllegalStateException("Cannot slice transient buffer");
        }

        public @NonNull GpuBufferSlice slice() {
            throw new IllegalStateException("Cannot slice transient buffer");
        }
    }
}

