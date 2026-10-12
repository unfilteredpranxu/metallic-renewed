/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.MetalCrossShaderCompiler$CompiledGlsl
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline$MtlPipelineKey
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline$ResourceBinding
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline$ResourceKind
 *  com.metallum.client.metal.render.sodium.SodiumGlAttributeFormatMapper
 *  com.mojang.blaze3d.pipeline.RenderPipeline
 *  com.mojang.blaze3d.platform.DepthTestFunction
 *  com.mojang.blaze3d.platform.PolygonMode
 *  com.mojang.blaze3d.vertex.VertexFormat$b
 *  com.mojang.blaze3d.vertex.VertexFormatElement$Type
 *  java.lang.foreign.MemorySegment
 *  net.caffeinemc.mods.sodium.client.gl.attribute.GlVertexAttributeBinding
 *  net.caffeinemc.mods.sodium.client.gl.attribute.GlVertexFormat
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.MetalCrossShaderCompiler;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.MetalPipelineSupport;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLColorWriteMask;
import com.metallum.client.metal.render.mtl.MTLCompareFunction;
import com.metallum.client.metal.render.mtl.MTLCullMode;
import com.metallum.client.metal.render.mtl.MTLPixelFormat;
import com.metallum.client.metal.render.mtl.MTLPrimitiveType;
import com.metallum.client.metal.render.mtl.MTLTriangleFillMode;
import com.metallum.client.metal.render.mtl.MTLVertexDescriptor;
import com.metallum.client.metal.render.mtl.MTLVertexFormat;
import com.metallum.client.metal.render.mtl.MTLVertexStepFunction;
import com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline;
import com.metallum.client.metal.render.sodium.SodiumGlAttributeFormatMapper;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.platform.DepthTestFunction;
import com.mojang.blaze3d.platform.PolygonMode;
import com.mojang.blaze3d.vertex.VertexFormat;
import com.mojang.blaze3d.vertex.VertexFormatElement;
import java.lang.foreign.MemorySegment;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import net.caffeinemc.mods.sodium.client.gl.attribute.GlVertexAttributeBinding;
import net.caffeinemc.mods.sodium.client.gl.attribute.GlVertexFormat;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
public final class MetalSodiumCompiledPipeline
implements AutoCloseable {
    public static final int STAGE_VERTEX = 1;
    public static final int STAGE_FRAGMENT = 2;
    private static final Pattern BUFFER_PARAM_PATTERN = Pattern.compile("constant\\s+([\\w<>]+)&\\s+(\\w+)\\s+\\[\\[buffer\\((\\d+)\\)\\]\\]");
    private static final Pattern TEXTURE_PARAM_PATTERN = Pattern.compile("texture2d<float>\\s+(\\w+)\\s+\\[\\[texture\\((\\d+)\\)\\]\\]");
    private final MetalDevice device;
    private final RenderPipeline stateSource;
    private final String vertexMsl;
    private final String fragmentMsl;
    private final GlVertexFormat vertexFormat;
    private final int firstVertexBufferSlot;
    private final List<ResourceBinding> resources;
    private final Map<String, ResourceBinding> resourcesByName;
    private final long allResourceMask;
    private final MTLCullMode cullMode;
    private final MTLTriangleFillMode fillMode;
    private final float depthBiasScaleFactor;
    private final float depthBiasConstant;
    private final MTLPrimitiveType topology;
    private final MTLCompareFunction depthCompareOp;
    private final int depthWrite;
    private final MemorySegment depthStencilState;
    private final MemorySegment vertexFunction;
    private final MemorySegment fragmentFunction;
    private final Map<MtlPipelineKey, MemorySegment> pipelineCache = new LinkedHashMap();
    private MemorySegment cachedWithDepth;
    private MemorySegment cachedWithoutDepth;
    private MTLPixelFormat cachedColorFormat;

    public MetalSodiumCompiledPipeline(MetalDevice device, RenderPipeline stateSource, MetalCrossShaderCompiler.CompiledGlsl compiled, GlVertexFormat vertexFormat, Map<String, Integer> vertexBufferBindings, Map<String, Integer> fragmentBufferBindings, Map<String, Integer> vertexTextureBindings, Map<String, Integer> fragmentTextureBindings) {
        this.device = device;
        this.stateSource = stateSource;
        this.vertexMsl = compiled.vertexMsl();
        this.fragmentMsl = compiled.fragmentMsl();
        this.vertexFormat = vertexFormat;
        this.resources = new ArrayList();
        this.addResources(vertexBufferBindings, 1, ResourceKind.UNIFORM_BUFFER);
        this.addResources(fragmentBufferBindings, 2, ResourceKind.UNIFORM_BUFFER);
        this.addResources(vertexTextureBindings, 1, ResourceKind.SAMPLED_IMAGE);
        this.addResources(fragmentTextureBindings, 2, ResourceKind.SAMPLED_IMAGE);
        LinkedHashMap<String, ResourceBinding> byName = new LinkedHashMap<String, ResourceBinding>();
        int maxBinding = -1;
        long mask = 0L;
        for (Object binding : this.resources) {
            byName.put(binding.name(), (ResourceBinding)binding);
            maxBinding = Math.max(maxBinding, binding.bindingIndex());
            mask |= 1L << binding.bindingIndex();
        }
        this.resourcesByName = Map.copyOf(byName);
        this.allResourceMask = mask;
        int maxVertexBuffer = -1;
        for (Map.Entry entry : vertexBufferBindings.entrySet()) {
            maxVertexBuffer = Math.max(maxVertexBuffer, (Integer)entry.getValue());
        }
        this.firstVertexBufferSlot = maxVertexBuffer + 1;
        this.cullMode = stateSource.isCull() ? MTLCullMode.Back : MTLCullMode.None;
        this.fillMode = stateSource.getPolygonMode() == PolygonMode.WIREFRAME ? MTLTriangleFillMode.Lines : MTLTriangleFillMode.Fill;
        this.topology = MTLPrimitiveType.from((VertexFormat.b)stateSource.getVertexFormatMode());
        this.depthBiasScaleFactor = stateSource.getDepthBiasScaleFactor();
        this.depthBiasConstant = stateSource.getDepthBiasConstant();
        DepthTestFunction depthTest = stateSource.getDepthTestFunction();
        this.depthCompareOp = MTLCompareFunction.from((DepthTestFunction)depthTest);
        this.depthWrite = stateSource.isWriteDepth() ? 1 : 0;
        this.depthStencilState = MetalNativeBridge.MTLDevice_makeDepthStencilState(device.metalDeviceHandle(), this.depthCompareOp, this.depthWrite);
        this.vertexFunction = device.getOrCompileFunction(compiled.vertexMsl(), compiled.vertexEntryPoint());
        this.fragmentFunction = device.getOrCompileFunction(compiled.fragmentMsl(), compiled.fragmentEntryPoint());
        MTLVertexDescriptor mTLVertexDescriptor = this.buildVertexDescriptor(vertexFormat, this.firstVertexBufferSlot);
        if (mTLVertexDescriptor != null) {
            mTLVertexDescriptor.close();
        }
    }

    private void addResources(Map<String, Integer> bindings, int stageMask, ResourceKind kind) {
        for (Map.Entry<String, Integer> e : bindings.entrySet()) {
            this.resources.add(new ResourceBinding(kind, e.getKey(), e.getValue().intValue(), stageMask));
        }
    }

    public static Map<String, Integer> extractBuffers(String msl, String uboTypeName) {
        LinkedHashMap<String, Integer> out = new LinkedHashMap<String, Integer>();
        Matcher matcher = BUFFER_PARAM_PATTERN.matcher(msl);
        while (matcher.find()) {
            String typeName = matcher.group(1);
            String varName = matcher.group(2);
            int index = Integer.parseInt(matcher.group(3));
            if (varName.startsWith("_")) {
                if (!uboTypeName.equals(typeName)) continue;
                out.put(uboTypeName, index);
                continue;
            }
            out.put(varName, index);
        }
        return out;
    }

    public static Map<String, Integer> extractTextures(String msl) {
        LinkedHashMap<String, Integer> out = new LinkedHashMap<String, Integer>();
        Matcher matcher = TEXTURE_PARAM_PATTERN.matcher(msl);
        while (matcher.find()) {
            out.put(matcher.group(1), Integer.parseInt(matcher.group(2)));
        }
        return out;
    }

    private MTLVertexDescriptor buildVertexDescriptor(GlVertexFormat vertexFormat, int metalSlot) {
        MTLVertexDescriptor vertexDesc = new MTLVertexDescriptor();
        long stride = vertexFormat.getStride();
        vertexDesc.setLayout(metalSlot, stride, MTLVertexStepFunction.PerVertex, 1L);
        for (GlVertexAttributeBinding binding : vertexFormat.getShaderBindings()) {
            MTLVertexFormat format;
            int attrIndex = binding.getIndex();
            GlVertexAttributeBinding attribute = binding;
            VertexFormatElement.Type type = SodiumGlAttributeFormatMapper.toMinecraftType((int)attribute.getFormat());
            MTLVertexFormat mTLVertexFormat = format = attribute.isIntType() ? MTLVertexFormat.fromInteger((VertexFormatElement.Type)type, (int)attribute.getCount()) : MTLVertexFormat.from((VertexFormatElement.Type)type, (int)attribute.getCount());
            if (format == MTLVertexFormat.Invalid) {
                throw new IllegalStateException("Unsupported Sodium vertex attribute format: " + String.valueOf(type) + "x" + attribute.getCount());
            }
            vertexDesc.setAttribute(attrIndex, format.value, attribute.getPointer(), metalSlot);
        }
        return vertexDesc;
    }

    private static String attributeNameForIndex(int index) {
        return switch (index) {
            case 0 -> "a_Position";
            case 1 -> "a_Color";
            case 2 -> "a_TexCoord";
            case 3 -> "a_LightAndData";
            default -> "a_Attr" + index;
        };
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    public @Nullable MemorySegment getNativePipeline(boolean useDepth, MTLPixelFormat colorFormat) {
        if (this.cachedColorFormat == colorFormat) {
            MemorySegment hit;
            MemorySegment memorySegment = hit = useDepth ? this.cachedWithDepth : this.cachedWithoutDepth;
            if (hit != null) {
                return hit;
            }
        }
        MetalSodiumCompiledPipeline metalSodiumCompiledPipeline = this;
        synchronized (metalSodiumCompiledPipeline) {
            MtlPipelineKey key;
            MemorySegment cached;
            if (this.cachedColorFormat == colorFormat) {
                MemorySegment hit;
                MemorySegment memorySegment = hit = useDepth ? this.cachedWithDepth : this.cachedWithoutDepth;
                if (hit != null) {
                    return hit;
                }
            }
            if ((cached = (MemorySegment)this.pipelineCache.get(key = new MtlPipelineKey(this.stateSource, colorFormat, useDepth))) != null) {
                if (useDepth) {
                    this.cachedWithDepth = cached;
                } else {
                    this.cachedWithoutDepth = cached;
                }
                this.cachedColorFormat = colorFormat;
                return cached;
            }
            MTLPixelFormat depthFormat = useDepth ? MTLPixelFormat.Depth32Float : MTLPixelFormat.Invalid;
            long writeMask = MTLColorWriteMask.from((boolean)this.stateSource.isWriteColor(), (boolean)this.stateSource.isWriteAlpha());
            try (MTLVertexDescriptor vertexDescriptor = this.buildVertexDescriptorForPipeline();){
                cached = MetalPipelineSupport.makeRenderPipelineState((MetalDevice)this.device, (MemorySegment)this.vertexFunction, (MemorySegment)this.fragmentFunction, (MTLVertexDescriptor)vertexDescriptor, (MTLPixelFormat)colorFormat, (MTLPixelFormat)depthFormat, (Optional)this.stateSource.getBlendFunction(), (long)writeMask, (String)this.stateSource.getLocation().toString());
            }
            this.pipelineCache.put(key, cached);
            if (useDepth) {
                this.cachedWithDepth = cached;
            } else {
                this.cachedWithoutDepth = cached;
            }
            this.cachedColorFormat = colorFormat;
            return cached;
        }
    }

    private MTLVertexDescriptor buildVertexDescriptorForPipeline() {
        return this.buildVertexDescriptor(this.vertexFormat, this.firstVertexBufferSlot);
    }

    public List<ResourceBinding> resources() {
        return this.resources;
    }

    public long allResourceMask() {
        return this.allResourceMask;
    }

    public // Could not load outer class - annotation placement on inner may be incorrect
    @Nullable MetalSodiumCompiledPipeline.ResourceBinding resource(String name) {
        return (ResourceBinding)this.resourcesByName.get(name);
    }

    public int firstAvailableVertexBufferSlot() {
        return this.firstVertexBufferSlot;
    }

    public int vertexBufferCount() {
        return 1;
    }

    public MTLCullMode cullMode() {
        return this.cullMode;
    }

    public MTLTriangleFillMode fillMode() {
        return this.fillMode;
    }

    public MTLPrimitiveType topology() {
        return this.topology;
    }

    public float depthBiasScaleFactor() {
        return this.depthBiasScaleFactor;
    }

    public float depthBiasConstant() {
        return this.depthBiasConstant;
    }

    public MTLCompareFunction depthCompareOp() {
        return this.depthCompareOp;
    }

    public int depthWrite() {
        return this.depthWrite;
    }

    public MemorySegment getDepthStencilState() {
        return this.depthStencilState;
    }

    public Set<String> vertexInputNames() {
        return Set.of((Object)"a_Position", (Object)"a_Color", (Object)"a_TexCoord", (Object)"a_LightAndData");
    }

    public boolean isValid() {
        return !MetalNativeBridge.isNullHandle(this.vertexFunction) && !MetalNativeBridge.isNullHandle(this.fragmentFunction);
    }

    @Override
    public void close() {
        for (MemorySegment pipeline : this.pipelineCache.values()) {
            if (MetalNativeBridge.isNullHandle(pipeline)) continue;
            MetalNativeBridge.metallum_release_object(pipeline);
        }
        this.pipelineCache.clear();
    }
}

