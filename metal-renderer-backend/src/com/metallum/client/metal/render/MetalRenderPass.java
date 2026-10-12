/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.GpuFormat
 *  com.mojang.blaze3d.IndexType
 *  com.mojang.blaze3d.buffers.GpuBuffer
 *  com.mojang.blaze3d.buffers.GpuBuffer$Usage
 *  com.mojang.blaze3d.buffers.GpuBufferSlice
 *  com.mojang.blaze3d.buffers.GpuBufferSlice$MappedView
 *  com.mojang.blaze3d.pipeline.RenderPipeline
 *  com.mojang.blaze3d.systems.GpuQueryPool
 *  com.mojang.blaze3d.systems.RenderPass$Draw
 *  com.mojang.blaze3d.systems.RenderPass$RenderArea
 *  com.mojang.blaze3d.systems.RenderPassBackend
 *  com.mojang.blaze3d.systems.ScissorState
 *  com.mojang.blaze3d.textures.GpuSampler
 *  com.mojang.blaze3d.textures.GpuTextureView
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  net.minecraft.SharedConstants
 *  org.joml.Vector4fc
 *  org.jspecify.annotations.NonNull
 *  org.jspecify.annotations.Nullable
 *  org.lwjgl.PointerBuffer
 *  org.lwjgl.system.CustomBuffer
 *  org.lwjgl.system.MemoryUtil
 *  org.lwjgl.vulkan.VkDrawIndexedIndirectCommand
 *  org.lwjgl.vulkan.VkDrawIndirectCommand
 */
package com.metallum.client.metal.render;

import com.metallum.Metallum;
import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalCompiledRenderPipeline;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.MetalGpuQueryPool;
import com.metallum.client.metal.render.MetalGpuSampler;
import com.metallum.client.metal.render.MetalGpuTexture;
import com.metallum.client.metal.render.MetalGpuTextureView;
import com.metallum.client.metal.render.Stats;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLIndexType;
import com.metallum.client.metal.render.mtl.MTLPixelFormat;
import com.metallum.client.metal.render.mtl.MTLPrimitiveType;
import com.metallum.client.metal.render.mtl.MTLRenderCommandEncoder;
import com.metallum.client.metal.render.mtl.MTLWinding;
import com.mojang.blaze3d.GpuFormat;
import com.mojang.blaze3d.IndexType;
import com.mojang.blaze3d.buffers.GpuBuffer;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.systems.GpuQueryPool;
import com.mojang.blaze3d.systems.RenderPass;
import com.mojang.blaze3d.systems.RenderPassBackend;
import com.mojang.blaze3d.systems.ScissorState;
import com.mojang.blaze3d.textures.GpuSampler;
import com.mojang.blaze3d.textures.GpuTextureView;
import java.lang.foreign.MemorySegment;
import java.nio.IntBuffer;
import java.nio.ShortBuffer;
import java.util.Collection;
import java.util.HashMap;
import java.util.function.Supplier;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import net.minecraft.SharedConstants;
import org.joml.Vector4fc;
import org.jspecify.annotations.NonNull;
import org.jspecify.annotations.Nullable;
import org.lwjgl.PointerBuffer;
import org.lwjgl.system.CustomBuffer;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.vulkan.VkDrawIndexedIndirectCommand;
import org.lwjgl.vulkan.VkDrawIndirectCommand;

