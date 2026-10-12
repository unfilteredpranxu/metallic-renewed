/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.DiagLog
 *  com.metallum.client.metal.render.MetalTransientMemory$MappedView
 *  com.metallum.client.metal.render.sodium.MetalGlBufferRegistry
 *  com.metallum.client.metal.render.sodium.MetalGlBufferRegistry$MetalGlBufferEntry
 *  com.metallum.client.metal.render.sodium.MetalSodiumActiveState
 *  com.metallum.client.metal.render.sodium.MetalSodiumCommandList
 *  com.metallum.client.metal.render.sodium.MetalSodiumDrawCommandList
 *  com.metallum.client.metal.render.sodium.MetalSodiumFence
 *  com.metallum.client.metal.render.sodium.MetalSodiumTessellation
 *  com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers$RegionUniformSlices
 *  com.metallum.client.metal.render.sodium.SodiumUsageMapper
 *  com.mojang.blaze3d.buffers.GpuBufferSlice
 *  com.mojang.blaze3d.systems.CommandEncoder
 *  java.lang.foreign.MemorySegment
 *  net.caffeinemc.mods.sodium.client.gl.array.GlVertexArray
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBuffer
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferMapFlags
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferMapping
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferStorageFlags
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferTarget
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferUsage
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlImmutableBuffer
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlMutableBuffer
 *  net.caffeinemc.mods.sodium.client.gl.device.CommandList
 *  net.caffeinemc.mods.sodium.client.gl.device.DrawCommandList
 *  net.caffeinemc.mods.sodium.client.gl.sync.GlFence
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.GlPrimitiveType
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.GlTessellation
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.TessellationBinding
 *  net.caffeinemc.mods.sodium.client.gl.util.EnumBitField
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.NonNull
 *  org.jspecify.annotations.Nullable
 *  org.lwjgl.system.MemoryUtil
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.Metallum;
import com.metallum.client.metal.render.DiagLog;
import com.metallum.client.metal.render.MetalBackend;
import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.MetalTransientMemory;
import com.metallum.client.metal.render.sodium.MetalGlBufferRegistry;
import com.metallum.client.metal.render.sodium.MetalSodiumActiveState;
import com.metallum.client.metal.render.sodium.MetalSodiumDrawCommandList;
import com.metallum.client.metal.render.sodium.MetalSodiumFence;
import com.metallum.client.metal.render.sodium.MetalSodiumTessellation;
import com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers;
import com.metallum.client.metal.render.sodium.SodiumUsageMapper;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import com.mojang.blaze3d.systems.CommandEncoder;
import java.lang.foreign.MemorySegment;
import java.nio.ByteBuffer;
import net.caffeinemc.mods.sodium.client.gl.array.GlVertexArray;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBuffer;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferMapFlags;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferMapping;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferStorageFlags;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferTarget;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferUsage;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlImmutableBuffer;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlMutableBuffer;
import net.caffeinemc.mods.sodium.client.gl.device.CommandList;
import net.caffeinemc.mods.sodium.client.gl.device.DrawCommandList;
import net.caffeinemc.mods.sodium.client.gl.sync.GlFence;
import net.caffeinemc.mods.sodium.client.gl.tessellation.GlPrimitiveType;
import net.caffeinemc.mods.sodium.client.gl.tessellation.GlTessellation;
import net.caffeinemc.mods.sodium.client.gl.tessellation.TessellationBinding;
import net.caffeinemc.mods.sodium.client.gl.util.EnumBitField;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.NonNull;
import org.jspecify.annotations.Nullable;
import org.lwjgl.system.MemoryUtil;

/*
 * Exception performing whole class analysis ignored.
 */
