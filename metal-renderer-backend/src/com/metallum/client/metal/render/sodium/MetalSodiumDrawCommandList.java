/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.DiagLog
 *  com.metallum.client.metal.render.Diagnostics
 *  com.metallum.client.metal.render.sodium.MetalSodiumActiveState
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline$ResourceBinding
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline$ResourceKind
 *  com.metallum.client.metal.render.sodium.MetalSodiumDrawCommandList
 *  com.metallum.client.metal.render.sodium.MetalSodiumDrawCommandList$1
 *  com.metallum.client.metal.render.sodium.MetalSodiumDrawCommandList$DrawCommand
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface
 *  com.metallum.client.metal.render.sodium.MetalSodiumTessellation
 *  com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers$RegionUniformSlices
 *  com.mojang.blaze3d.textures.GpuTextureView
 *  fzf
 *  java.lang.MatchException
 *  java.lang.foreign.MemorySegment
 *  net.caffeinemc.mods.sodium.client.gl.device.DrawCommandList
 *  net.caffeinemc.mods.sodium.client.gl.device.MultiDrawBatch
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.GlIndexType
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.GlPrimitiveType
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.lwjgl.system.MemoryUtil
 *  org.lwjgl.system.Pointer
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.Metallum;
import com.metallum.client.metal.render.DiagLog;
import com.metallum.client.metal.render.Diagnostics;
import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.MetalGpuSampler;
import com.metallum.client.metal.render.MetalGpuTextureView;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLIndexType;
import com.metallum.client.metal.render.mtl.MTLPixelFormat;
import com.metallum.client.metal.render.mtl.MTLPrimitiveType;
import com.metallum.client.metal.render.mtl.MTLRenderCommandEncoder;
import com.metallum.client.metal.render.mtl.MTLWinding;
import com.metallum.client.metal.render.sodium.MetalSodiumActiveState;
import com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline;
import com.metallum.client.metal.render.sodium.MetalSodiumDrawCommandList;
import com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface;
import com.metallum.client.metal.render.sodium.MetalSodiumTessellation;
import com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers;
import com.mojang.blaze3d.textures.GpuTextureView;
import java.lang.foreign.MemorySegment;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;
import net.caffeinemc.mods.sodium.client.gl.device.DrawCommandList;
import net.caffeinemc.mods.sodium.client.gl.device.MultiDrawBatch;
import net.caffeinemc.mods.sodium.client.gl.tessellation.GlIndexType;
import net.caffeinemc.mods.sodium.client.gl.tessellation.GlPrimitiveType;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.Pointer;

/*
 * Exception performing whole class analysis ignored.
 */
