/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.buffers.GpuBuffer
 *  com.mojang.blaze3d.buffers.GpuBufferSlice
 *  com.mojang.blaze3d.buffers.GpuFence
 *  com.mojang.blaze3d.systems.CommandEncoderBackend
 *  com.mojang.blaze3d.systems.GpuQueryPool
 *  com.mojang.blaze3d.systems.RenderPass$RenderArea
 *  com.mojang.blaze3d.systems.RenderPassBackend
 *  com.mojang.blaze3d.systems.RenderPassDescriptor
 *  com.mojang.blaze3d.systems.RenderPassDescriptor$Attachment
 *  com.mojang.blaze3d.systems.TransientMemory
 *  com.mojang.blaze3d.textures.GpuTexture
 *  com.mojang.blaze3d.textures.GpuTextureView
 *  it.unimi.dsi.fastutil.longs.Long2ObjectOpenHashMap
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.joml.Vector4f
 *  org.joml.Vector4fc
 *  org.jspecify.annotations.NonNull
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render;

import com.metallum.Metallum;
import com.metallum.client.metal.render.MetalDestructionQueue;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.MetalFence;
import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.MetalGpuQueryPool;
import com.metallum.client.metal.render.MetalGpuTexture;
import com.metallum.client.metal.render.MetalGpuTextureView;
import com.metallum.client.metal.render.MetalPipelineSupport;
import com.metallum.client.metal.render.MetalRenderPass;
import com.metallum.client.metal.render.MetalTransientMemory;
import com.metallum.client.metal.render.Stats;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLBlitCommandEncoder;
import com.metallum.client.metal.render.mtl.MTLCommandBuffer;
import com.metallum.client.metal.render.mtl.MTLCommandEncoder;
import com.metallum.client.metal.render.mtl.MTLRenderCommandEncoder;
import com.metallum.client.metal.render.mtl.MTLRenderStages;
import com.mojang.blaze3d.buffers.GpuBuffer;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import com.mojang.blaze3d.buffers.GpuFence;
import com.mojang.blaze3d.systems.CommandEncoderBackend;
import com.mojang.blaze3d.systems.GpuQueryPool;
import com.mojang.blaze3d.systems.RenderPass;
import com.mojang.blaze3d.systems.RenderPassBackend;
import com.mojang.blaze3d.systems.RenderPassDescriptor;
import com.mojang.blaze3d.systems.TransientMemory;
import com.mojang.blaze3d.textures.GpuTexture;
import com.mojang.blaze3d.textures.GpuTextureView;
import it.unimi.dsi.fastutil.longs.Long2ObjectOpenHashMap;
import java.lang.foreign.MemorySegment;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayDeque;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.OptionalDouble;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.joml.Vector4f;
import org.joml.Vector4fc;
import org.jspecify.annotations.NonNull;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
final class MetalCommandEncoder
implements CommandEncoderBackend {
    public static final int MAX_SUBMITS_IN_FLIGHT = 3;
    private final MetalDevice device;
    private long currentSubmitIndex = 3L;
    private final InFlight[] inFlight = new InFlight[3];
    private final MemorySegment[] submitSemaphores = new MemorySegment[3];
    private final MetalDestructionQueue destroyQueue = new MetalDestructionQueue(3);
    private final MetalTransientMemory transientMemory;
    private final Map<MetalGpuTexture, Vector4fc> pendingColorClears = new IdentityHashMap<MetalGpuTexture, Vector4fc>();
    private final Map<MetalGpuTexture, Double> pendingDepthClears = new IdentityHashMap<MetalGpuTexture, Double>();
    private final MemorySegment fence;
    private @Nullable MetalRenderPass currentRenderPass;
    private @Nullable MTLCommandBuffer commandBuffer;
    private @Nullable MTLCommandEncoder currentEncoder;
    private MemorySegment renderColorAttachment = MemorySegment.NULL;
    private MemorySegment renderDepthAttachment = MemorySegment.NULL;
    private final Long2ObjectOpenHashMap<ArrayDeque<MemorySegment>> dynamicBackingPool = new Long2ObjectOpenHashMap();
    private static final int MAX_POOLED_DYNAMIC_BACKINGS_PER_SIZE = 8;

    MetalCommandEncoder(MetalDevice device) {
        this.device = device;
        this.transientMemory = new MetalTransientMemory(device, this);
        this.fence = MetalNativeBridge.metallum_create_fence(device.metalDeviceHandle());
        if (MetalNativeBridge.isNullHandle(this.fence)) {
            throw new IllegalStateException("Failed to allocate MTLFence");
        }
        for (int slot = 0; slot < 3; ++slot) {
            this.submitSemaphores[slot] = MetalNativeBridge.metallum_create_semaphore();
            if (!MetalNativeBridge.isNullHandle(this.submitSemaphores[slot])) continue;
            throw new IllegalStateException("Failed to allocate submit semaphore");
        }
    }

    MTLCommandBuffer commandBuffer() {
        if (this.commandBuffer != null) {
            return this.commandBuffer;
        }
        this.commandBuffer = this.device.commandQueue.makeCommandBuffer(this.device.useLabels() ? "Metallum frame " + this.currentSubmitIndex : null);
        return this.commandBuffer;
    }

    MTLBlitCommandEncoder blitCommandEncoder() {
        this.endEncoder();
        MTLBlitCommandEncoder encoder = this.commandBuffer().makeBlitCommandEncoder();
        encoder.waitForFence(this.fence);
        this.currentEncoder = encoder;
        return encoder;
    }

    void endEncoder() {
        if (this.currentEncoder != null) {
            MTLCommandEncoder mTLCommandEncoder = this.currentEncoder;
            if (mTLCommandEncoder instanceof MTLRenderCommandEncoder) {
                MTLRenderCommandEncoder renderEncoder = (MTLRenderCommandEncoder)mTLCommandEncoder;
                renderEncoder.updateFence(this.fence, MTLRenderStages.VertexAndFragment);
            } else {
                mTLCommandEncoder = this.currentEncoder;
                if (mTLCommandEncoder instanceof MTLBlitCommandEncoder) {
                    MTLBlitCommandEncoder blitEncoder = (MTLBlitCommandEncoder)mTLCommandEncoder;
                    blitEncoder.updateFence(this.fence);
                }
            }
            this.currentEncoder.endEncoding();
            this.currentEncoder = null;
        }
        this.renderColorAttachment = MemorySegment.NULL;
        this.renderDepthAttachment = MemorySegment.NULL;
    }

    public @NonNull TransientMemory transientMemory() {
        return this.transientMemory;
    }

    public void submit() {
        if (this.commandBuffer == null) {
            return;
        }
        this.submitRenderPass();
        this.endEncoder();
        int slot = (int)(this.currentSubmitIndex % 3L);
        MemorySegment completedSemaphore = this.submitSemaphores[slot];
        this.commandBuffer.commitWithSignal(completedSemaphore);
        InFlight toClose = this.inFlight[slot];
        this.inFlight[slot] = new InFlight(this.currentSubmitIndex, this.commandBuffer, completedSemaphore);
        this.commandBuffer = null;
        ++this.currentSubmitIndex;
        if (!this.awaitSubmitCompletion(this.currentSubmitIndex - 3L, 5000L)) {
            throw new IllegalStateException("5s timeout reached when waiting for Metal submit completion");
        }
        if (toClose != null) {
            toClose.buffer.close();
        }
        this.transientMemory.rotate();
        this.destroyQueue.rotate();
        Stats.tickRenderStats();
    }

    MTLRenderCommandEncoder renderCommandEncoder(MetalGpuTextureView colorTextureView, @Nullable MetalGpuTextureView depthTextureView, int viewportWidth, int viewportHeight, boolean clearColorEnabled, float clearColorRed, float clearColorGreen, float clearColorBlue, float clearColorAlpha, boolean clearDepthEnabled, double clearDepthValue) {
        MemorySegment colorAttachment = colorTextureView.nativeHandle();
        MemorySegment depthAttachment = depthTextureView == null ? MemorySegment.NULL : depthTextureView.nativeHandle();
        MTLCommandEncoder mTLCommandEncoder = this.currentEncoder;
        if (mTLCommandEncoder instanceof MTLRenderCommandEncoder) {
            MTLRenderCommandEncoder enc = (MTLRenderCommandEncoder)mTLCommandEncoder;
            if (MetalPipelineSupport.sameHandle(this.renderColorAttachment, colorAttachment) && MetalPipelineSupport.sameHandle(this.renderDepthAttachment, depthAttachment)) {
                if (clearColorEnabled || clearDepthEnabled) {
                    enc.clearDraw(colorAttachment, depthAttachment, viewportWidth, viewportHeight, clearColorEnabled, clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, clearDepthEnabled, clearDepthValue);
                }
                return enc;
            }
        }
        this.endEncoder();
        MTLRenderCommandEncoder encoder = this.commandBuffer().makeRenderCommandEncoder(colorAttachment, depthAttachment, viewportWidth, viewportHeight, clearColorEnabled ? 1 : 0, clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, clearDepthEnabled ? 1 : 0, clearDepthValue);
        encoder.waitForFence(this.fence, MTLRenderStages.VertexAndFragment);
        this.currentEncoder = encoder;
        this.renderColorAttachment = colorAttachment;
        this.renderDepthAttachment = depthAttachment;
        return encoder;
    }

    public @NonNull RenderPassBackend createRenderPass(RenderPassDescriptor descriptor) {
        MetalRenderPass renderPass;
        OptionalDouble depthClear;
        RenderPassDescriptor.Attachment colorAttachment = (RenderPassDescriptor.Attachment)descriptor.colorAttachments().getFirst();
        GpuTextureView colorTexture = colorAttachment.textureView();
        Optional<Vector4fc> colorClear = (Optional<Vector4fc>)colorAttachment.clearValue();
        MetalGpuTexture colorTex = (MetalGpuTexture)colorTexture.texture();
        Vector4fc pendingColor = this.pendingColorClears.get((Object)colorTex);
        if (pendingColor != null && MetalCommandEncoder.isFullTextureView(colorTexture) && colorClear.isEmpty()) {
            this.pendingColorClears.remove((Object)colorTex);
            colorClear = Optional.of(pendingColor);
        } else if (pendingColor != null && colorClear.isEmpty()) {
            this.flushPendingClear(colorTex);
        } else {
            this.pendingColorClears.remove((Object)colorTex);
        }
        colorTex.markContentsDirty();
        RenderPassDescriptor.Attachment depthAttachment = descriptor.depthAttachment();
        GpuTextureView depthTexture = depthAttachment == null ? null : depthAttachment.textureView();
        OptionalDouble optionalDouble = depthClear = depthAttachment == null ? OptionalDouble.empty() : (OptionalDouble)depthAttachment.clearValue();
        if (depthAttachment != null) {
            MetalGpuTexture metalDepth = (MetalGpuTexture)depthTexture.texture();
            Double pendingDepth = this.pendingDepthClears.get((Object)metalDepth);
            if (pendingDepth != null && MetalCommandEncoder.isFullTextureView(depthTexture) && depthClear.isEmpty()) {
                this.pendingDepthClears.remove((Object)metalDepth);
                depthClear = OptionalDouble.of(pendingDepth);
            } else if (pendingDepth != null && depthClear.isEmpty()) {
                this.flushPendingClear(metalDepth);
            } else {
                this.pendingDepthClears.remove((Object)metalDepth);
            }
            metalDepth.markContentsDirty();
        }
        assert (descriptor.renderArea != null);
        RenderPass.RenderArea renderArea = descriptor.renderArea;
        this.currentRenderPass = renderPass = new MetalRenderPass(this.device, this, descriptor.label(), colorTexture, depthTexture, renderArea, colorClear.orElse(null), depthClear.isPresent(), depthClear.orElse(0.0));
        renderPass.pushDebugGroup(descriptor.label());
        return renderPass;
    }

    public void submitRenderPass() {
        if (this.currentRenderPass != null) {
            this.currentRenderPass.materializePendingClear();
            this.currentRenderPass.popDebugGroup();
            this.currentRenderPass = null;
        }
    }

    void presentTextureToDrawable(MemorySegment drawable, GpuTextureView textureView) {
        MetalGpuTexture source = (MetalGpuTexture)textureView.texture();
        this.flushPendingClear(source);
        this.submitRenderPass();
        this.endEncoder();
        MTLCommandBuffer commandBuffer = this.commandBuffer();
        commandBuffer.encodePresentTextureToDrawable(drawable, source.nativeHandle(), this.fence);
    }

    public void clearColorTexture(@NonNull GpuTexture colorTexture, @NonNull Vector4fc clearColor) {
        this.pendingColorClears.put((MetalGpuTexture)colorTexture, (Vector4fc)new Vector4f(clearColor));
    }

    public void clearColorAndDepthTextures(@NonNull GpuTexture colorTexture, @NonNull Vector4fc clearColor, @NonNull GpuTexture depthTexture, double clearDepth) {
        MetalGpuTexture color = (MetalGpuTexture)colorTexture;
        MetalGpuTexture depth = (MetalGpuTexture)depthTexture;
        this.pendingColorClears.put(color, (Vector4fc)new Vector4f(clearColor));
        this.pendingDepthClears.put(depth, clearDepth);
    }

    public void clearColorAndDepthTextures(@NonNull GpuTexture colorTexture, @NonNull Vector4fc clearColor, @NonNull GpuTexture depthTexture, double clearDepth, int regionX, int regionY, int regionWidth, int regionHeight) {
        MetalGpuTexture color = (MetalGpuTexture)colorTexture;
        MetalGpuTexture depth = (MetalGpuTexture)depthTexture;
        Vector4f clearColorCopy = new Vector4f(clearColor);
        if (MetalCommandEncoder.isFullTextureRegion(color, depth, regionX, regionY, regionWidth, regionHeight)) {
            this.pendingColorClears.put(color, (Vector4fc)clearColorCopy);
            this.pendingDepthClears.put(depth, clearDepth);
            return;
        }
        color.markContentsDirty();
        depth.markContentsDirty();
        this.submitRenderPass();
        this.endEncoder();
        this.commandBuffer().clearColorDepthTexturesRegion(color.nativeHandle(), clearColorCopy.x(), clearColorCopy.y(), clearColorCopy.z(), clearColorCopy.w(), depth.nativeHandle(), clearDepth, regionX, regionY, regionWidth, regionHeight, this.fence);
    }

    public void clearDepthTexture(@NonNull GpuTexture depthTexture, double clearDepth) {
        this.pendingDepthClears.put((MetalGpuTexture)depthTexture, clearDepth);
    }

    public void writeToBuffer(GpuBufferSlice destination, ByteBuffer data) {
        MetalGpuBuffer buffer = (MetalGpuBuffer)destination.buffer();
        int length = data.remaining();
        if (buffer.isDynamic()) {
            this.orphanWrite(buffer, destination.offset(), data);
            return;
        }
        GpuBufferSlice staging = this.transientMemory.uploadStaging(data, 4L, 16);
        MetalGpuBuffer stagingBuffer = (MetalGpuBuffer)staging.buffer();
        MTLBlitCommandEncoder blit = this.blitCommandEncoder();
        blit.copyFromBufferToBuffer(stagingBuffer.nativeHandle(), staging.offset(), buffer.nativeHandle(), destination.offset(), length);
        this.endEncoder();
    }

    private void orphanWrite(MetalGpuBuffer buffer, long offset, ByteBuffer data) {
        long size = buffer.allocationSize();
        MemorySegment old = buffer.nativeHandle();
        MemorySegment fresh = this.acquireDynamicBacking(size, buffer.resourceOptions());
        if (fresh.address() == 0L) {
            return;
        }
        ByteBuffer freshStorage = MetalNativeBridge.nativeByteBufferView(MetalNativeBridge.metallum_get_buffer_contents(fresh), size).order(ByteOrder.nativeOrder());
        if (offset != 0L || (long)data.remaining() != buffer.size()) {
            ByteBuffer previous = buffer.currentStorage();
            previous.clear();
            freshStorage.duplicate().put(previous);
        }
        ByteBuffer dst = freshStorage.duplicate().order(ByteOrder.nativeOrder());
        dst.position(Math.toIntExact(offset));
        dst.put(data.duplicate());
        buffer.swapBacking(fresh, freshStorage);
        this.recycleDynamicBacking(old, size, buffer.resourceOptions());
    }

    private MemorySegment acquireDynamicBacking(long size, long resourceOptions) {
        long key = MetalDevice.composePoolKey(size, resourceOptions);
        ArrayDeque bucket = (ArrayDeque)this.dynamicBackingPool.get(key);
        if (bucket != null && !bucket.isEmpty()) {
            return (MemorySegment)bucket.pop();
        }
        MemorySegment handle = MetalNativeBridge.metallum_create_buffer(this.device.metalDeviceHandle(), size, resourceOptions);
        if (MetalNativeBridge.isNullHandle(handle)) {
            Metallum.LOGGER.warn("dynamic backing OOM, skipping uniform update this frame");
            return MemorySegment.NULL;
        }
        return handle;
    }

    private void recycleDynamicBacking(MemorySegment handle, long size, long resourceOptions) {
        this.queueForDestroy(() -> {
            long key = MetalDevice.composePoolKey(size, resourceOptions);
            ArrayDeque bucket = (ArrayDeque)this.dynamicBackingPool.computeIfAbsent(key, k -> new ArrayDeque());
            if (bucket.size() < 8) {
                bucket.push(handle);
            } else {
                MetalNativeBridge.metallum_release_object(handle);
            }
        });
    }

    public void copyToBuffer(GpuBufferSlice source, GpuBufferSlice target) {
        MetalGpuBuffer sourceBuffer = (MetalGpuBuffer)source.buffer();
        MetalGpuBuffer targetBuffer = (MetalGpuBuffer)target.buffer();
        MTLBlitCommandEncoder blit = this.blitCommandEncoder();
        blit.copyFromBufferToBuffer(sourceBuffer.nativeHandle(), source.offset(), targetBuffer.nativeHandle(), target.offset(), source.length());
        this.endEncoder();
    }

    public void writeToTexture(@NonNull GpuTexture destination, @NonNull ByteBuffer source, int mipLevel, int depthOrLayer, int destX, int destY, int width, int height) {
        MetalGpuTexture metalDst = (MetalGpuTexture)destination;
        this.flushPendingClearForWrite(metalDst);
        int pixelSize = metalDst.pixelSize();
        int rowBytes = width * pixelSize;
        int bytesPerImage = rowBytes * height;
        GpuBufferSlice slice = this.transientMemory.uploadStaging((ByteBuffer)source.duplicate().limit(bytesPerImage), pixelSize, 16);
        MTLBlitCommandEncoder blit = this.blitCommandEncoder();
        blit.copyFromBufferToTexture(((MetalGpuBuffer)slice.buffer()).nativeHandle(), slice.offset(), metalDst.nativeHandle(), mipLevel, depthOrLayer, destX, destY, width, height, rowBytes, bytesPerImage);
        this.endEncoder();
    }

    public void copyBufferToTexture(@NonNull GpuBufferSlice source, int sourceX, int sourceY, int sourceWidth, int sourceHeight, @NonNull GpuTexture destination, int destinationX, int destinationY, int copyWidth, int copyHeight, int mipLevel, int arrayLayer) {
        MetalGpuTexture metalDst = (MetalGpuTexture)destination;
        this.flushPendingClearForWrite(metalDst);
        int texelSize = destination.getFormat().blockSize();
        long skipBytes = ((long)sourceX + (long)sourceY * (long)sourceWidth) * (long)texelSize;
        long rowBytes = (long)sourceWidth * (long)texelSize;
        MTLBlitCommandEncoder blit = this.blitCommandEncoder();
        blit.copyFromBufferToTexture(((MetalGpuBuffer)source.buffer()).nativeHandle(), source.offset() + skipBytes, metalDst.nativeHandle(), mipLevel, arrayLayer, destinationX, destinationY, copyWidth, copyHeight, rowBytes, rowBytes * (long)sourceHeight);
        this.endEncoder();
    }

    public void copyTextureToBuffer(@NonNull GpuTexture source, @NonNull GpuBuffer destination, long offset, @NonNull Runnable callback, int mipLevel) {
        this.copyTextureToBuffer(source, destination, offset, callback, mipLevel, 0, 0, source.getWidth(mipLevel), source.getHeight(mipLevel));
    }

    public void copyTextureToBuffer(@NonNull GpuTexture source, @NonNull GpuBuffer destination, long offset, @NonNull Runnable callback, int mipLevel, int x, int y, int width, int height) {
        MetalGpuTexture texture = (MetalGpuTexture)source;
        this.flushPendingClear(texture);
        MetalGpuBuffer buffer = (MetalGpuBuffer)destination;
        int bytesPerPixel = texture.pixelSize();
        int rowBytes = width * bytesPerPixel;
        int bytesPerImage = rowBytes * height;
        MTLBlitCommandEncoder blit = this.blitCommandEncoder();
        blit.copyFromTextureToBuffer(texture.nativeHandle(), buffer.nativeHandle(), offset, mipLevel, 0L, x, y, width, height, rowBytes, bytesPerImage);
        this.endEncoder();
        this.queueForDestroy(callback);
    }

    public void copyTextureToTexture(@NonNull GpuTexture source, @NonNull GpuTexture destination, int mipLevel, int destX, int destY, int sourceX, int sourceY, int width, int height) {
        MetalGpuTexture srcTexture = (MetalGpuTexture)source;
        MetalGpuTexture dstTexture = (MetalGpuTexture)destination;
        this.flushPendingClear(srcTexture);
        this.flushPendingClearForWrite(dstTexture);
        MTLBlitCommandEncoder blit = this.blitCommandEncoder();
        blit.copyFromTextureToTexture(srcTexture.nativeHandle(), dstTexture.nativeHandle(), mipLevel, sourceX, sourceY, destX, destY, width, height);
        this.endEncoder();
    }

    public @NonNull GpuFence createFence() {
        return new MetalFence(this, this.currentSubmitIndex);
    }

    void queueForDestroy(Runnable destroyAction) {
        this.destroyQueue.add(destroyAction);
    }

    boolean awaitSubmitCompletion(long submitIndex, long timeoutMs) {
        if (submitIndex == this.currentSubmitIndex) {
            throw new IllegalStateException("Cannot wait on a fence for the current submit");
        }
        for (InFlight f : this.inFlight) {
            if (f == null || f.index != submitIndex) continue;
            return MetalNativeBridge.metallum_semaphore_wait(f.completedSemaphore, Math.max(timeoutMs, 0L)) == 0;
        }
        return true;
    }

    void close() {
        int slot;
        this.submitRenderPass();
        this.endEncoder();
        for (slot = 0; slot < this.inFlight.length; ++slot) {
            InFlight f = this.inFlight[slot];
            if (f == null) continue;
            f.buffer.close();
            this.inFlight[slot] = null;
        }
        for (slot = 0; slot < this.submitSemaphores.length; ++slot) {
            if (MetalNativeBridge.isNullHandle(this.submitSemaphores[slot])) continue;
            MetalNativeBridge.metallum_release_object(this.submitSemaphores[slot]);
            this.submitSemaphores[slot] = MemorySegment.NULL;
        }
        if (this.commandBuffer != null) {
            this.commandBuffer.close();
            this.commandBuffer = null;
        }
        this.transientMemory.close();
        this.device.queueResourceRelease(this.fence);
        this.destroyQueue.close();
        for (ArrayDeque bucket : this.dynamicBackingPool.values()) {
            for (MemorySegment handle : bucket) {
                MetalNativeBridge.metallum_release_object(handle);
            }
        }
        this.dynamicBackingPool.clear();
    }

    void waitForSubmittedGpuWork() {
        if (this.commandBuffer != null || this.currentRenderPass != null || this.currentEncoder != null) {
            this.submit();
        } else {
            this.endEncoder();
        }
        long latestSubmit = this.currentSubmitIndex - 1L;
        if (latestSubmit >= 3L) {
            this.awaitSubmitCompletion(latestSubmit, Long.MAX_VALUE);
        }
    }

    public void writeTimestamp(@NonNull GpuQueryPool pool, int index) {
        if (pool instanceof MetalGpuQueryPool) {
            MetalGpuQueryPool metalPool = (MetalGpuQueryPool)pool;
            if (index >= 0 && index < pool.size()) {
                metalPool.setValue(index, this.device.getTimestampNow());
            }
        }
    }

    private void flushPendingClearForWrite(MetalGpuTexture texture) {
        this.flushPendingClear(texture);
        texture.markContentsDirty();
    }

    void flushPendingClear(MetalGpuTexture texture) {
        Vector4fc colorClear = this.pendingColorClears.remove((Object)texture);
        Double depthClear = this.pendingDepthClears.remove((Object)texture);
        if (colorClear == null && depthClear == null) {
            return;
        }
        if (texture.clearIsRedundant(colorClear, depthClear)) {
            return;
        }
        this.endEncoder();
        MTLRenderCommandEncoder encoder = this.commandBuffer().makeRenderCommandEncoder(colorClear != null ? texture.nativeHandle() : null, depthClear != null ? texture.nativeHandle() : null, 1.0, 1.0, colorClear != null ? 1 : 0, colorClear != null ? colorClear.x() : 0.0f, colorClear != null ? colorClear.y() : 0.0f, colorClear != null ? colorClear.z() : 0.0f, colorClear != null ? colorClear.w() : 0.0f, depthClear != null ? 1 : 0, depthClear != null ? depthClear : 1.0);
        encoder.waitForFence(this.fence, MTLRenderStages.VertexAndFragment);
        this.currentEncoder = encoder;
        texture.recordMaterializedClear(colorClear, depthClear);
    }

    private static boolean isFullTextureView(GpuTextureView textureView) {
        return textureView.baseMipLevel() == 0 && textureView.mipLevels() >= textureView.texture().getMipLevels() && textureView.texture().getDepthOrLayers() == 1;
    }

    private static boolean isFullTextureRegion(MetalGpuTexture color, MetalGpuTexture depth, int x, int y, int width, int height) {
        return x == 0 && y == 0 && width == color.getWidth(0) && height == color.getHeight(0) && width == depth.getWidth(0) && height == depth.getHeight(0);
    }

    private record InFlight(long index, MTLCommandBuffer buffer, MemorySegment completedSemaphore) {
    }
}
