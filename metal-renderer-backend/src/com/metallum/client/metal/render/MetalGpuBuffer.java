/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.buffers.GpuBuffer
 *  com.mojang.blaze3d.buffers.GpuBuffer$Usage
 *  com.mojang.blaze3d.buffers.GpuBufferSlice$MappedView
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.NonNull
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLHazardTrackingMode;
import com.metallum.client.metal.render.mtl.MTLResourceOptions;
import com.metallum.client.metal.render.mtl.MTLStorageMode;
import com.mojang.blaze3d.buffers.GpuBuffer;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import java.lang.foreign.MemorySegment;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.NonNull;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
class MetalGpuBuffer
extends GpuBuffer {
    private final MetalDevice device;
    private final boolean cpuAccessible;
    private final boolean dynamic;
    private final long resourceOptions;
    private final long allocationSize;
    private @Nullable MemorySegment nativeHandle;
    private @Nullable ByteBuffer storage;
    private boolean closed;

    MetalGpuBuffer(MetalDevice device, @GpuBuffer.Usage int usage, long size) {
        super(usage, size);
        this.device = device;
        this.dynamic = MetalGpuBuffer.isDynamic(usage);
        this.cpuAccessible = MetalGpuBuffer.isCpuAccessible(usage) || this.dynamic;
        this.resourceOptions = MetalGpuBuffer.toMtlResourceOptions(usage);
        if (size <= 0L) {
            throw new IllegalArgumentException("Metal buffer size must be > 0 (got " + size + ")");
        }
        long aligned = size + 15L & 0xFFFFFFFFFFFFFFF0L;
        if (aligned <= 0L) {
            throw new IllegalArgumentException("Metal buffer size overflow after alignment: " + size);
        }
        this.allocationSize = aligned;
        MemorySegment pooled = device.tryAcquirePooledBuffer(this.allocationSize, this.resourceOptions);
        if (!MetalNativeBridge.isNullHandle(pooled)) {
            this.nativeHandle = pooled;
            if (this.cpuAccessible) {
                MemorySegment contents = MetalNativeBridge.metallum_get_buffer_contents(pooled);
                if (MetalNativeBridge.isNullHandle(contents)) {
                    MetalNativeBridge.metallum_release_object(pooled);
                    this.nativeHandle = null;
                    throw new IllegalStateException("MTLBuffer.contents returned null for pooled buffer (size=" + this.allocationSize + ", resourceOptions=" + this.resourceOptions + ")");
                }
                this.storage = MetalNativeBridge.nativeByteBufferView(contents, this.allocationSize).order(ByteOrder.nativeOrder());
            }
            return;
        }
        long max = device.maxBufferAllocationSize();
        if (max > 0L && this.allocationSize > max) {
            throw new IllegalArgumentException("Metal buffer size " + this.allocationSize + " exceeds device max " + max);
        }
        this.nativeHandle = MetalNativeBridge.metallum_create_buffer(device.metalDeviceHandle(), this.allocationSize, this.resourceOptions);
        if (MetalNativeBridge.isNullHandle(this.nativeHandle)) {
            throw new IllegalStateException("Failed to create Metal buffer (size=" + this.allocationSize + ", resourceOptions=" + this.resourceOptions + ", device=" + this.device.getClass().getSimpleName() + ")");
        }
        if (this.cpuAccessible) {
            MemorySegment contents = MetalNativeBridge.metallum_get_buffer_contents(this.nativeHandle);
            if (MetalNativeBridge.isNullHandle(contents)) {
                MetalNativeBridge.metallum_release_object(this.nativeHandle);
                this.nativeHandle = null;
                throw new IllegalStateException("MTLBuffer.contents returned null (size=" + this.allocationSize + ", resourceOptions=" + this.resourceOptions + ")");
            }
            this.storage = MetalNativeBridge.nativeByteBufferView(contents, this.allocationSize).order(ByteOrder.nativeOrder());
        }
    }

    MetalGpuBuffer(MetalDevice device, @GpuBuffer.Usage int usage, long size, @Nullable MemorySegment wrappedHandle) {
        super(usage, size);
        this.device = device;
        this.cpuAccessible = false;
        this.dynamic = false;
        this.resourceOptions = 0L;
        this.allocationSize = size;
        this.nativeHandle = wrappedHandle;
        this.storage = null;
    }

    ByteBuffer sliceStorage(long offset, long length) {
        if (this.storage == null) {
            throw new IllegalStateException("Buffer is not CPU-accessible");
        }
        ByteBuffer duplicate = this.storage.duplicate().order(this.storage.order());
        duplicate.position(Math.toIntExact(offset));
        duplicate.limit(Math.toIntExact(offset + length));
        return duplicate.slice().order(this.storage.order());
    }

    MemorySegment nativeHandle() {
        if (this.nativeHandle == null || this.nativeHandle.address() == 0L) {
            throw new IllegalStateException("Native Metal buffer is closed or null");
        }
        return this.nativeHandle;
    }

    boolean isDynamic() {
        return this.dynamic;
    }

    long allocationSize() {
        return this.allocationSize;
    }

    long resourceOptions() {
        return this.resourceOptions;
    }

    ByteBuffer currentStorage() {
        if (this.storage == null) {
            throw new IllegalStateException("Buffer is not CPU-accessible");
        }
        return this.storage.duplicate().order(this.storage.order());
    }

    void swapBacking(MemorySegment handle, ByteBuffer storage) {
        this.nativeHandle = handle;
        this.storage = storage;
    }

    public boolean isClosed() {
        return this.closed || this.nativeHandle == null;
    }

    public void close() {
        if (this.closed) {
            return;
        }
        this.closed = true;
        this.storage = null;
        if (this.nativeHandle != null) {
            MemorySegment handle = this.nativeHandle;
            this.nativeHandle = null;
            this.device.queueBufferRelease(handle, this.allocationSize, this.resourceOptions);
        }
    }

    public // Could not load outer class - annotation placement on inner may be incorrect
     @NonNull GpuBufferSlice.MappedView map(long offset, long length, boolean read, boolean write) {
        if (this.isClosed()) {
            throw new IllegalStateException("Buffer already closed");
        }
        if (!read && !write) {
            throw new IllegalArgumentException("At least read or write must be true");
        }
        if (read && (this.usage() & 1) == 0) {
            throw new IllegalStateException("Buffer is not readable");
        }
        if (write && (this.usage() & 2) == 0) {
            throw new IllegalStateException("Buffer is not writable");
        }
        ByteBuffer mapped = this.sliceStorage(offset, length);
        return new GpuBufferSlice.MappedView(this.slice(offset, length), mapped, () -> {});
    }

    public int getUsage() {
        return this.usage();
    }

    private static boolean isCpuAccessible(@GpuBuffer.Usage int usage) {
        return (usage & 1) != 0 || (usage & 2) != 0 || (usage & 4) != 0;
    }

    private static boolean isDynamic(@GpuBuffer.Usage int usage) {
        return (usage & 0x80) != 0 && (usage & 8) != 0;
    }

    private static long toMtlResourceOptions(@GpuBuffer.Usage int usage) {
        MTLStorageMode storageMode = MetalGpuBuffer.isCpuAccessible(usage) || MetalGpuBuffer.isDynamic(usage) ? MTLStorageMode.Shared : MTLStorageMode.Private;
        return MTLResourceOptions.of(storageMode, MTLHazardTrackingMode.Untracked);
    }
}

