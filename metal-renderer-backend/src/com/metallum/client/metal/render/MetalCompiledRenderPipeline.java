/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.GpuFormat
 *  com.mojang.blaze3d.pipeline.BlendFunction
 *  com.mojang.blaze3d.pipeline.ColorTargetState
 *  com.mojang.blaze3d.pipeline.CompiledRenderPipeline
 *  com.mojang.blaze3d.pipeline.DepthStencilState
 *  com.mojang.blaze3d.pipeline.RenderPipeline
 *  com.mojang.blaze3d.platform.PolygonMode
 *  com.mojang.blaze3d.vertex.VertexFormat
 *  com.mojang.blaze3d.vertex.VertexFormatElement
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLBlendFactor;
import com.metallum.client.metal.render.mtl.MTLBlendOperation;
import com.metallum.client.metal.render.mtl.MTLColorWriteMask;
import com.metallum.client.metal.render.mtl.MTLCompareFunction;
import com.metallum.client.metal.render.mtl.MTLCullMode;
import com.metallum.client.metal.render.mtl.MTLPixelFormat;
import com.metallum.client.metal.render.mtl.MTLPrimitiveType;
import com.metallum.client.metal.render.mtl.MTLRenderPipelineDescriptor;
import com.metallum.client.metal.render.mtl.MTLTriangleFillMode;
import com.metallum.client.metal.render.mtl.MTLVertexDescriptor;
import com.metallum.client.metal.render.mtl.MTLVertexFormat;
import com.metallum.client.metal.render.mtl.MTLVertexStepFunction;
import com.mojang.blaze3d.GpuFormat;
import com.mojang.blaze3d.pipeline.BlendFunction;
import com.mojang.blaze3d.pipeline.ColorTargetState;
import com.mojang.blaze3d.pipeline.CompiledRenderPipeline;
import com.mojang.blaze3d.pipeline.DepthStencilState;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.platform.PolygonMode;
import com.mojang.blaze3d.vertex.VertexFormat;
import com.mojang.blaze3d.vertex.VertexFormatElement;
import java.lang.foreign.MemorySegment;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
final class MetalCompiledRenderPipeline
implements CompiledRenderPipeline,
AutoCloseable {
    static final int STAGE_VERTEX = 1;
    static final int STAGE_FRAGMENT = 2;
    static final int STAGE_ALL = 3;
    private final List<ResourceBinding> resources;
    private final Map<String, ResourceBinding> resourcesByName;
    private final long allResourceMask;
    private final int firstAvailableVertexBufferSlot;
    private final MTLCullMode cullMode;
    private final MTLTriangleFillMode fillMode;
    private final float depthBiasScaleFactor;
    private final float depthBiasConstant;
    private final MTLPrimitiveType topology;
    private final int vertexBufferCount;
    private final MemorySegment depthStencilState;
    private final MemorySegment withDepthPipeline;
    private final MemorySegment withoutDepthPipeline;

    MetalCompiledRenderPipeline(MetalDevice device, RenderPipeline info, String vertexMsl, String fragmentMsl, String vertexEntryPoint, String fragmentEntryPoint, List<ResourceBinding> resources) {
        int depthWrite;
        MTLCompareFunction depthCompareOp;
        this.resources = resources;
        this.resourcesByName = (Map)resources.stream().collect(Collectors.toUnmodifiableMap(ResourceBinding::name, binding -> binding));
        int maxBindingIndex = -1;
        long resourceMask = 0L;
        for (ResourceBinding binding2 : resources) {
            maxBindingIndex = Math.max(maxBindingIndex, binding2.bindingIndex());
            resourceMask |= 1L << binding2.bindingIndex();
        }
        if (maxBindingIndex >= 64) {
            throw new IllegalStateException("Pipeline " + String.valueOf(info.getLocation()) + " has binding index " + maxBindingIndex + ", limit is 63");
        }
        this.allResourceMask = resourceMask;
        this.firstAvailableVertexBufferSlot = MetalCompiledRenderPipeline.firstAvailableVertexBufferSlot(resources);
        this.cullMode = info.isCull() ? MTLCullMode.Back : MTLCullMode.None;
        this.fillMode = info.getPolygonMode() == PolygonMode.WIREFRAME ? MTLTriangleFillMode.Lines : MTLTriangleFillMode.Fill;
        this.topology = MTLPrimitiveType.from(info.getPrimitiveTopology());
        this.vertexBufferCount = info.getVertexFormatBindings().length;
        DepthStencilState depthStencilState = info.getDepthStencilState();
        if (depthStencilState == null) {
            depthCompareOp = MTLCompareFunction.Always;
            depthWrite = 0;
            this.depthBiasScaleFactor = 0.0f;
            this.depthBiasConstant = 0.0f;
        } else {
            depthCompareOp = MTLCompareFunction.from(depthStencilState.depthTest());
            depthWrite = depthStencilState.writeDepth() ? 1 : 0;
            this.depthBiasScaleFactor = depthStencilState.depthBiasScaleFactor();
            this.depthBiasConstant = depthStencilState.depthBiasConstant();
        }
        this.depthStencilState = MetalNativeBridge.MTLDevice_makeDepthStencilState(device.metalDeviceHandle(), depthCompareOp, depthWrite);
        ColorTargetState colorTarget = info.getColorTargetState();
        MTLPixelFormat colorFormat = colorTarget != null ? MTLPixelFormat.from(colorTarget.format()) : MTLPixelFormat.RGBA8Unorm;
        MemorySegment vertexFunction = device.getOrCompileFunction(vertexMsl, vertexEntryPoint);
        MemorySegment fragmentFunction = device.getOrCompileFunction(fragmentMsl, fragmentEntryPoint);
        try (MTLVertexDescriptor vertexDescriptor = MetalCompiledRenderPipeline.buildVertexDescriptor(info, this.firstAvailableVertexBufferSlot);){
            this.withoutDepthPipeline = MetalCompiledRenderPipeline.createPipeline(device, info, vertexFunction, fragmentFunction, vertexDescriptor, colorFormat, MTLPixelFormat.Invalid);
            this.withDepthPipeline = MetalCompiledRenderPipeline.createPipeline(device, info, vertexFunction, fragmentFunction, vertexDescriptor, colorFormat, MTLPixelFormat.Depth32Float);
        }
    }

    private static MemorySegment createPipeline(MetalDevice device, RenderPipeline info, MemorySegment vertexFunction, MemorySegment fragmentFunction, MTLVertexDescriptor vertexDescriptor, MTLPixelFormat colorFormat, MTLPixelFormat depthFormat) {
        if (MetalNativeBridge.isNullHandle(vertexFunction) || MetalNativeBridge.isNullHandle(fragmentFunction)) {
            return MemorySegment.NULL;
        }
        ColorTargetState colorTarget = info.getColorTargetState();
        Optional blendFunction = colorTarget == null ? Optional.empty() : colorTarget.blendFunction();
        long writeMask = colorTarget == null ? MTLColorWriteMask.All.value : MTLColorWriteMask.from(colorTarget.writeMask());
        try (MTLRenderPipelineDescriptor pipelineDesc = new MTLRenderPipelineDescriptor();){
            pipelineDesc.setCompiledFunctions(vertexFunction, fragmentFunction);
            pipelineDesc.setVertexDescriptor(vertexDescriptor);
            pipelineDesc.setAttachmentFormats(colorFormat, depthFormat, MTLPixelFormat.Invalid);
            if (blendFunction.isPresent()) {
                BlendFunction function = (BlendFunction)blendFunction.get();
                pipelineDesc.setBlendState(MTLBlendFactor.from(function.color().sourceFactor()), MTLBlendFactor.from(function.color().destFactor()), MTLBlendOperation.from(function.color().op()), MTLBlendFactor.from(function.alpha().sourceFactor()), MTLBlendFactor.from(function.alpha().destFactor()), MTLBlendOperation.from(function.alpha().op()), writeMask);
            } else {
                pipelineDesc.disableBlending(writeMask);
            }
            MemorySegment memorySegment = MetalNativeBridge.metallum_MTLDevice_makeRenderPipelineState(device.metalDeviceHandle(), pipelineDesc.handle());
            return memorySegment;
        }
    }

    public boolean isValid() {
        return !MetalNativeBridge.isNullHandle(this.withoutDepthPipeline);
    }

    List<ResourceBinding> resources() {
        return this.resources;
    }

    long allResourceMask() {
        return this.allResourceMask;
    }

    @Nullable ResourceBinding resource(String name) {
        return this.resourcesByName.get(name);
    }

    int firstAvailableVertexBufferSlot() {
        return this.firstAvailableVertexBufferSlot;
    }

    float depthBiasScaleFactor() {
        return this.depthBiasScaleFactor;
    }

    float depthBiasConstant() {
        return this.depthBiasConstant;
    }

    MemorySegment getDepthStencilState() {
        return this.depthStencilState;
    }

    MemorySegment getNativePipeline(boolean useDepth) {
        return useDepth && !MetalNativeBridge.isNullHandle(this.withDepthPipeline) ? this.withDepthPipeline : this.withoutDepthPipeline;
    }

    MTLCullMode cullMode() {
        return this.cullMode;
    }

    MTLTriangleFillMode fillMode() {
        return this.fillMode;
    }

    MTLPrimitiveType topology() {
        return this.topology;
    }

    int vertexBufferCount() {
        return this.vertexBufferCount;
    }

    private static MTLVertexDescriptor buildVertexDescriptor(RenderPipeline pipeline, int firstMetalVertexBufferSlot) {
        VertexFormat[] bindings = pipeline.getVertexFormatBindings();
        MTLVertexDescriptor vertexDesc = new MTLVertexDescriptor();
        long attrIndex = 0L;
        for (int i = 0; i < bindings.length; ++i) {
            VertexFormat binding = bindings[i];
            if (binding == null || binding.getElements().isEmpty()) continue;
            int metalSlot = firstMetalVertexBufferSlot + i;
            long stride = binding.getVertexSize();
            long stepRate = binding.getStepRate();
            MTLVertexStepFunction stepFunction = stepRate > 0L ? MTLVertexStepFunction.PerInstance : MTLVertexStepFunction.PerVertex;
            vertexDesc.setLayout(metalSlot, stride, stepFunction, stepRate > 0L ? stepRate : 1L);
            for (VertexFormatElement element : binding.getElements()) {
                MTLVertexFormat format = MTLVertexFormat.from(element.format());
                if (format == MTLVertexFormat.Invalid) {
                    throw new IllegalStateException("Unsupported vertex attribute format: " + String.valueOf(element.format()));
                }
                vertexDesc.setAttribute(attrIndex, format.value, element.offset(), metalSlot);
                ++attrIndex;
            }
        }
        return vertexDesc;
    }

    private static int firstAvailableVertexBufferSlot(List<ResourceBinding> resources) {
        int maxVertexBufferBinding = -1;
        for (ResourceBinding resource : resources) {
            if (resource.kind() != ResourceKind.UNIFORM_BUFFER || (resource.stageMask() & 1) == 0) continue;
            maxVertexBufferBinding = Math.max(maxVertexBufferBinding, resource.bindingIndex());
        }
        return maxVertexBufferBinding + 1;
    }

    @Override
    public void close() {
        if (!MetalNativeBridge.isNullHandle(this.withDepthPipeline)) {
            MetalNativeBridge.metallum_release_object(this.withDepthPipeline);
        }
        if (!MetalNativeBridge.isNullHandle(this.withoutDepthPipeline)) {
            MetalNativeBridge.metallum_release_object(this.withoutDepthPipeline);
        }
    }

    record ResourceBinding(ResourceKind kind, String name, int bindingIndex, int stageMask, @Nullable GpuFormat texelBufferFormat) {
    }

    static enum ResourceKind {
        UNIFORM_BUFFER,
        SAMPLED_IMAGE,
        TEXEL_BUFFER;

    }
}