@Environment(value=EnvType.CLIENT)
public final class MetalSodiumDrawCommandList
implements DrawCommandList {
    private static final int STAGE_VERTEX = 1;
    private static final AtomicBoolean ChunkDataMissingWarned = new AtomicBoolean(false);
    private static final int UNIFORM_CACHE_SLOTS = 32;
    private static long cacheEpoch = Long.MIN_VALUE;
    private static MemorySegment cachePipeline;
    private static final MemorySegment[] cacheUniformHandle;
    private static final long[] cacheUniformOffset;
    private static final MemorySegment[] cacheTexHandle;
    private static final MemorySegment[] cacheSamplerHandle;
    private final MetalCommandEncoder encoder;
    private final MetalSodiumTessellation tessellation;
    private final MetalSodiumActiveState state;
    private final MetalSodiumUniformBuffers.RegionUniformSlices regionUniforms;
    private boolean closed;
    private long sodiumDrawCount;

    private static boolean stateCacheValid(MemorySegment pipelineHandle) {
        return MetalCommandEncoder.encoderEpoch() == cacheEpoch && pipelineHandle == cachePipeline;
    }

    private static void stateCacheReset(MemorySegment pipelineHandle) {
        cacheEpoch = MetalCommandEncoder.encoderEpoch();
        cachePipeline = pipelineHandle;
        Arrays.fill(cacheUniformHandle, null);
        Arrays.fill(cacheUniformOffset, 0L);
        Arrays.fill(cacheTexHandle, null);
        Arrays.fill(cacheSamplerHandle, null);
    }

    public MetalSodiumDrawCommandList(MetalCommandEncoder encoder, MetalSodiumTessellation tessellation, MetalSodiumActiveState state, MetalSodiumUniformBuffers.RegionUniformSlices regionUniforms) {
        this.encoder = encoder;
        this.tessellation = tessellation;
        this.state = state;
        this.regionUniforms = regionUniforms;
    }

    public static DrawCommand readBatchEntry(MultiDrawBatch batch, int index) {
        int elementCount = MemoryUtil.memGetInt((long)(batch.pElementCount + (long)index * 4L));
        int baseVertex = MemoryUtil.memGetInt((long)(batch.pBaseVertex + (long)index * 4L));
        long indexOffsetBytes = MemoryUtil.memGetAddress((long)(batch.pElementPointer + ((long)index << Pointer.POINTER_SHIFT)));
        return new DrawCommand(elementCount, baseVertex, indexOffsetBytes);
    }

    public void multiDrawElementsBaseVertex(MultiDrawBatch batch, GlIndexType indexType) {
        if (this.closed) {
            throw new IllegalStateException("DrawCommandList already closed");
        }
        MTLRenderCommandEncoder enc = this.encoder.ensureActiveRenderEncoder();
        if (enc == null) {
            throw new IllegalStateException("Sodium draw outside of active Metal render pass (ensureActiveRenderEncoder() == null)");
        }
        if (this.tessellation.indexBuffer() == null) {
            throw new IllegalStateException("Sodium tessellation missing index buffer");
        }
        this.applyPipelineState(enc);
        this.applyVertexBuffer(enc);
        this.applyResources(enc);
        MetalGpuBuffer indexBuffer = this.tessellation.indexBuffer();
        MTLPrimitiveType primitiveType = MetalSodiumDrawCommandList.toMetalPrimitive((GlPrimitiveType)this.tessellation.getPrimitiveType());
        MTLIndexType metalIndexType = MetalSodiumDrawCommandList.toMetalIndex((GlIndexType)indexType);
        this.sodiumDrawCount += (long)batch.size;
        if (Diagnostics.shouldRun((String)"sodium-draw", (long)5000L)) {
            StringBuilder sb = new StringBuilder("[diag] sodium draws(last5s)=").append(this.sodiumDrawCount).append(" batch=").append(batch.size);
            if (batch.size > 0) {
                DrawCommand first = MetalSodiumDrawCommandList.readBatchEntry((MultiDrawBatch)batch, (int)0);
                sb.append(" first=").append(first.elementCount()).append('/').append(first.baseVertex()).append('/').append(first.indexOffsetBytes());
                long minIo = Long.MAX_VALUE;
                long maxIo = -1L;
                int minBv = Integer.MAX_VALUE;
                int maxBv = Integer.MIN_VALUE;
                int minE = Integer.MAX_VALUE;
                int maxE = -1;
                int nonZeroIo = 0;
                int dupIoPairs = 0;
                long prevIo = -1L;
                for (int i = 0; i < batch.size; ++i) {
                    DrawCommand c = MetalSodiumDrawCommandList.readBatchEntry((MultiDrawBatch)batch, (int)i);
                    minIo = Math.min(minIo, c.indexOffsetBytes());
                    maxIo = Math.max(maxIo, c.indexOffsetBytes());
                    minBv = Math.min(minBv, c.baseVertex());
                    maxBv = Math.max(maxBv, c.baseVertex());
                    minE = Math.min(minE, c.elementCount());
                    maxE = Math.max(maxE, c.elementCount());
                    if (c.indexOffsetBytes() != 0L) {
                        ++nonZeroIo;
                        if (c.indexOffsetBytes() == prevIo) {
                            ++dupIoPairs;
                        }
                    }
                    prevIo = c.indexOffsetBytes();
                }
                sb.append(" ioR=[").append(minIo).append(',').append(maxIo).append("] bvR=[").append(minBv).append(',').append(maxBv).append("] eR=[").append(minE).append(',').append(maxE).append(" ioNz=").append(nonZeroIo).append(" dupIo=").append(dupIoPairs);
            } else {
                sb.append(" (empty)");
            }
            DiagLog.log((String)"%s", (Object[])new Object[]{sb});
            this.sodiumDrawCount = 0L;
        }
        for (int i = 0; i < batch.size; ++i) {
            int elementCount = MemoryUtil.memGetInt((long)(batch.pElementCount + (long)i * 4L));
            int baseVertex = MemoryUtil.memGetInt((long)(batch.pBaseVertex + (long)i * 4L));
            long indexOffsetBytes = MemoryUtil.memGetAddress((long)(batch.pElementPointer + ((long)i << Pointer.POINTER_SHIFT)));
            enc.drawIndexedPrimitives(primitiveType, elementCount, metalIndexType, indexBuffer.nativeHandle(), indexOffsetBytes, 1, baseVertex, 0);
        }
    }

    private void applyPipelineState(MTLRenderCommandEncoder enc) {
        MTLPixelFormat colorFormat;
        boolean useDepth;
        MetalSodiumCompiledPipeline pipeline = this.state.pipeline();
        MemorySegment pipelineHandle = pipeline.getNativePipeline(useDepth = this.encoder.activeHasDepth(), colorFormat = this.encoder.activeColorFormat());
        if (MetalNativeBridge.isNullHandle(pipelineHandle)) {
            throw new IllegalStateException("Sodium native pipeline unavailable (useDepth=" + useDepth + ", color=" + String.valueOf((Object)colorFormat) + ")");
        }
        if (MetalSodiumDrawCommandList.stateCacheValid((MemorySegment)pipelineHandle)) {
            return;
        }
        MetalSodiumDrawCommandList.stateCacheReset((MemorySegment)pipelineHandle);
        enc.setRenderPipelineState(pipelineHandle);
        if (useDepth) {
            MemorySegment depthState = pipeline.getDepthStencilState();
            if (MetalNativeBridge.isNullHandle(depthState)) {
                throw new IllegalStateException("Sodium native depth state unavailable");
            }
            enc.setDepthStencilState(depthState);
            enc.setDepthBias(pipeline.depthBiasConstant(), pipeline.depthBiasScaleFactor(), 0.0f);
        }
        enc.setFrontFacingWinding(MTLWinding.Clockwise);
        enc.setCullMode(pipeline.cullMode());
        enc.setTriangleFillMode(pipeline.fillMode());
    }

    private void applyVertexBuffer(MTLRenderCommandEncoder enc) {
        MetalGpuBuffer vertexBuffer = this.tessellation.vertexBuffer();
        enc.setBuffer(vertexBuffer.nativeHandle(), 0L, this.state.pipeline().firstAvailableVertexBufferSlot(), 1);
    }

    private void applyResources(MTLRenderCommandEncoder enc) {
        MetalSodiumActiveState state = this.state;
        MemorySegment pipelineHandle = state.pipeline().getNativePipeline(this.encoder.activeHasDepth(), this.encoder.activeColorFormat());
        if (!MetalSodiumDrawCommandList.stateCacheValid((MemorySegment)pipelineHandle)) {
            MetalSodiumDrawCommandList.stateCacheReset((MemorySegment)pipelineHandle);
        }
        int uniformSlot = 0;
        for (MetalSodiumCompiledPipeline.ResourceBinding binding : state.pipeline().resources()) {
            if (binding.kind() == MetalSodiumCompiledPipeline.ResourceKind.UNIFORM_BUFFER) {
                MetalGpuBuffer buffer;
                long bufferOffset = 0L;
                if ("u_RegionOffset".equals(binding.name())) {
                    buffer = (MetalGpuBuffer)this.regionUniforms.regionOffset().buffer();
                    bufferOffset = this.regionUniforms.regionOffset().offset();
                } else if ("u_CurrentTime".equals(binding.name())) {
                    buffer = (MetalGpuBuffer)this.regionUniforms.currentTime().buffer();
                    bufferOffset = this.regionUniforms.currentTime().offset();
                } else {
                    buffer = state.uniformBuffers().forBinding(binding.name());
                    if (buffer == null && "ChunkData".equals(binding.name()) && (buffer = state.shaderInterface().chunkDataBuffer()) != null && buffer.isCpuAccessible() && Diagnostics.shouldRun((String)"sodium-chunkdata", (long)5000L)) {
                        ByteBuffer data = buffer.currentStorage();
                        int ints = data.remaining() / 4;
                        int countNegOne = 0;
                        int countZero = 0;
                        int countPositive = 0;
                        for (int k = 0; k < ints; ++k) {
                            int v = data.getInt(k * 4);
                            if (v == -1) {
                                ++countNegOne;
                                continue;
                            }
                            if (v == 0) {
                                ++countZero;
                                continue;
                            }
                            ++countPositive;
                        }
                        DiagLog.log((String)"[diag] sodium chunkFades total=%d negOne=%d zero=%d positive=%d first=%d,%d,%d,%d", (Object[])new Object[]{ints, countNegOne, countZero, countPositive, ints > 0 ? data.getInt(0) : 0, ints > 1 ? data.getInt(4) : 0, ints > 2 ? data.getInt(8) : 0, ints > 3 ? data.getInt(12) : 0});
                    }
                }
                if (buffer == null) {
                    if (!ChunkDataMissingWarned.compareAndSet(false, true)) continue;
                    Metallum.LOGGER.error("[metallum][sodium] ChunkData uniform buffer missing, skipping binding");
                    continue;
                }
                MemorySegment handle = buffer.nativeHandle();
                if (uniformSlot < 32 && handle == cacheUniformHandle[uniformSlot] && bufferOffset == cacheUniformOffset[uniformSlot]) {
                    ++uniformSlot;
                    continue;
                }
                enc.setBuffer(handle, bufferOffset, binding.bindingIndex(), binding.stageMask());
                if (uniformSlot >= 32) continue;
                MetalSodiumDrawCommandList.cacheUniformHandle[uniformSlot] = handle;
                MetalSodiumDrawCommandList.cacheUniformOffset[uniformSlot] = bufferOffset;
                ++uniformSlot;
                continue;
            }
            if (binding.kind() != MetalSodiumCompiledPipeline.ResourceKind.SAMPLED_IMAGE) continue;
            this.applyTextureBinding(enc, binding);
        }
    }

    private void applyTextureBinding(MTLRenderCommandEncoder enc, MetalSodiumCompiledPipeline.ResourceBinding binding) {
        MetalGpuTextureView metalTexture;
        fzf sampler;
        block21: {
            block20: {
                MetalSodiumShaderInterface shaderInterface = this.state.shaderInterface();
                GpuTextureView textureView = switch (binding.name()) {
                    case "u_BlockTex" -> shaderInterface.blockTex();
                    case "u_LightTex" -> shaderInterface.lightTex();
                    default -> null;
                };
                switch (binding.name()) {
                    case "u_BlockTex": {
                        fzf fzf2 = shaderInterface.terrainSampler();
                        break;
                    }
                    case "u_LightTex": {
                        fzf fzf2 = shaderInterface.lightSampler();
                        break;
                    }
                    default: {
                        fzf fzf2 = sampler = null;
                    }
                }
                if (!(textureView instanceof MetalGpuTextureView)) break block20;
                metalTexture = (MetalGpuTextureView)textureView;
                if (sampler instanceof MetalGpuSampler) break block21;
            }
            throw new IllegalStateException("Sodium texture/sampler for " + binding.name() + " not Metal-backed or missing");
        }
        MetalGpuSampler metalSampler = (MetalGpuSampler)sampler;
        int texSlot = "u_BlockTex".equals(binding.name()) ? 0 : 1;
        MemorySegment texHandle = metalTexture.nativeHandle();
        MemorySegment samplerHandle = metalSampler.nativeHandle();
        if (texHandle == cacheTexHandle[texSlot] && samplerHandle == cacheSamplerHandle[texSlot]) {
            return;
        }
        MetalSodiumDrawCommandList.cacheTexHandle[texSlot] = texHandle;
        MetalSodiumDrawCommandList.cacheSamplerHandle[texSlot] = samplerHandle;
        enc.setTextureAndSampler(texHandle, samplerHandle, binding.bindingIndex(), binding.stageMask());
    }

    private static MTLPrimitiveType toMetalPrimitive(GlPrimitiveType type) {
        switch (1.$SwitchMap$net$caffeinemc$mods$sodium$client$gl$tessellation$GlPrimitiveType[type.ordinal()]) {
            case 1: {
                break;
            }
            default: {
                throw new IllegalStateException("Unsupported Sodium primitive type: " + String.valueOf(type));
            }
        }
        return MTLPrimitiveType.Triangle;
    }

    private static MTLIndexType toMetalIndex(GlIndexType type) {
        return switch (1.$SwitchMap$net$caffeinemc$mods$sodium$client$gl$tessellation$GlIndexType[type.ordinal()]) {
            default -> throw new MatchException(null, null);
            case 1 -> MTLIndexType.UInt32;
            case 2 -> MTLIndexType.UInt16;
            case 3 -> throw new IllegalStateException("Unsupported Sodium index type: UNSIGNED_BYTE");
        };
    }

    public void endTessellating() {
    }

    public void flush() {
    }

    public void close() {
        this.closed = true;
    }

    static {
        cacheUniformHandle = new MemorySegment[32];
        cacheUniformOffset = new long[32];
        cacheTexHandle = new MemorySegment[2];
        cacheSamplerHandle = new MemorySegment[2];
    }
}