@Environment(value=EnvType.CLIENT)
public final class MetalSodiumCommandList
implements CommandList {
    private static volatile MetalSodiumActiveState activeSodiumState;
    private static long uploadCalls;
    private static long uploadBytes;
    private static long uploadUs;
    private static long lastUploadReportNanos;

    public GlMutableBuffer createMutableBuffer() {
        return new GlMutableBuffer();
    }

    public GlImmutableBuffer createImmutableBuffer(long bufferSize, EnumBitField<GlBufferStorageFlags> flags) {
        GlImmutableBuffer buffer = new GlImmutableBuffer(flags);
        MetalGlBufferRegistry.MetalGlBufferEntry entry = MetalSodiumCommandList.entryOf((GlBuffer)buffer);
        entry.markImmutable();
        if (bufferSize > 0L) {
            entry.ensureAllocated(bufferSize, SodiumUsageMapper.toStorageUsage(flags));
        }
        return buffer;
    }

    public void allocateStorage(GlMutableBuffer buffer, long bufferSize, GlBufferUsage usage) {
        int minecraftUsage = SodiumUsageMapper.toMinecraftUsage((GlBufferUsage)usage);
        long size = bufferSize;
        if ((minecraftUsage & 0x28) == 40) {
            size = bufferSize + 262143L & 0xFFFFFFFFFFFC0000L;
        }
        MetalSodiumCommandList.entryOf((GlBuffer)buffer).ensureAllocated(size, minecraftUsage);
        buffer.setSize(bufferSize);
    }

    public void uploadData(GlMutableBuffer glBuffer, ByteBuffer byteBuffer, GlBufferUsage usage) {
        long t0 = System.nanoTime();
        MetalGlBufferRegistry.MetalGlBufferEntry entry = MetalSodiumCommandList.entryOf((GlBuffer)glBuffer);
        int length = byteBuffer.remaining();
        int mcUsage = SodiumUsageMapper.toMinecraftUsage((GlBufferUsage)usage);
        if (MetalGlBufferRegistry.MetalGlBufferEntry.isStagingUsage((int)mcUsage)) {
            MetalCommandEncoder encoder = (MetalCommandEncoder)MetalSodiumCommandList.encoder();
            MetalTransientMemory.MappedView view = encoder.allocateTransientStaging(length, 16L);
            MemoryUtil.memCopy((long)MemoryUtil.memAddress((ByteBuffer)byteBuffer), (long)MemoryUtil.memAddress((ByteBuffer)view.data()), (long)length);
            entry.pushStagingUpload(view.slice());
            glBuffer.setSize((long)length);
            MetalSodiumCommandList.recordUpload((long)length, (long)t0);
            return;
        }
        entry.ensureAllocated((long)length, mcUsage);
        glBuffer.setSize((long)length);
        MetalSodiumCommandList.writeBuffer((MetalGlBufferRegistry.MetalGlBufferEntry)entry, (long)0L, (ByteBuffer)byteBuffer.duplicate());
        MetalSodiumCommandList.recordUpload((long)length, (long)t0);
    }

    private static void recordUpload(long bytes, long t0) {
        long elapsedUs = (System.nanoTime() - t0) / 1000L;
        ++uploadCalls;
        uploadBytes += bytes;
        uploadUs += elapsedUs;
        long now = System.nanoTime();
        if (now - lastUploadReportNanos > 5000000000L) {
            lastUploadReportNanos = now;
            DiagLog.log((String)"[diag] sodium-upload calls=%d bytes=%d us=%d", (Object[])new Object[]{uploadCalls, uploadBytes, uploadUs});
            uploadCalls = 0L;
            uploadBytes = 0L;
            uploadUs = 0L;
        }
    }

    public void uploadDataToOffset(GlMutableBuffer glBuffer, int offset, long pointer, int size) {
        long t0 = System.nanoTime();
        MetalGlBufferRegistry.MetalGlBufferEntry entry = MetalSodiumCommandList.entryOf((GlBuffer)glBuffer);
        if (entry.buffer() == null || entry.size() < (long)offset + (long)size) {
            int usage = entry.usage() != 0 ? entry.usage() : 40;
            entry.ensureAllocated((long)offset + (long)size, usage);
        }
        ByteBuffer src = MemorySegment.ofAddress((long)pointer).reinterpret((long)size).asByteBuffer();
        MetalSodiumCommandList.writeBuffer((MetalGlBufferRegistry.MetalGlBufferEntry)entry, (long)offset, (ByteBuffer)src);
        MetalSodiumCommandList.recordUpload((long)size, (long)t0);
    }

    public void copyBufferSubData(GlBuffer src, GlBuffer dst, long readOffset, long writeOffset, long bytes) {
        MetalGlBufferRegistry.MetalGlBufferEntry srcEntry = MetalSodiumCommandList.entryOf((GlBuffer)src);
        GpuBufferSlice srcSlice = srcEntry.popStagingUpload();
        MetalGpuBuffer dstBuffer = MetalSodiumCommandList.requireBuffer((GlBuffer)dst);
        if (srcSlice != null) {
            MetalSodiumCommandList.encoder().copyToBuffer(new GpuBufferSlice(srcSlice.buffer(), srcSlice.offset() + readOffset, bytes), dstBuffer.slice(writeOffset, bytes));
            return;
        }
        MetalGpuBuffer srcBuffer = MetalSodiumCommandList.requireBuffer((GlBuffer)src);
        MetalSodiumCommandList.encoder().copyToBuffer(srcBuffer.slice(readOffset, bytes), dstBuffer.slice(writeOffset, bytes));
    }

    public void deleteBuffer(GlBuffer buffer) {
        MetalGlBufferRegistry.MetalGlBufferEntry entry = MetalGlBufferRegistry.remove((int)buffer.handle());
        if (entry == null) {
            return;
        }
        if (buffer.getActiveMapping() != null) {
            buffer.getActiveMapping().dispose();
            buffer.setActiveMapping(null);
        }
        entry.dispose();
        buffer.invalidateHandle();
    }

    public GlBufferMapping mapBuffer(GlBuffer buffer, long offset, long length, EnumBitField<GlBufferMapFlags> flags) {
        MetalGlBufferRegistry.MetalGlBufferEntry entry;
        boolean needRebuild;
        if (buffer.getActiveMapping() != null) {
            throw new IllegalStateException("Buffer is already mapped");
        }
        if (flags.contains((Enum)GlBufferMapFlags.PERSISTENT) && !(buffer instanceof GlImmutableBuffer)) {
            throw new IllegalStateException("Tried to map mutable buffer as persistent");
        }
        if (buffer instanceof GlImmutableBuffer) {
            EnumBitField storageFlags = ((GlImmutableBuffer)buffer).getFlags();
            if (flags.contains((Enum)GlBufferMapFlags.PERSISTENT) && !storageFlags.contains((Enum)GlBufferStorageFlags.PERSISTENT)) {
                throw new IllegalArgumentException("Tried to map non-persistent buffer as persistent");
            }
            if (flags.contains((Enum)GlBufferMapFlags.WRITE) && !storageFlags.contains((Enum)GlBufferStorageFlags.MAP_WRITE)) {
                throw new IllegalStateException("Tried to map non-writable buffer as writable");
            }
            if (flags.contains((Enum)GlBufferMapFlags.READ) && !storageFlags.contains((Enum)GlBufferStorageFlags.MAP_READ)) {
                throw new IllegalStateException("Tried to map non-readable buffer as readable");
            }
        }
        boolean bl = needRebuild = (entry = MetalSodiumCommandList.entryOf((GlBuffer)buffer)).buffer() == null || !entry.buffer().isCpuAccessible() || entry.size() < offset + length;
        if (needRebuild && entry.buffer() != null && !flags.contains((Enum)GlBufferMapFlags.INVALIDATE_BUFFER) && !flags.contains((Enum)GlBufferMapFlags.PERSISTENT)) {
            Metallum.LOGGER.warn("[metallum] mapBuffer on non-CPU-accessible buffer without INVALIDATE_BUFFER (handle={}, size={})", (Object)buffer.handle(), (Object)entry.size());
        }
        if (needRebuild) {
            entry.ensureAllocated(offset + length, SodiumUsageMapper.toMapUsage(flags));
        }
        ByteBuffer map = entry.buffer().sliceStorage(offset, length);
        GlBufferMapping mapping = new GlBufferMapping(buffer, map);
        buffer.setActiveMapping(mapping);
        return mapping;
    }

    public void unmap(GlBufferMapping map) {
        this.checkMapDisposed(map);
        map.getBufferObject().setActiveMapping(null);
        map.dispose();
    }

    public void flushMappedRange(GlBufferMapping map, int offset, int length) {
        this.checkMapDisposed(map);
    }

    public GlFence createFence() {
        return new MetalSodiumFence();
    }

    public void bindBuffer(GlBufferTarget target, GlBuffer buffer) {
    }

    public void bindVertexArray(GlVertexArray array) {
    }

    public void unbindVertexArray() {
    }

    public void deleteVertexArray(GlVertexArray vertexArray) {
    }

    public void flush() {
    }

    public GlTessellation createTessellation(GlPrimitiveType primitiveType, TessellationBinding[] bindings) {
        return new MetalSodiumTessellation(primitiveType, bindings);
    }

    public void deleteTessellation(GlTessellation tessellation) {
    }

    public DrawCommandList beginTessellating(GlTessellation tessellation) {
        MetalSodiumActiveState state = MetalSodiumCommandList.activeSodiumState();
        if (state == null) {
            throw new IllegalStateException("Sodium beginTessellating without active renderer state (renderer.begin() not called?)");
        }
        if (!(tessellation instanceof MetalSodiumTessellation)) {
            throw new IllegalStateException("Tessellation is not Metal-backed: " + tessellation.getClass().getName());
        }
        MetalSodiumTessellation metalTessellation = (MetalSodiumTessellation)tessellation;
        state.uniformBuffers().uploadPassUniforms(state.shaderInterface());
        MetalSodiumUniformBuffers.RegionUniformSlices regionUniforms = state.uniformBuffers().allocateRegionUniforms(state.shaderInterface());
        return new MetalSodiumDrawCommandList((MetalCommandEncoder)MetalSodiumCommandList.encoder(), metalTessellation, state, regionUniforms);
    }

    public static void setActiveSodiumState(MetalSodiumActiveState state) {
        activeSodiumState = state;
    }

    public static void clearActiveSodiumState() {
        activeSodiumState = null;
    }

    public static @Nullable MetalSodiumActiveState activeSodiumState() {
        return activeSodiumState;
    }

    private void checkMapDisposed(GlBufferMapping map) {
        if (map.isDisposed()) {
            throw new IllegalStateException("Buffer mapping is already disposed");
        }
    }

    private static MetalGlBufferRegistry.MetalGlBufferEntry entryOf(GlBuffer buffer) {
        MetalGlBufferRegistry.MetalGlBufferEntry entry = MetalGlBufferRegistry.get((int)buffer.handle());
        if (entry == null) {
            throw new IllegalStateException("Sodium GlBuffer not registered (handle=" + buffer.handle() + ")");
        }
        return entry;
    }

    static MetalGpuBuffer requireBuffer(GlBuffer buffer) {
        MetalGlBufferRegistry.MetalGlBufferEntry entry = MetalSodiumCommandList.entryOf((GlBuffer)buffer);
        MetalGpuBuffer metal = entry.buffer();
        if (metal == null) {
            throw new IllegalStateException("Sodium GlBuffer not allocated (handle=" + buffer.handle() + ")");
        }
        return metal;
    }

    private static @NonNull CommandEncoder encoder() {
        return MetalBackend.activeDevice().createCommandEncoder();
    }

    private static void writeBuffer(MetalGlBufferRegistry.MetalGlBufferEntry entry, long offset, ByteBuffer data) {
        MetalGpuBuffer metal = entry.buffer();
        if (metal == null) {
            throw new IllegalStateException("Sodium GlBuffer not allocated (handle=" + entry.handle() + ")");
        }
        if (metal.isCpuAccessible()) {
            ByteBuffer dst = metal.currentStorage();
            dst.position(Math.toIntExact(offset));
            dst.put(data);
        } else {
            MetalSodiumCommandList.encoder().writeToBuffer(metal.slice(offset, data.remaining()), data);
        }
    }
}

