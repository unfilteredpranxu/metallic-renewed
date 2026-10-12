/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.GpuFormat
 *  com.mojang.blaze3d.buffers.GpuBuffer
 *  com.mojang.blaze3d.buffers.GpuBuffer$Usage
 *  com.mojang.blaze3d.pipeline.CompiledRenderPipeline
 *  com.mojang.blaze3d.pipeline.RenderPipeline
 *  com.mojang.blaze3d.preprocessor.GlslPreprocessor
 *  com.mojang.blaze3d.shaders.GpuDebugOptions
 *  com.mojang.blaze3d.shaders.ShaderSource
 *  com.mojang.blaze3d.shaders.ShaderType
 *  com.mojang.blaze3d.systems.DeviceFeatures
 *  com.mojang.blaze3d.systems.DeviceInfo
 *  com.mojang.blaze3d.systems.DeviceLimits
 *  com.mojang.blaze3d.systems.DeviceType
 *  com.mojang.blaze3d.systems.GpuDeviceBackend
 *  com.mojang.blaze3d.systems.GpuQueryPool
 *  com.mojang.blaze3d.systems.GpuSurfaceBackend
 *  com.mojang.blaze3d.systems.HintsAndWorkarounds
 *  com.mojang.blaze3d.textures.AddressMode
 *  com.mojang.blaze3d.textures.FilterMode
 *  com.mojang.blaze3d.textures.GpuSampler
 *  com.mojang.blaze3d.textures.GpuTexture
 *  com.mojang.blaze3d.textures.GpuTexture$Usage
 *  com.mojang.blaze3d.textures.GpuTextureView
 *  com.mojang.blaze3d.vulkan.glsl.GlslCompiler
 *  com.mojang.blaze3d.vulkan.glsl.IntermediaryShaderModule
 *  com.mojang.blaze3d.vulkan.glsl.ShaderCompileException
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  net.minecraft.client.renderer.ShaderDefines
 *  net.minecraft.resources.Identifier
 *  org.jspecify.annotations.NonNull
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalCompiledRenderPipeline;
import com.metallum.client.metal.render.MetalCrossShaderCompiler;
import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.MetalGpuQueryPool;
import com.metallum.client.metal.render.MetalGpuSampler;
import com.metallum.client.metal.render.MetalGpuTexture;
import com.metallum.client.metal.render.MetalGpuTextureView;
import com.metallum.client.metal.render.MetalSurface;
import com.metallum.client.metal.render.Stats;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLCommandQueue;
import com.mojang.blaze3d.GpuFormat;
import com.mojang.blaze3d.buffers.GpuBuffer;
import com.mojang.blaze3d.pipeline.CompiledRenderPipeline;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.preprocessor.GlslPreprocessor;
import com.mojang.blaze3d.shaders.GpuDebugOptions;
import com.mojang.blaze3d.shaders.ShaderSource;
import com.mojang.blaze3d.shaders.ShaderType;
import com.mojang.blaze3d.systems.DeviceFeatures;
import com.mojang.blaze3d.systems.DeviceInfo;
import com.mojang.blaze3d.systems.DeviceLimits;
import com.mojang.blaze3d.systems.DeviceType;
import com.mojang.blaze3d.systems.GpuDeviceBackend;
import com.mojang.blaze3d.systems.GpuQueryPool;
import com.mojang.blaze3d.systems.GpuSurfaceBackend;
import com.mojang.blaze3d.systems.HintsAndWorkarounds;
import com.mojang.blaze3d.textures.AddressMode;
import com.mojang.blaze3d.textures.FilterMode;
import com.mojang.blaze3d.textures.GpuSampler;
import com.mojang.blaze3d.textures.GpuTexture;
import com.mojang.blaze3d.textures.GpuTextureView;
import com.mojang.blaze3d.vulkan.glsl.GlslCompiler;
import com.mojang.blaze3d.vulkan.glsl.IntermediaryShaderModule;
import com.mojang.blaze3d.vulkan.glsl.ShaderCompileException;
import java.lang.foreign.MemorySegment;
import java.nio.ByteBuffer;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.OptionalDouble;
import java.util.Set;
import java.util.function.Supplier;
import java.util.regex.Pattern;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import net.minecraft.client.renderer.ShaderDefines;
import net.minecraft.resources.Identifier;
import org.jspecify.annotations.NonNull;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
final class MetalDevice
implements GpuDeviceBackend {
    private static final Pattern BLOCK_COMMENTS = Pattern.compile("(?s)/\\*.*?\\*/");
    private static final Pattern LINE_COMMENTS = Pattern.compile("(?m)//[^\\n]*");
    private final MemorySegment metalDeviceHandle;
    private final MemorySegment metalLayer;
    private final MemorySegment cocoaView;
    private final GpuDebugOptions debugOptions;
    private final MetalCommandEncoder commandEncoder;
    private final DeviceInfo deviceInfo;
    public final MTLCommandQueue commandQueue;
    private final Map<RenderPipeline, MetalCompiledRenderPipeline> compiledPipelines = new IdentityHashMap<RenderPipeline, MetalCompiledRenderPipeline>();
    private final Map<ShaderCompilationKey, IntermediaryShaderModule> shaderCache = new HashMap<ShaderCompilationKey, IntermediaryShaderModule>();
    private final Map<MslFunctionKey, MemorySegment> functionCache = new HashMap<MslFunctionKey, MemorySegment>();
    private static final int MAX_POOLED_BUFFER_BUCKETS = 32;
    private static final int MAX_POOLED_BUFFERS_PER_SIZE = 8;
    private final Map<Long, Deque<MemorySegment>> bufferPool = new LinkedHashMap<Long, Deque<MemorySegment>>(this, 16, 0.75f, true){
        final /* synthetic */ MetalDevice this$0;
        {
            MetalDevice metalDevice = this$0;
            Objects.requireNonNull(metalDevice);
            this.this$0 = metalDevice;
            super(arg0, arg1, arg2);
        }

        @Override
        protected boolean removeEldestEntry(Map.Entry<Long, Deque<MemorySegment>> eldest) {
            if (this.size() <= 32) {
                return false;
            }
            for (MemorySegment handle : eldest.getValue()) {
                MetalNativeBridge.metallum_release_object(handle);
            }
            return true;
        }
    };
    private static final int MAX_TEXEL_VIEWS = 128;
    private final Map<TexelTexelViewKey, MemorySegment> texelViewCache = new LinkedHashMap<TexelTexelViewKey, MemorySegment>(this, 16, 0.75f, true){
        final /* synthetic */ MetalDevice this$0;
        {
            MetalDevice metalDevice = this$0;
            Objects.requireNonNull(metalDevice);
            this.this$0 = metalDevice;
            super(arg0, arg1, arg2);
        }

        @Override
        protected boolean removeEldestEntry(Map.Entry<TexelTexelViewKey, MemorySegment> eldest) {
            if (this.size() <= 128) {
                return false;
            }
            MetalNativeBridge.metallum_release_object(eldest.getValue());
            return true;
        }
    };
    private ShaderSource activeShaderSource;

    MetalDevice(ShaderSource defaultShaderSource, GpuDebugOptions debugOptions, MemorySegment metalDeviceHandle, MemorySegment metalLayer, String deviceName, MemorySegment cocoaView) {
        this.activeShaderSource = defaultShaderSource;
        this.debugOptions = debugOptions;
        this.metalDeviceHandle = metalDeviceHandle;
        this.metalLayer = metalLayer;
        this.cocoaView = cocoaView;
        MetalNativeBridge.metallum_set_debug_labels_enabled(this.useLabels());
        this.commandQueue = MTLCommandQueue.create(metalDeviceHandle);
        MetalNativeBridge.metallum_init_pipelines(metalDeviceHandle);
        this.commandEncoder = new MetalCommandEncoder(this);
        this.deviceInfo = this.buildDeviceInfo(deviceName);
    }

    public @NonNull GpuSurfaceBackend createSurface(long windowHandle) {
        return new MetalSurface(this, this.metalLayer);
    }

    public @NonNull MetalCommandEncoder createCommandEncoder() {
        return this.commandEncoder;
    }

    public @NonNull GpuSampler createSampler(@NonNull AddressMode addressModeU, @NonNull AddressMode addressModeV, @NonNull FilterMode minFilter, @NonNull FilterMode magFilter, int maxAnisotropy, @NonNull OptionalDouble maxLod) {
        return new MetalGpuSampler(this, addressModeU, addressModeV, minFilter, magFilter, maxAnisotropy, maxLod);
    }

    public @NonNull GpuTexture createTexture(@Nullable Supplier<String> label, @GpuTexture.Usage int usage, @NonNull GpuFormat format, int width, int height, int depthOrLayers, int mipLevels) {
        return this.createTexture(this.resolveDebugLabel(label), usage, format, width, height, depthOrLayers, mipLevels);
    }

    public @NonNull GpuTexture createTexture(@Nullable String label, @GpuTexture.Usage int usage, @NonNull GpuFormat format, int width, int height, int depthOrLayers, int mipLevels) {
        return new MetalGpuTexture(this, usage, label == null ? "" : label, format, width, height, depthOrLayers, mipLevels);
    }

    public @NonNull GpuTextureView createTextureView(@NonNull GpuTexture texture) {
        return this.createTextureView(texture, 0, texture.getMipLevels());
    }

    public @NonNull GpuTextureView createTextureView(@NonNull GpuTexture texture, int baseMipLevel, int mipLevels) {
        return new MetalGpuTextureView(texture, baseMipLevel, mipLevels);
    }

    public @NonNull GpuBuffer createBuffer(@Nullable Supplier<String> label, @GpuBuffer.Usage int usage, long size) {
        if (size <= 0L) {
            throw new IllegalArgumentException("Metal buffer size must be > 0 (got " + size + ")");
        }
        return new MetalGpuBuffer(this, usage, size);
    }

    public @NonNull GpuBuffer createBuffer(@Nullable Supplier<String> label, @GpuBuffer.Usage int usage, ByteBuffer data) {
        if (data == null || data.remaining() <= 0) {
            throw new IllegalArgumentException("Cannot create buffer from empty ByteBuffer");
        }
        MetalGpuBuffer buffer = (MetalGpuBuffer)this.createBuffer(label, usage | 8, data.remaining());
        this.commandEncoder.writeToBuffer(buffer.slice(), data.duplicate());
        return buffer;
    }

    public @NonNull List<String> getLastDebugMessages() {
        return List.of();
    }

    public boolean isDebuggingEnabled() {
        return this.debugOptions.logLevel() > 0 || this.debugOptions.useLabels() || this.debugOptions.useValidationLayers();
    }

    boolean useLabels() {
        return this.debugOptions.useLabels();
    }

    public @NonNull CompiledRenderPipeline precompilePipeline(@NonNull RenderPipeline pipeline, @Nullable ShaderSource shaderSource) {
        ShaderSource effectiveSource;
        ShaderSource shaderSource2 = effectiveSource = shaderSource == null ? this.activeShaderSource : shaderSource;
        if (shaderSource != null) {
            this.activeShaderSource = shaderSource;
        }
        return this.compiledPipelines.computeIfAbsent(pipeline, p -> MetalCrossShaderCompiler.compile(this, p, effectiveSource));
    }

    public void clearPipelineCache() {
        this.waitForSubmittedGpuWork();
        this.compiledPipelines.values().forEach(MetalCompiledRenderPipeline::close);
        this.compiledPipelines.clear();
        this.shaderCache.values().forEach(IntermediaryShaderModule::close);
        this.shaderCache.clear();
        for (MemorySegment function : this.functionCache.values()) {
            if (MetalNativeBridge.isNullHandle(function)) continue;
            MetalNativeBridge.metallum_release_object(function);
        }
        this.functionCache.clear();
        for (MemorySegment view : this.texelViewCache.values()) {
            if (MetalNativeBridge.isNullHandle(view)) continue;
            MetalNativeBridge.metallum_release_object(view);
        }
        this.texelViewCache.clear();
    }

    public void close() {
        this.waitForSubmittedGpuWork();
        this.commandEncoder.close();
        this.clearPipelineCache();
        this.drainBufferPool();
        try {
            MetalNativeBridge.metallum_NSView_clearLayer(this.cocoaView);
        }
        catch (Throwable throwable) {
            // empty catch block
        }
        this.commandQueue.close();
        MetalNativeBridge.metallum_release_object(this.metalDeviceHandle);
    }

    public @NonNull GpuQueryPool createTimestampQueryPool(int size) {
        return new MetalGpuQueryPool(size);
    }

    public long getTimestampNow() {
        return System.nanoTime();
    }

    public @NonNull DeviceInfo getDeviceInfo() {
        return this.deviceInfo;
    }

    MemorySegment metalDeviceHandle() {
        return this.metalDeviceHandle;
    }

    long maxBufferAllocationSize() {
        return this.deviceInfo.limits().maxMemoryAllocationSize();
    }

    void waitForSubmittedGpuWork() {
        this.commandEncoder.waitForSubmittedGpuWork();
    }

    void queueResourceRelease(MemorySegment handle) {
        this.commandEncoder.queueForDestroy(() -> MetalNativeBridge.metallum_release_object(handle));
    }

    MemorySegment tryAcquirePooledBuffer(long size, long resourceOptions) {
        long key = MetalDevice.composePoolKey(size, resourceOptions);
        Deque<MemorySegment> bucket = this.bufferPool.get(key);
        if (bucket != null && !bucket.isEmpty()) {
            return bucket.pop();
        }
        return MemorySegment.NULL;
    }

    void queueBufferRelease(MemorySegment handle, long size, long resourceOptions) {
        this.commandEncoder.queueForDestroy(() -> {
            long key = MetalDevice.composePoolKey(size, resourceOptions);
            Deque bucket = this.bufferPool.computeIfAbsent(key, k -> new ArrayDeque());
            if (bucket.size() < 8) {
                bucket.push(handle);
            } else {
                MetalNativeBridge.metallum_release_object(handle);
            }
        });
    }

    MemorySegment getOrCreateTexelView(MetalGpuBuffer texelBuffer, long pixelFormat, long offset, long texelCount, long height, long bytesPerRow) {
        TexelTexelViewKey key = new TexelTexelViewKey(texelBuffer.nativeHandle().address(), pixelFormat, offset, bytesPerRow, texelCount, height);
        MemorySegment cached = this.texelViewCache.get((Object)key);
        if (cached != null && !MetalNativeBridge.isNullHandle(cached)) {
            return cached;
        }
        MemorySegment view = MetalNativeBridge.metallum_create_buffer_texture_view(texelBuffer.nativeHandle(), pixelFormat, offset, texelCount, height, bytesPerRow);
        if (!MetalNativeBridge.isNullHandle(view)) {
            this.texelViewCache.put(key, view);
            Stats.recordTexelViewAllocation();
        }
        return view;
    }

    static long composePoolKey(long size, long resourceOptions) {
        return size << 12 | resourceOptions & 0xFFFL;
    }

    private void drainBufferPool() {
        for (Deque<MemorySegment> bucket : this.bufferPool.values()) {
            for (MemorySegment handle : bucket) {
                MetalNativeBridge.metallum_release_object(handle);
            }
        }
        this.bufferPool.clear();
    }

    MetalCompiledRenderPipeline getOrCompilePipeline(RenderPipeline pipeline) {
        return this.compiledPipelines.computeIfAbsent(pipeline, p -> MetalCrossShaderCompiler.compile(this, p, this.activeShaderSource));
    }

    IntermediaryShaderModule getOrCompileShader(Identifier id, ShaderType type, ShaderDefines defines, ShaderSource shaderSource) {
        ShaderCompilationKey key = new ShaderCompilationKey(id, type, defines);
        return this.shaderCache.computeIfAbsent(key, k -> {
            IntermediaryShaderModule intermediaryShaderModule;
            String source = shaderSource.get(k.id(), k.type());
            if (source == null) {
                return IntermediaryShaderModule.INVALID;
            }
            String sourceWithDefines = MetalDevice.prepareShaderSource(source, k.defines());
            GlslCompiler glslCompiler = new GlslCompiler();
            try {
                intermediaryShaderModule = glslCompiler.createIntermediary(k.id().toDebugFileName(), sourceWithDefines, k.type());
            }
            catch (Throwable t$) {
                try {
                    try {
                        glslCompiler.close();
                    }
                    catch (Throwable x2) {
                        t$.addSuppressed(x2);
                    }
                    throw t$;
                }
                catch (ShaderCompileException e) {
                    throw new IllegalStateException("Failed to compile shader " + String.valueOf(k.id()), e);
                }
            }
            glslCompiler.close();
            return intermediaryShaderModule;
        });
    }

    private static String prepareShaderSource(String source, ShaderDefines defines) {
        String stripped = BLOCK_COMMENTS.matcher(source).replaceAll("");
        stripped = LINE_COMMENTS.matcher(stripped).replaceAll("").stripLeading();
        return GlslPreprocessor.injectDefines((String)stripped, (ShaderDefines)defines);
    }

    MemorySegment getOrCompileFunction(String msl, String entryPoint) {
        return this.functionCache.computeIfAbsent(new MslFunctionKey(msl, entryPoint), key -> MetalNativeBridge.metallum_create_shader_function(this.metalDeviceHandle, key.msl(), key.entryPoint()));
    }

    private DeviceInfo buildDeviceInfo(String deviceName) {
        DeviceType type = DeviceType.INTEGRATED;
        Set underlyingExtensions = Set.of((Object)"CAMetalLayer", (Object)"MTLDevice");
        String osVersion = System.getProperty("os.version", "").trim();
        String platformName = MetalNativeBridge.isIOS() ? "iOS" : "macOS";
        String driverDescription = platformName + " " + osVersion;
        long maxMemoryAllocationSize = MetalNativeBridge.MTLDevice_maxMemoryAllocationSize(this.metalDeviceHandle);
        return new DeviceInfo(deviceName, "Apple", driverDescription, true, "Metal", 1.0f, new DeviceLimits(16, 256, 16384, maxMemoryAllocationSize, 0, 1), new DeviceFeatures(false, false, true, true, true, false, true), underlyingExtensions, new HintsAndWorkarounds(false, false), type);
    }

    private @Nullable String resolveDebugLabel(@Nullable Supplier<String> label) {
        return this.useLabels() && label != null ? label.get() : null;
    }

    private record TexelTexelViewKey(long bufferAddress, long pixelFormat, long offset, long bytesPerRow, long texelCount, long height) {
    }

    private record ShaderCompilationKey(Identifier id, ShaderType type, ShaderDefines defines) {
    }

    private record MslFunctionKey(String msl, String entryPoint) {
    }
}