@Environment(value=EnvType.CLIENT)
final class MetalRenderPass
implements RenderPassBackend {
    static final boolean VALIDATION = SharedConstants.IS_RUNNING_IN_IDE;
    static final int MAX_VERTEX_BUFFERS = 16;
    private final MetalDevice device;
    private final MetalCommandEncoder commandEncoder;
    private final @Nullable String label;
    private final GpuTextureView colorTexture;
    private final @Nullable GpuTextureView depthTexture;
    private final RenderPass.RenderArea renderArea;
    private @Nullable Vector4fc clearColor;
    private boolean clearDepthEnabled;
    private final double clearDepthValue;
    private final ScissorState scissorState = new ScissorState();
    private final GpuBufferSlice[] vertexBuffers = new GpuBufferSlice[16];
    private final HashMap<String, GpuBufferSlice> uniforms = new HashMap();
    private final HashMap<String, TextureViewAndSampler> samplers = new HashMap();
    private long dirtyDescriptorMask;
    private @Nullable MetalCompiledRenderPipeline compiledPipeline;
    private @Nullable GpuBuffer indexBuffer;
    private MTLIndexType indexType = MTLIndexType.UInt16;
    private int pushedDebugGroups = 0;
    private boolean scissorDirty = true;
    private boolean vertexBuffersDirty = true;
    private boolean pipelineDirty = true;

    MetalRenderPass(MetalDevice device, MetalCommandEncoder encoder, Supplier<String> label, GpuTextureView colorTexture, @Nullable GpuTextureView depthTexture, RenderPass.RenderArea renderArea, @Nullable Vector4fc clearColor, boolean clearDepthEnabled, double clearDepthValue) {
        this.device = device;
        this.commandEncoder = encoder;
        this.label = device.useLabels() ? label.get() : null;
        this.colorTexture = colorTexture;
        this.depthTexture = depthTexture;
        this.renderArea = renderArea;
        this.clearColor = clearColor;
        this.clearDepthEnabled = clearDepthEnabled;
        this.clearDepthValue = clearDepthValue;
    }

    public void pushDebugGroup(@NonNull Supplier<String> label) {
        ++this.pushedDebugGroups;
        if (this.device.useLabels()) {
            this.commandEncoder.commandBuffer().pushDebugGroup(label.get());
        }
    }

    public void popDebugGroup() {
        if (this.pushedDebugGroups == 0) {
            throw new IllegalStateException("Can't pop more debug groups than was pushed!");
        }
        --this.pushedDebugGroups;
        if (this.device.useLabels()) {
            this.commandEncoder.commandBuffer().popDebugGroup();
        }
    }

    public void setPipeline(@NonNull RenderPipeline pipeline) {
        MetalCompiledRenderPipeline compiled = this.device.getOrCompilePipeline(pipeline);
        if (this.compiledPipeline != compiled) {
            this.compiledPipeline = compiled;
            this.vertexBuffersDirty = true;
            this.pipelineDirty = true;
        }
    }

    public void bindTexture(@NonNull String name, @Nullable GpuTextureView textureView, @Nullable GpuSampler sampler) {
        if (textureView != null && sampler != null) {
            this.samplers.put(name, new TextureViewAndSampler(textureView, sampler));
            this.commandEncoder.flushPendingClear((MetalGpuTexture)textureView.texture());
            this.markDescriptorDirty(name);
        } else if (textureView == null && sampler == null) {
            this.samplers.remove(name);
        } else {
            throw new IllegalArgumentException();
        }
    }

    public void setUniform(@NonNull String name, GpuBuffer value) {
        this.setUniform(name, value.slice());
    }

    public void setUniform(@NonNull String name, @NonNull GpuBufferSlice value) {
        this.uniforms.put(name, value);
        this.markDescriptorDirty(name);
    }

    public void enableScissor(int x, int y, int width, int height) {
        if (this.scissorState.enabled() && this.scissorState.x() == x && this.scissorState.y() == y && this.scissorState.width() == width && this.scissorState.height() == height) {
            return;
        }
        this.scissorState.enable(x, y, width, height);
        this.scissorDirty = true;
    }

    public void disableScissor() {
        if (!this.scissorState.enabled()) {
            return;
        }
        this.scissorState.disable();
        this.scissorDirty = true;
    }

    public void setVertexBuffer(int slot, @Nullable GpuBufferSlice vertexBuffer) {
        if (slot < 0 || slot >= 16) {
            throw new IllegalArgumentException("Unsupported Metal vertex buffer slot: " + slot);
        }
        if (!MetalRenderPass.sameSlice(this.vertexBuffers[slot], vertexBuffer)) {
            this.vertexBuffers[slot] = vertexBuffer;
            this.vertexBuffersDirty = true;
        }
    }

    public void setIndexBuffer(@Nullable GpuBuffer indexBuffer, @NonNull IndexType indexType) {
        this.setIndexBuffer(indexBuffer, MTLIndexType.from(indexType));
    }

    private void setIndexBuffer(@Nullable GpuBuffer indexBuffer, MTLIndexType indexType) {
        if (this.indexBuffer != indexBuffer || this.indexType != indexType) {
            this.indexBuffer = indexBuffer;
            this.indexType = indexType;
        }
    }

    public void drawIndexed(int indexCount, int instanceCount, int firstIndex, int vertexOffset, int firstInstance) {
        if (this.indexBuffer == null) {
            Metallum.LOGGER.warn("[metallum] drawIndexed called with null index buffer, skipping draw");
            return;
        }
        MetalGpuBuffer nativeIndexBuffer = (MetalGpuBuffer)this.indexBuffer;
        MTLRenderCommandEncoder enc = this.renderEncoder();
        this.bindDrawState(enc);
        this.drawIndexedNative(enc, nativeIndexBuffer, firstIndex, indexCount, vertexOffset, instanceCount, this.indexType, firstInstance);
    }

    public void multiDrawIndexed(@NonNull IntBuffer drawParameters, int instanceCount, int firstInstance, int drawCount) {
        MTLPrimitiveType primitiveType = this.primitiveTopology();
        MetalGpuBuffer nativeIndexBuffer = (MetalGpuBuffer)this.indexBuffer;
        MTLRenderCommandEncoder enc = this.renderEncoder();
        this.bindDrawState(enc);
        if (primitiveType == MTLPrimitiveType.TriangleFan) {
            for (int i = 0; i < drawCount; ++i) {
                int firstIndex = drawParameters.get(i * 3);
                int indexCount = drawParameters.get(i * 3 + 1);
                int baseVertex = drawParameters.get(i * 3 + 2);
                if (indexCount <= 0) continue;
                this.drawIndexedNative(enc, nativeIndexBuffer, firstIndex, indexCount, baseVertex, instanceCount, this.indexType, firstInstance);
            }
            return;
        }
        MetalNativeBridge.MTLRenderCommandEncoder_multiDrawIndexedFull(enc.handle(), primitiveType.value, this.indexType.value, nativeIndexBuffer.nativeHandle(), MemorySegment.ofAddress((long)MemoryUtil.memAddress((IntBuffer)drawParameters)), drawCount, instanceCount, firstInstance);
        Stats.recordBatchedMultiDraw();
    }

    public void multiDrawIndexed(@NonNull PointerBuffer firstIndexOffsets, @NonNull IntBuffer indexCounts, @NonNull IntBuffer vertexOffsets, int drawCount) {
        MTLPrimitiveType primitiveType = this.primitiveTopology();
        if (primitiveType == MTLPrimitiveType.TriangleFan) {
            throw new UnsupportedOperationException("Metal backend does not support triangle fan multiDrawIndexed");
        }
        MetalGpuBuffer nativeIndexBuffer = (MetalGpuBuffer)this.indexBuffer;
        MTLRenderCommandEncoder enc = this.renderEncoder();
        this.bindDrawState(enc);
        MetalNativeBridge.MTLRenderCommandEncoder_multiDrawIndexed(enc.handle(), primitiveType.value, this.indexType.value, nativeIndexBuffer.nativeHandle(), MemorySegment.ofAddress((long)MemoryUtil.memAddress((CustomBuffer)firstIndexOffsets)), MemorySegment.ofAddress((long)MemoryUtil.memAddress((IntBuffer)indexCounts)), MemorySegment.ofAddress((long)MemoryUtil.memAddress((IntBuffer)vertexOffsets)), drawCount, 1L, 0L);
    }

    public void drawIndexedIndirect(@NonNull GpuBufferSlice commands, int drawCount) {
        if (drawCount <= 0) {
            return;
        }
        MTLPrimitiveType primitiveType = this.primitiveTopology();
        if (primitiveType == MTLPrimitiveType.TriangleFan) {
            throw new UnsupportedOperationException("Metal backend does not support triangle fan indirect draws");
        }
        if (this.indexBuffer == null) {
            Metallum.LOGGER.warn("[metallum] drawIndexedIndirect called with null index buffer, skipping draw");
            return;
        }
        if (commands.buffer().isClosed()) {
            Metallum.LOGGER.warn("[metallum] drawIndexedIndirect called with closed indirect command buffer, skipping draw");
            return;
        }
        long needed = (long)drawCount * (long)VkDrawIndexedIndirectCommand.SIZEOF;
        if (commands.length() < needed) {
            Metallum.LOGGER.warn("[metallum] drawIndexedIndirect command buffer too small: need {} bytes, have {} (drawCount={})", new Object[]{needed, commands.length(), drawCount});
            return;
        }
        MetalGpuBuffer nativeIndexBuffer = (MetalGpuBuffer)this.indexBuffer;
        MTLRenderCommandEncoder enc = this.renderEncoder();
        this.bindDrawState(enc);
        enc.drawIndexedPrimitivesIndirect(primitiveType, this.indexType, nativeIndexBuffer.nativeHandle(), ((MetalGpuBuffer)commands.buffer()).nativeHandle(), commands.offset(), drawCount, VkDrawIndexedIndirectCommand.SIZEOF);
    }

    public <T> void drawMultipleIndexed(Collection<RenderPass.Draw<T>> draws, @Nullable GpuBuffer defaultIndexBuffer, @Nullable IndexType defaultIndexType, @NonNull Collection<String> dynamicUniforms, @NonNull T uniformArgument) {
        IndexType fallbackIndexType = defaultIndexType == null ? IndexType.SHORT : defaultIndexType;
        MTLRenderCommandEncoder enc = this.renderEncoder();
        for (RenderPass.Draw<T> draw : draws) {
            MTLIndexType drawIndexType = MTLIndexType.from(draw.indexType() == null ? fallbackIndexType : draw.indexType());
            GpuBuffer currentIndexBuffer = draw.indexBuffer() == null ? defaultIndexBuffer : draw.indexBuffer();
            this.setIndexBuffer(currentIndexBuffer, drawIndexType);
            this.setVertexBuffer(draw.slot(), draw.vertexBuffer().slice());
            if (draw.uniformUploaderConsumer() != null) {
                draw.uniformUploaderConsumer().accept(uniformArgument, this::setUniform);
            }
            if (this.scissorDirty || this.vertexBuffersDirty || this.dirtyDescriptorMask != 0L || this.pipelineDirty) {
                this.bindDrawState(enc);
            }
            MetalGpuBuffer nativeIndexBuffer = (MetalGpuBuffer)this.indexBuffer;
            this.drawIndexedNative(enc, nativeIndexBuffer, draw.firstIndex(), draw.indexCount(), draw.baseVertex(), 1, drawIndexType, 0);
        }
    }

    public void draw(int vertexCount, int instanceCount, int firstVertex, int firstInstance) {
        MTLPrimitiveType primitiveType = this.primitiveTopology();
        MTLRenderCommandEncoder enc = this.renderEncoder();
        this.bindDrawState(enc);
        if (primitiveType == MTLPrimitiveType.TriangleFan) {
            this.drawTriangleFan(enc, firstVertex, vertexCount, instanceCount, firstInstance);
        } else {
            enc.drawPrimitives(primitiveType, firstVertex, vertexCount, Math.max(1, instanceCount), firstInstance);
        }
    }

    public void multiDraw(@NonNull IntBuffer drawParameters, int instanceCount, int firstInstance, int drawCount) {
        throw new UnsupportedOperationException();
    }

    public void multiDraw(@NonNull IntBuffer firstVertices, @NonNull IntBuffer vertexCounts, int drawCount) {
        throw new UnsupportedOperationException();
    }

    public void drawIndirect(@NonNull GpuBufferSlice commands, int drawCount) {
        MTLPrimitiveType primitiveType = this.primitiveTopology();
        if (primitiveType == MTLPrimitiveType.TriangleFan) {
            throw new UnsupportedOperationException("Metal backend does not support triangle fan indirect draws");
        }
        MTLRenderCommandEncoder enc = this.renderEncoder();
        this.bindDrawState(enc);
        enc.drawPrimitivesIndirect(primitiveType, ((MetalGpuBuffer)commands.buffer()).nativeHandle(), commands.offset(), drawCount, VkDrawIndirectCommand.SIZEOF);
    }

    public void writeTimestamp(@NonNull GpuQueryPool pool, int index) {
        if (pool instanceof MetalGpuQueryPool) {
            MetalGpuQueryPool metalPool = (MetalGpuQueryPool)pool;
            if (index >= 0 && index < pool.size()) {
                metalPool.setValue(index, this.device.getTimestampNow());
            }
        }
    }

    MTLPixelFormat colorAttachmentFormat() {
        return ((MetalGpuTexture)this.colorTexture.texture()).mtlPixelFormat();
    }

    MTLPixelFormat depthAttachmentFormat() {
        if (this.depthTexture == null) {
            return MTLPixelFormat.Invalid;
        }
        return ((MetalGpuTexture)this.depthTexture.texture()).mtlPixelFormat();
    }

    MTLPixelFormat stencilAttachmentFormat() {
        if (this.depthTexture == null) {
            return MTLPixelFormat.Invalid;
        }
        return ((MetalGpuTexture)this.depthTexture.texture()).mtlStencilPixelFormat();
    }

    void materializePendingClear() {
        if (this.clearColor != null || this.clearDepthEnabled) {
            this.renderEncoder();
        }
    }

    private MTLRenderCommandEncoder renderEncoder() {
        MetalGpuTextureView colorTextureView = (MetalGpuTextureView)this.colorTexture;
        MetalGpuTextureView depthTextureView = this.depthTexture == null ? null : (MetalGpuTextureView)this.depthTexture;
        boolean clearColorNow = this.clearColor != null;
        boolean clearDepthNow = this.clearDepthEnabled;
        MTLRenderCommandEncoder encoder = this.commandEncoder.renderCommandEncoder(colorTextureView, depthTextureView, this.colorTexture.getWidth(0), this.colorTexture.getHeight(0), clearColorNow, clearColorNow ? this.clearColor.x() : 0.0f, clearColorNow ? this.clearColor.y() : 0.0f, clearColorNow ? this.clearColor.z() : 0.0f, clearColorNow ? this.clearColor.w() : 0.0f, clearDepthNow, this.clearDepthValue);
        this.clearColor = null;
        this.clearDepthEnabled = false;
        return encoder;
    }

    GpuBufferSlice.MappedView allocateTransient(long size, long alignment, @GpuBuffer.Usage int usage) {
        return this.commandEncoder.transientMemory().allocateGpuMapped(size, alignment, usage);
    }

    private void pushVertexBuffers(MTLRenderCommandEncoder enc) {
        int firstSlot = this.compiledPipeline.firstAvailableVertexBufferSlot();
        int count = this.compiledPipeline.vertexBufferCount();
        for (int slot = 0; slot < count; ++slot) {
            GpuBufferSlice vertexBuffer = this.vertexBuffers[slot];
            if (vertexBuffer == null) continue;
            if (VALIDATION && vertexBuffer.buffer().isClosed()) {
                throw new IllegalStateException("Vertex buffer at slot " + slot + " has been closed");
            }
            MetalGpuBuffer nativeVertexBuffer = (MetalGpuBuffer)vertexBuffer.buffer();
            int metalSlot = firstSlot + slot;
            enc.setBuffer(nativeVertexBuffer.nativeHandle(), vertexBuffer.offset(), metalSlot, 1);
        }
    }

    private void drawTriangleFan(MTLRenderCommandEncoder encoder, int firstVertex, int vertexCount, int instanceCount, int baseInstance) {
        int triangleCount = vertexCount - 2;
        int indexCount = triangleCount * 3;
        MTLIndexType fanIndexType = vertexCount - 1 <= 65535 ? MTLIndexType.UInt16 : MTLIndexType.UInt32;
        try (GpuBufferSlice.MappedView mapped = this.commandEncoder.transientMemory().allocateGpuMapped((long)indexCount * (long)fanIndexType.bytes, (long)fanIndexType.bytes, 64);){
            if (fanIndexType == MTLIndexType.UInt16) {
                indices = mapped.data().asShortBuffer();
                for (int i = 0; i < triangleCount; ++i) {
                    ((ShortBuffer)indices).put((short)0);
                    ((ShortBuffer)indices).put((short)(i + 1));
                    ((ShortBuffer)indices).put((short)(i + 2));
                }
            } else {
                indices = mapped.data().asIntBuffer();
                for (int i = 0; i < triangleCount; ++i) {
                    ((IntBuffer)indices).put(0);
                    ((IntBuffer)indices).put(i + 1);
                    ((IntBuffer)indices).put(i + 2);
                }
            }
            GpuBufferSlice slice = mapped.slice();
            encoder.drawIndexedPrimitives(MTLPrimitiveType.Triangle, indexCount, fanIndexType, ((MetalGpuBuffer)slice.buffer()).nativeHandle(), slice.offset(), Math.max(1, instanceCount), firstVertex, baseInstance);
        }
    }

    private void drawIndexedNative(MTLRenderCommandEncoder enc, MetalGpuBuffer nativeIndexBuffer, int firstIndex, int indexCount, int baseVertex, int instanceCount, MTLIndexType indexType, int baseInstance) {
        Stats.recordIndexedDraw();
        MTLPrimitiveType primitiveType = this.primitiveTopology();
        long indexOffsetBytes = (long)firstIndex * (long)indexType.bytes;
        if (primitiveType == MTLPrimitiveType.TriangleFan) {
            long fanSize = Math.multiplyExact((long)Math.multiplyExact((long)indexCount - 2L, 3L), (int)4);
            try (GpuBufferSlice.MappedView mapped = this.commandEncoder.transientMemory().allocateGpuMapped(fanSize, 4L, 64);){
                GpuBufferSlice slice = mapped.slice();
                enc.drawIndexedPrimitivesTriangleFan(nativeIndexBuffer.nativeHandle(), ((MetalGpuBuffer)slice.buffer()).nativeHandle(), slice.offset(), indexType.value, indexOffsetBytes, indexCount, baseVertex, instanceCount, baseInstance);
            }
        } else {
            enc.drawIndexedPrimitives(primitiveType, indexCount, indexType, nativeIndexBuffer.nativeHandle(), indexOffsetBytes, instanceCount, baseVertex, baseInstance);
        }
    }

    private void bindDrawState(MTLRenderCommandEncoder enc) {
        if (this.compiledPipeline == null) {
            throw new IllegalStateException("Pipeline is missing");
        }
        if (this.pipelineDirty) {
            boolean useDepth = this.depthAttachmentFormat().value != MTLPixelFormat.Invalid.value;
            MemorySegment pipelineHandle = this.compiledPipeline.getNativePipeline(useDepth);
            if (MetalNativeBridge.isNullHandle(pipelineHandle)) {
                throw new IllegalStateException("Native pipeline is unavailable");
            }
            enc.setRenderPipelineState(pipelineHandle);
            this.pipelineDirty = false;
            if (useDepth) {
                MemorySegment depthState = this.compiledPipeline.getDepthStencilState();
                if (MetalNativeBridge.isNullHandle(depthState)) {
                    throw new IllegalStateException("Native depth state is unavailable");
                }
                enc.setDepthStencilState(depthState);
                enc.setDepthBias(this.compiledPipeline.depthBiasConstant(), this.compiledPipeline.depthBiasScaleFactor(), 0.0f);
            }
            enc.setFrontFacingWinding(MTLWinding.Clockwise);
            enc.setCullMode(this.compiledPipeline.cullMode());
            enc.setTriangleFillMode(this.compiledPipeline.fillMode());
            this.dirtyDescriptorMask |= this.compiledPipeline.allResourceMask();
        }
        if (this.scissorDirty) {
            this.pushEffectiveScissor(enc);
            this.scissorDirty = false;
        }
        if (this.vertexBuffersDirty) {
            this.pushVertexBuffers(enc);
            this.vertexBuffersDirty = false;
        }
        if (this.dirtyDescriptorMask != 0L) {
            for (MetalCompiledRenderPipeline.ResourceBinding binding : this.compiledPipeline.resources()) {
                if ((this.dirtyDescriptorMask & 1L << binding.bindingIndex()) == 0L) continue;
                this.pushDescriptor(enc, binding);
            }
        }
        this.dirtyDescriptorMask = 0L;
    }

    private MTLPrimitiveType primitiveTopology() {
        if (this.compiledPipeline == null) {
            throw new IllegalStateException("Pipeline is missing");
        }
        return this.compiledPipeline.topology();
    }

    private void pushEffectiveScissor(MTLRenderCommandEncoder enc) {
        int areaLeft = this.renderArea.x();
        int areaTop = this.renderArea.y();
        if (!this.scissorState.enabled()) {
            if (this.renderArea.fillsTexture(this.colorTexture)) {
                enc.setScissorRect(0L, 0L, this.colorTexture.getWidth(0), this.colorTexture.getHeight(0));
                return;
            }
            enc.setScissorRect(areaLeft, areaTop, this.renderArea.width(), this.renderArea.height());
            return;
        }
        int areaRight = areaLeft + this.renderArea.width();
        int areaBottom = areaTop + this.renderArea.height();
        int left = Math.max(areaLeft, this.scissorState.x());
        int top = Math.max(areaTop, this.scissorState.y());
        int right = Math.min(areaRight, this.scissorState.x() + this.scissorState.width());
        int bottom = Math.min(areaBottom, this.scissorState.y() + this.scissorState.height());
        if (right <= left || bottom <= top) {
            enc.setScissorRect(0L, 0L, 0L, 0L);
        } else {
            enc.setScissorRect(left, top, right - left, bottom - top);
        }
    }

    private void markDescriptorDirty(String name) {
        MetalCompiledRenderPipeline.ResourceBinding binding;
        if (this.compiledPipeline != null && (binding = this.compiledPipeline.resource(name)) != null) {
            this.dirtyDescriptorMask |= 1L << binding.bindingIndex();
        }
    }

    private void pushDescriptor(MTLRenderCommandEncoder enc, MetalCompiledRenderPipeline.ResourceBinding binding) {
        if (binding.kind() == MetalCompiledRenderPipeline.ResourceKind.SAMPLED_IMAGE) {
            TextureViewAndSampler textureBinding = this.samplers.get(binding.name());
            if (textureBinding == null) {
                throw new IllegalStateException("Missing sampler " + binding.name());
            }
            if (VALIDATION && textureBinding.textureView().isClosed()) {
                throw new IllegalStateException("Sampler " + binding.name() + " texture view has been closed");
            }
            MetalGpuTextureView textureView = (MetalGpuTextureView)textureBinding.textureView();
            MetalGpuSampler sampler = (MetalGpuSampler)textureBinding.sampler();
            enc.setTextureAndSampler(textureView.nativeHandle(), sampler.nativeHandle(), binding.bindingIndex(), binding.stageMask());
            return;
        }
        if (binding.kind() == MetalCompiledRenderPipeline.ResourceKind.TEXEL_BUFFER) {
            this.pushTexelBufferDescriptor(enc, binding);
            return;
        }
        GpuBufferSlice uniformSlice = this.uniforms.get(binding.name());
        if (uniformSlice == null) {
            throw new IllegalStateException("Missing uniform " + binding.name());
        }
        if (VALIDATION && uniformSlice.buffer().isClosed()) {
            throw new IllegalStateException("Uniform " + binding.name() + " buffer has been closed");
        }
        MetalGpuBuffer uniformBuffer = (MetalGpuBuffer)uniformSlice.buffer();
        enc.setBuffer(uniformBuffer.nativeHandle(), uniformSlice.offset(), binding.bindingIndex(), binding.stageMask());
    }

    private void pushTexelBufferDescriptor(MTLRenderCommandEncoder enc, MetalCompiledRenderPipeline.ResourceBinding binding) {
        GpuBufferSlice texelSlice = this.uniforms.get(binding.name());
        if (texelSlice == null) {
            throw new IllegalStateException("Missing texel buffer " + binding.name());
        }
        if (VALIDATION && texelSlice.buffer().isClosed()) {
            throw new IllegalStateException("Texel buffer " + binding.name() + " has been closed");
        }
        GpuFormat texelFormat = binding.texelBufferFormat();
        if (texelFormat == null) {
            throw new IllegalStateException("Texel buffer " + binding.name() + " is missing a format");
        }
        MetalGpuBuffer texelBuffer = (MetalGpuBuffer)texelSlice.buffer();
        long pixelFormat = MTLPixelFormat.from((GpuFormat)texelFormat).value;
        int pixelSize = texelFormat.blockSize();
        long texelByteLength = texelSlice.length();
        if (texelByteLength <= 0L || texelByteLength % (long)pixelSize != 0L) {
            throw new IllegalStateException("Texel buffer " + binding.name() + " length " + texelByteLength + " is not a valid " + String.valueOf(texelFormat) + " range");
        }
        long texelCount = texelByteLength / (long)pixelSize;
        MemorySegment texelTexture = this.device.getOrCreateTexelView(texelBuffer, pixelFormat, texelSlice.offset(), texelCount, 1L, texelByteLength);
        if (MetalNativeBridge.isNullHandle(texelTexture)) {
            throw new IllegalStateException("Failed to create Metal texel buffer texture for " + binding.name());
        }
        enc.setTexture(texelTexture, binding.bindingIndex(), binding.stageMask());
    }

    private static boolean sameSlice(@Nullable GpuBufferSlice left, @Nullable GpuBufferSlice right) {
        if (left == null || right == null) {
            return left == right;
        }
        return left.buffer() == right.buffer() && left.offset() == right.offset() && left.length() == right.length();
    }

    record TextureViewAndSampler(GpuTextureView textureView, GpuSampler sampler) {
    }
}

