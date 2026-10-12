/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  java.lang.foreign.Arena
 *  java.lang.foreign.FunctionDescriptor
 *  java.lang.foreign.Linker
 *  java.lang.foreign.Linker$Option
 *  java.lang.foreign.MemoryLayout
 *  java.lang.foreign.MemorySegment
 *  java.lang.foreign.SymbolLookup
 *  java.lang.foreign.ValueLayout
 *  java.lang.foreign.ValueLayout$OfDouble
 *  java.lang.foreign.ValueLayout$OfFloat
 *  java.lang.foreign.ValueLayout$OfInt
 *  java.lang.foreign.ValueLayout$OfLong
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 *  org.lwjgl.system.Configuration
 */
package com.metallum.client.metal.render.bridge;

import com.metallum.client.metal.render.mtl.MTLCompareFunction;
import com.metallum.client.metal.render.mtl.MTLPixelFormat;
import com.metallum.client.metal.render.mtl.MTLSamplerAddressMode;
import com.metallum.client.metal.render.mtl.MTLSamplerMinMagFilter;
import com.metallum.client.metal.render.mtl.MTLSamplerMipFilter;
import com.metallum.client.metal.render.mtl.MTLStorageMode;
import java.io.IOException;
import java.io.InputStream;
import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemoryLayout;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.FileAttribute;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.Nullable;
import org.lwjgl.system.Configuration;

@Environment(value=EnvType.CLIENT)
public final class MetalNativeBridge {
    private static final String MACOS_RESOURCE_PATH = "/natives/macos/libmetallum.dylib";
    private static final String IOS_RESOURCE_PATH = "/natives/ios/libmetallum.dylib";
    private static final ValueLayout.OfInt INT = ValueLayout.JAVA_INT;
    private static final ValueLayout.OfLong LONG = ValueLayout.JAVA_LONG;
    private static final ValueLayout.OfFloat FLOAT = ValueLayout.JAVA_FLOAT;
    private static final ValueLayout.OfDouble DOUBLE = ValueLayout.JAVA_DOUBLE;
    private static final Linker LINKER = Linker.nativeLinker();
    private static volatile boolean spvcConfigured = false;
    private static final MethodHandle createSystemDefaultDevice;
    private static final MethodHandle copyDeviceName;
    private static final MethodHandle NSWindowBackingScaleFactor;
    private static final MethodHandle createMetalLayer;
    private static final MethodHandle NSViewSetMetalLayer;
    private static final MethodHandle NSViewClearLayer;
    private static final MethodHandle setDebugLabelsEnabled;
    private static final MethodHandle MTLDeviceMaxMemoryAllocationSize;
    private static final MethodHandle MTLDeviceMakeCommandQueue;
    private static final MethodHandle MTLCommandQueueMakeCommandBuffer;
    private static final MethodHandle MTLCommandBufferCommit;
    private static final MethodHandle createSemaphore;
    private static final MethodHandle MTLCommandBufferCommitWithSignal;
    private static final MethodHandle semaphoreWait;
    private static final MethodHandle MTLCommandBufferIsCompleted;
    private static final MethodHandle MTLCommandBufferWaitUntilCompleted;
    private static final MethodHandle MTLCommandBufferPushDebugGroup;
    private static final MethodHandle MTLCommandBufferPopDebugGroup;
    private static final MethodHandle MTLCommandBufferMakeBlitCommandEncoder;
    private static final MethodHandle MTLCommandEncoderEndEncoding;
    private static final MethodHandle MTLBlitCommandEncoderCopyFromBufferToBuffer;
    private static final MethodHandle MTLBlitCommandEncoderCopyFromBufferToTexture;
    private static final MethodHandle MTLBlitCommandEncoderCopyFromTextureToTexture;
    private static final MethodHandle MTLBlitCommandEncoderCopyFromTextureToBuffer;
    private static final MethodHandle MTLDeviceMakeDepthStencilState;
    private static final MethodHandle MTLCommandBufferMakeRenderCommandEncoder;
    private static final MethodHandle MTLRenderCommandEncoderSetRenderPipelineState;
    private static final MethodHandle MTLRenderCommandEncoderSetDepthStencilState;
    private static final MethodHandle MTLRenderCommandEncoderSetDepthBias;
    private static final MethodHandle MTLRenderCommandEncoderSetFrontFacingWinding;
    private static final MethodHandle MTLRenderCommandEncoderSetCullMode;
    private static final MethodHandle MTLRenderCommandEncoderSetTriangleFillMode;
    private static final MethodHandle MTLRenderCommandEncoderSetBuffer;
    private static final MethodHandle MTLRenderCommandEncoderSetBufferOffset;
    private static final MethodHandle MTLRenderCommandEncoderSetTexture;
    private static final MethodHandle MTLRenderCommandEncoderSetTextureAndSampler;
    private static final MethodHandle MTLRenderCommandEncoderSetScissorRect;
    private static final MethodHandle MTLRenderCommandEncoderClearDraw;
    private static final MethodHandle MTLRenderCommandEncoderDrawPrimitives;
    private static final MethodHandle MTLRenderCommandEncoderDrawIndexedPrimitives;
    private static final MethodHandle MTLRenderCommandEncoderMultiDrawIndexed;
    private static final MethodHandle MTLRenderCommandEncoderMultiDrawIndexedFull;
    private static final MethodHandle MTLRenderCommandEncoderDrawIndexedPrimitivesTriangleFan;
    private static final MethodHandle MTLRenderCommandEncoderDrawIndexedPrimitivesIndirect;
    private static final MethodHandle MTLRenderCommandEncoderDrawPrimitivesIndirect;
    private static final MethodHandle MTLCommandBufferClearColorDepthTexturesRegion;
    private static final MethodHandle MTLCommandBufferEncodePresentTextureToDrawable;
    private static final MethodHandle createBuffer;
    private static final MethodHandle createTexture2d;
    private static final MethodHandle createTextureView;
    private static final MethodHandle createBufferTextureView;
    private static final MethodHandle createSampler;
    private static final MethodHandle MTLVertexDescriptorCreate;
    private static final MethodHandle MTLVertexDescriptorSetAttribute;
    private static final MethodHandle MTLVertexDescriptorSetLayout;
    private static final MethodHandle MTLRenderPipelineDescriptorCreate;
    private static final MethodHandle createShaderFunction;
    private static final MethodHandle MTLRenderPipelineDescriptorSetCompiledFunctions;
    private static final MethodHandle MTLRenderPipelineDescriptorSetVertexDescriptor;
    private static final MethodHandle MTLRenderPipelineDescriptorSetAttachmentFormats;
    private static final MethodHandle MTLRenderPipelineDescriptorSetBlendState;
    private static final MethodHandle MTLDeviceMakeRenderPipelineState;
    private static final MethodHandle configureLayer;
    private static final MethodHandle releaseObject;
    private static final MethodHandle getBufferContents;
    private static final MethodHandle createFence;
    private static final MethodHandle MTLRenderCommandEncoderUpdateFence;
    private static final MethodHandle MTLRenderCommandEncoderWaitForFence;
    private static final MethodHandle MTLBlitCommandEncoderUpdateFence;
    private static final MethodHandle MTLBlitCommandEncoderWaitForFence;
    private static final MethodHandle initPipelines;
    private static final MethodHandle iosFindSurfaceView;
    private static final MethodHandle iosGetViewMetalLayer;

    public static boolean isIOS() {
        String osName = System.getProperty("os.name", "");
        String osArch = System.getProperty("os.arch", "");
        if (osName.toLowerCase().contains("ios")) {
            return true;
        }
        if (System.getProperty("pojav.launcher") != null || System.getProperty("org.pojavlauncher") != null) {
            return true;
        }
        String tmpDir = System.getProperty("java.io.tmpdir", "");
        String userHome = System.getProperty("user.home", "");
        if (tmpDir.contains("/var/mobile/") || tmpDir.contains("/var/containers/") || userHome.contains("/var/mobile/") || userHome.contains("/var/containers/")) {
            return true;
        }
        return osName.toLowerCase().contains("darwin") && osArch.toLowerCase().contains("aarch64") && !osName.toLowerCase().contains("mac");
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    public static void ensureSpvcLibraryConfigured() {
        if (spvcConfigured) {
            return;
        }
        Class<MetalNativeBridge> clazz = MetalNativeBridge.class;
        synchronized (MetalNativeBridge.class) {
            if (spvcConfigured) {
                // ** MonitorExit[var0] (shouldn't be in output)
                return;
            }
            if (!MetalNativeBridge.isIOS()) {
                spvcConfigured = true;
                // ** MonitorExit[var0] (shouldn't be in output)
                return;
            }
            try {
                MetalNativeBridge.configureBundledSpvcLibrary();
            }
            catch (Throwable throwable) {
            }
            finally {
                spvcConfigured = true;
            }
            // ** MonitorExit[var0] (shouldn't be in output)
            return;
        }
    }

    private static void configureBundledSpvcLibrary() throws IOException {
        String resourcePath = "/natives/ios/libspvc.dylib";
        try (InputStream stream = MetalNativeBridge.class.getResourceAsStream(resourcePath);){
            if (stream == null) {
                return;
            }
            Path tempLib = null;
            IOException lastError = null;
            for (String dirProperty : new String[]{"pojav.launcher.home", "POJAV_HOME", "user.home", "java.io.tmpdir"}) {
                Path dirPath;
                String dir = System.getProperty(dirProperty);
                if (dir == null || dir.isBlank() || !Files.isDirectory(dirPath = Path.of((String)dir, (String[])new String[0]), new LinkOption[0])) continue;
                try {
                    tempLib = dirPath.resolve("libspvc_metallum.dylib");
                    Files.copy(stream, tempLib, StandardCopyOption.REPLACE_EXISTING);
                    break;
                }
                catch (IOException e) {
                    lastError = e;
                    tempLib = null;
                }
            }
            if (tempLib == null) {
                if (lastError != null) {
                    throw lastError;
                }
                throw new IOException("No writable directory available for libspvc.dylib extraction");
            }
            tempLib.toFile().deleteOnExit();
            System.load(tempLib.toString());
            Configuration.SPVC_LIBRARY_NAME.set((Object)tempLib.toString());
        }
    }

    private static SymbolLookup createSymbolLookup() throws IOException {
        if (MetalNativeBridge.isIOS()) {
            return MetalNativeBridge.createIOSSymbolLookup();
        }
        return MetalNativeBridge.extractAndLoad(MACOS_RESOURCE_PATH);
    }

    private static SymbolLookup createIOSSymbolLookup() throws IOException {
        try {
            System.loadLibrary("metallum");
        }
        catch (UnsatisfiedLinkError first) {
            try {
                System.loadLibrary("metallum_native");
            }
            catch (UnsatisfiedLinkError unsatisfiedLinkError) {
                // empty catch block
            }
        }
        SymbolLookup loader = SymbolLookup.loaderLookup();
        if (loader.find("metallum_create_system_default_device").isPresent()) {
            return loader;
        }
        Throwable lastError = null;
        for (String dirProperty : new String[]{"pojav.launcher.home", "POJAV_HOME", "user.home", "java.io.tmpdir"}) {
            Path dirPath;
            String dir = System.getProperty(dirProperty);
            if (dir == null || dir.isEmpty() || !Files.isDirectory(dirPath = Path.of((String)dir, (String[])new String[0]), new LinkOption[0])) continue;
            try {
                Path lib = dirPath.resolve("libmetallum.dylib");
                try (InputStream stream = MetalNativeBridge.class.getResourceAsStream(IOS_RESOURCE_PATH);){
                    if (stream == null) {
                        throw new IllegalStateException("Missing native library resource: /natives/ios/libmetallum.dylib");
                    }
                    Files.copy(stream, lib, StandardCopyOption.REPLACE_EXISTING);
                }
                lib.toFile().deleteOnExit();
                System.load(lib.toString());
                loader = SymbolLookup.loaderLookup();
                if (!loader.find("metallum_create_system_default_device").isPresent()) continue;
                return loader;
            }
            catch (IOException | UnsatisfiedLinkError e) {
                lastError = e instanceof UnsatisfiedLinkError ? (UnsatisfiedLinkError)e : null;
            }
        }
        throw new IllegalStateException("Could not load the Metallum native bridge on iOS.\nTried: System.loadLibrary (Frameworks/), System.load from\n$POJAV_HOME / $HOME / $TMPDIR \u2014 all failed.\n" + (String)(lastError != null ? "Last loader error: " + lastError.getMessage() + "\n" : "") + "\nThe iOS dylib must either:\n  (a) be embedded in the Amethyst app bundle at\n      <Amethyst.app>/Frameworks/libmetallum.dylib and signed at\n      IPA build time (the supported path \u2014 Amethyst loads all its\n      natives this way via java.library.path); OR\n  (b) the device must have JIT enabled (TrollStore / jailbreak)\n      so Amethyst's dyld library-validation bypass can load the\n      unsigned dylib extracted from the jar.\nSee README.md -> iOS Installation for details.", lastError);
    }

    private static SymbolLookup extractAndLoad(String resourcePath) throws IOException {
        Path tempLib = Files.createTempFile("metallum-native-", ".dylib", new FileAttribute[0]);
        tempLib.toFile().deleteOnExit();
        try (InputStream stream = MetalNativeBridge.class.getResourceAsStream(resourcePath);){
            if (stream == null) {
                throw new IllegalStateException("Missing native library resource: " + resourcePath);
            }
            Files.copy(stream, tempLib, StandardCopyOption.REPLACE_EXISTING);
        }
        return SymbolLookup.libraryLookup((Path)tempLib, (Arena)Arena.global());
    }

    private static MethodHandle downcall(SymbolLookup lookup, String symbol, FunctionDescriptor descriptor) {
        return LINKER.downcallHandle(lookup.findOrThrow(symbol), descriptor, new Linker.Option[]{Linker.Option.critical((boolean)false)});
    }

    private static MethodHandle downcallWithoutCritical(SymbolLookup lookup, String symbol, FunctionDescriptor descriptor) {
        return LINKER.downcallHandle(lookup.findOrThrow(symbol), descriptor, new Linker.Option[0]);
    }

    public static MemorySegment metallum_create_system_default_device() {
        try {
            return createSystemDefaultDevice.invokeExact();
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_system_default_device", throwable);
        }
    }

    public static String metallum_copy_device_name(MemorySegment device) {
        String string;
        block8: {
            Arena arena = Arena.ofConfined();
            try {
                MemorySegment buffer = arena.allocate(256L);
                int result = copyDeviceName.invokeExact(MetalNativeBridge.segment(device), buffer, 256L);
                String string2 = string = result == 0 ? buffer.getString(0L) : "";
                if (arena == null) break block8;
            }
            catch (Throwable throwable) {
                try {
                    if (arena != null) {
                        try {
                            arena.close();
                        }
                        catch (Throwable throwable2) {
                            throwable.addSuppressed(throwable2);
                        }
                    }
                    throw throwable;
                }
                catch (Throwable throwable3) {
                    throw MetalNativeBridge.bridgeFailure("metallum_copy_device_name", throwable3);
                }
            }
            arena.close();
        }
        return string;
    }

    public static double metallum_NSWindow_backingScaleFactor(MemorySegment window) {
        try {
            return NSWindowBackingScaleFactor.invokeExact(MetalNativeBridge.segment(window));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_NSWindow_backingScaleFactor", throwable);
        }
    }

    public static MemorySegment metallum_create_metal_layer(MemorySegment device, double contentsScale) {
        try {
            return createMetalLayer.invokeExact(MetalNativeBridge.segment(device), contentsScale);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_metal_layer", throwable);
        }
    }

    public static void metallum_NSView_setMetalLayer(MemorySegment view, MemorySegment layer) {
        try {
            NSViewSetMetalLayer.invokeExact(MetalNativeBridge.segment(view), MetalNativeBridge.segment(layer));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_NSView_setMetalLayer", throwable);
        }
    }

    public static void metallum_NSView_clearLayer(MemorySegment view) {
        try {
            NSViewClearLayer.invokeExact(MetalNativeBridge.segment(view));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_NSView_clearLayer", throwable);
        }
    }

    public static MemorySegment metallum_ios_find_surface_view() {
        if (iosFindSurfaceView == null) {
            return MemorySegment.NULL;
        }
        try {
            return iosFindSurfaceView.invokeExact();
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_ios_find_surface_view", throwable);
        }
    }

    public static MemorySegment metallum_ios_get_view_metal_layer(MemorySegment view, MemorySegment device, double contentsScale) {
        if (iosGetViewMetalLayer == null) {
            return MemorySegment.NULL;
        }
        try {
            return iosGetViewMetalLayer.invokeExact(MetalNativeBridge.segment(view), MetalNativeBridge.segment(device), contentsScale);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_ios_get_view_metal_layer", throwable);
        }
    }

    public static void metallum_set_debug_labels_enabled(boolean enabled) {
        try {
            setDebugLabelsEnabled.invokeExact(enabled ? 1 : 0);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_set_debug_labels_enabled", throwable);
        }
    }

    public static void metallum_init_pipelines(MemorySegment device) {
        try {
            initPipelines.invokeExact(MetalNativeBridge.segment(device));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_init_pipelines", throwable);
        }
    }

    public static long MTLDevice_maxMemoryAllocationSize(MemorySegment device) {
        try {
            return MTLDeviceMaxMemoryAllocationSize.invokeExact(MetalNativeBridge.segment(device));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLDevice_maxMemoryAllocationSize", throwable);
        }
    }

    public static MemorySegment MTLDevice_makeCommandQueue(MemorySegment device) {
        try {
            return MTLDeviceMakeCommandQueue.invokeExact(MetalNativeBridge.segment(device));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLDevice_makeCommandQueue", throwable);
        }
    }

    public static MemorySegment MTLCommandQueue_makeCommandBuffer(MemorySegment commandQueue, String label) {
        MemorySegment memorySegment;
        block8: {
            Arena arena = Arena.ofConfined();
            try {
                memorySegment = MTLCommandQueueMakeCommandBuffer.invokeExact(MetalNativeBridge.segment(commandQueue), MetalNativeBridge.toCString(arena, label));
                if (arena == null) break block8;
            }
            catch (Throwable throwable) {
                try {
                    if (arena != null) {
                        try {
                            arena.close();
                        }
                        catch (Throwable throwable2) {
                            throwable.addSuppressed(throwable2);
                        }
                    }
                    throw throwable;
                }
                catch (Throwable throwable3) {
                    throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandQueue_makeCommandBuffer", throwable3);
                }
            }
            arena.close();
        }
        return memorySegment;
    }

    public static void MTLCommandBuffer_commit(MemorySegment commandBuffer) {
        try {
            MTLCommandBufferCommit.invokeExact(MetalNativeBridge.segment(commandBuffer));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_commit", throwable);
        }
    }

    public static MemorySegment metallum_create_semaphore() {
        try {
            return createSemaphore.invokeExact();
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_semaphore", throwable);
        }
    }

    public static void MTLCommandBuffer_commitWithSignal(MemorySegment commandBuffer, MemorySegment semaphore) {
        try {
            MTLCommandBufferCommitWithSignal.invokeExact(MetalNativeBridge.segment(commandBuffer), MetalNativeBridge.segment(semaphore));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_commitWithSignal", throwable);
        }
    }

    public static int metallum_semaphore_wait(MemorySegment semaphore, long timeoutMs) {
        try {
            return semaphoreWait.invokeExact(MetalNativeBridge.segment(semaphore), timeoutMs);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_semaphore_wait", throwable);
        }
    }

    public static int MTLCommandBuffer_isCompleted(MemorySegment commandBuffer) {
        try {
            return MTLCommandBufferIsCompleted.invokeExact(MetalNativeBridge.segment(commandBuffer));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_isCompleted", throwable);
        }
    }

    public static int MTLCommandBuffer_waitUntilCompleted(MemorySegment commandBuffer, long timeoutMs) {
        try {
            return MTLCommandBufferWaitUntilCompleted.invokeExact(MetalNativeBridge.segment(commandBuffer), timeoutMs);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_waitUntilCompleted", throwable);
        }
    }

    public static void MTLCommandBuffer_pushDebugGroup(MemorySegment commandBuffer, String label) {
        try (Arena arena = Arena.ofConfined();){
            MTLCommandBufferPushDebugGroup.invokeExact(MetalNativeBridge.segment(commandBuffer), MetalNativeBridge.toCString(arena, label));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_pushDebugGroup", throwable);
        }
    }

    public static void MTLCommandBuffer_popDebugGroup(MemorySegment commandBuffer) {
        try {
            MTLCommandBufferPopDebugGroup.invokeExact(MetalNativeBridge.segment(commandBuffer));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_popDebugGroup", throwable);
        }
    }

    public static MemorySegment MTLCommandBuffer_makeBlitCommandEncoder(MemorySegment commandBuffer) {
        try {
            return MTLCommandBufferMakeBlitCommandEncoder.invokeExact(MetalNativeBridge.segment(commandBuffer));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_makeBlitCommandEncoder", throwable);
        }
    }

    public static void MTLCommandEncoder_endEncoding(MemorySegment encoder) {
        try {
            MTLCommandEncoderEndEncoding.invokeExact(MetalNativeBridge.segment(encoder));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandEncoder_endEncoding", throwable);
        }
    }

    public static void MTLBlitCommandEncoder_copyFromBufferToBuffer(MemorySegment blitEncoder, MemorySegment sourceBuffer, long sourceOffset, MemorySegment destinationBuffer, long destinationOffset, long length) {
        try {
            MTLBlitCommandEncoderCopyFromBufferToBuffer.invokeExact(MetalNativeBridge.segment(blitEncoder), MetalNativeBridge.segment(sourceBuffer), sourceOffset, MetalNativeBridge.segment(destinationBuffer), destinationOffset, length);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLBlitCommandEncoder_copyFromBufferToBuffer", throwable);
        }
    }

    public static void MTLBlitCommandEncoder_copyFromBufferToTexture(MemorySegment blitEncoder, MemorySegment sourceBuffer, long sourceOffset, MemorySegment texture, long mipLevel, long slice, long x, long y, long width, long height, long bytesPerRow, long bytesPerImage) {
        try {
            MTLBlitCommandEncoderCopyFromBufferToTexture.invokeExact(MetalNativeBridge.segment(blitEncoder), MetalNativeBridge.segment(sourceBuffer), sourceOffset, MetalNativeBridge.segment(texture), mipLevel, slice, x, y, width, height, bytesPerRow, bytesPerImage);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLBlitCommandEncoder_copyFromBufferToTexture", throwable);
        }
    }

    public static void MTLBlitCommandEncoder_copyFromTextureToTexture(MemorySegment blitEncoder, MemorySegment sourceTexture, MemorySegment destinationTexture, long mipLevel, long sourceX, long sourceY, long destX, long destY, long width, long height) {
        try {
            MTLBlitCommandEncoderCopyFromTextureToTexture.invokeExact(MetalNativeBridge.segment(blitEncoder), MetalNativeBridge.segment(sourceTexture), MetalNativeBridge.segment(destinationTexture), mipLevel, sourceX, sourceY, destX, destY, width, height);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLBlitCommandEncoder_copyFromTextureToTexture", throwable);
        }
    }

    public static void MTLBlitCommandEncoder_copyFromTextureToBuffer(MemorySegment blitEncoder, MemorySegment sourceTexture, MemorySegment destinationBuffer, long destinationOffset, long mipLevel, long slice, long x, long y, long width, long height, long bytesPerRow, long bytesPerImage) {
        try {
            MTLBlitCommandEncoderCopyFromTextureToBuffer.invokeExact(MetalNativeBridge.segment(blitEncoder), MetalNativeBridge.segment(sourceTexture), MetalNativeBridge.segment(destinationBuffer), destinationOffset, mipLevel, slice, x, y, width, height, bytesPerRow, bytesPerImage);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLBlitCommandEncoder_copyFromTextureToBuffer", throwable);
        }
    }

    public static MemorySegment metallum_create_buffer(MemorySegment device, long length, long options) {
        try {
            return createBuffer.invokeExact(MetalNativeBridge.segment(device), length, options);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_buffer", throwable);
        }
    }

    public static MemorySegment metallum_create_texture_2d(MemorySegment device, MTLPixelFormat pixelFormat, long width, long height, long depthOrLayers, long mipLevels, long cubeCompatible, long usage, MTLStorageMode storageMode, String label) {
        MemorySegment memorySegment;
        block8: {
            Arena arena = Arena.ofConfined();
            try {
                memorySegment = createTexture2d.invokeExact(MetalNativeBridge.segment(device), pixelFormat.value, width, height, depthOrLayers, mipLevels, cubeCompatible, usage, storageMode.value, MetalNativeBridge.toCString(arena, label));
                if (arena == null) break block8;
            }
            catch (Throwable throwable) {
                try {
                    if (arena != null) {
                        try {
                            arena.close();
                        }
                        catch (Throwable throwable2) {
                            throwable.addSuppressed(throwable2);
                        }
                    }
                    throw throwable;
                }
                catch (Throwable throwable3) {
                    throw MetalNativeBridge.bridgeFailure("metallum_create_texture_2d", throwable3);
                }
            }
            arena.close();
        }
        return memorySegment;
    }

    public static MemorySegment metallum_create_texture_view(MemorySegment texture, long baseMipLevel, long mipLevelCount) {
        try {
            return createTextureView.invokeExact(MetalNativeBridge.segment(texture), baseMipLevel, mipLevelCount);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_texture_view", throwable);
        }
    }

    public static MemorySegment metallum_create_buffer_texture_view(MemorySegment buffer, long pixelFormat, long offset, long width, long height, long bytesPerRow) {
        try {
            return createBufferTextureView.invokeExact(MetalNativeBridge.segment(buffer), pixelFormat, offset, width, height, bytesPerRow);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_buffer_texture_view", throwable);
        }
    }

    public static MemorySegment metallum_create_sampler(MemorySegment device, MTLSamplerAddressMode addressModeU, MTLSamplerAddressMode addressModeV, MTLSamplerMinMagFilter minFilter, MTLSamplerMinMagFilter magFilter, MTLSamplerMipFilter mipFilter, int maxAnisotropy, double lodMaxClamp) {
        try {
            return createSampler.invokeExact(MetalNativeBridge.segment(device), addressModeU.value, addressModeV.value, minFilter.value, magFilter.value, mipFilter.value, maxAnisotropy, lodMaxClamp);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_sampler", throwable);
        }
    }

    public static MemorySegment MTLDevice_makeDepthStencilState(MemorySegment device, MTLCompareFunction depthCompareOp, int writeDepth) {
        try {
            return MTLDeviceMakeDepthStencilState.invokeExact(MetalNativeBridge.segment(device), depthCompareOp.value, writeDepth);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLDevice_makeDepthStencilState", throwable);
        }
    }

    public static MemorySegment MTLCommandBuffer_makeRenderCommandEncoder(MemorySegment commandBuffer, MemorySegment colorTexture, MemorySegment depthTexture, double viewportWidth, double viewportHeight, int clearColorEnabled, float clearColorRed, float clearColorGreen, float clearColorBlue, float clearColorAlpha, int clearDepthEnabled, double clearDepth) {
        try {
            return MTLCommandBufferMakeRenderCommandEncoder.invokeExact(MetalNativeBridge.segment(commandBuffer), MetalNativeBridge.segment(colorTexture), MetalNativeBridge.segment(depthTexture), viewportWidth, viewportHeight, clearColorEnabled, clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, clearDepthEnabled, clearDepth);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_makeRenderCommandEncoder", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_clearDraw(MemorySegment encoder, MemorySegment colorTexture, MemorySegment depthTexture, double viewportWidth, double viewportHeight, int clearColorEnabled, float clearColorRed, float clearColorGreen, float clearColorBlue, float clearColorAlpha, int clearDepthEnabled, double clearDepth) {
        try {
            MTLRenderCommandEncoderClearDraw.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(colorTexture), MetalNativeBridge.segment(depthTexture), viewportWidth, viewportHeight, clearColorEnabled, clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, clearDepthEnabled, clearDepth);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_clearDraw", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setRenderPipelineState(MemorySegment encoder, MemorySegment pipeline) {
        try {
            MTLRenderCommandEncoderSetRenderPipelineState.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(pipeline));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setRenderPipelineState", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setDepthStencilState(MemorySegment encoder, MemorySegment depthStencilState) {
        try {
            MTLRenderCommandEncoderSetDepthStencilState.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(depthStencilState));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setDepthStencilState", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setDepthBias(MemorySegment encoder, float depthBias, float slopeScale, float clamp) {
        try {
            MTLRenderCommandEncoderSetDepthBias.invokeExact(MetalNativeBridge.segment(encoder), depthBias, slopeScale, clamp);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setDepthBias", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setFrontFacingWinding(MemorySegment encoder, int clockwise) {
        try {
            MTLRenderCommandEncoderSetFrontFacingWinding.invokeExact(MetalNativeBridge.segment(encoder), clockwise);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setFrontFacingWinding", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setCullMode(MemorySegment encoder, long cullMode) {
        try {
            MTLRenderCommandEncoderSetCullMode.invokeExact(MetalNativeBridge.segment(encoder), cullMode);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setCullMode", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setTriangleFillMode(MemorySegment encoder, int lines) {
        try {
            MTLRenderCommandEncoderSetTriangleFillMode.invokeExact(MetalNativeBridge.segment(encoder), lines);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setTriangleFillMode", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setBuffer(MemorySegment encoder, MemorySegment buffer, long offset, long index, int stageMask) {
        try {
            MTLRenderCommandEncoderSetBuffer.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(buffer), offset, index, stageMask);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setBuffer", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setBufferOffset(MemorySegment encoder, long offset, long index, int stageMask) {
        try {
            MTLRenderCommandEncoderSetBufferOffset.invokeExact(MetalNativeBridge.segment(encoder), offset, index, stageMask);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setBufferOffset", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setTexture(MemorySegment encoder, MemorySegment texture, long index, int stageMask) {
        try {
            MTLRenderCommandEncoderSetTexture.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(texture), index, stageMask);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setTexture", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setTextureAndSampler(MemorySegment encoder, MemorySegment texture, MemorySegment sampler, long index, int stageMask) {
        try {
            MTLRenderCommandEncoderSetTextureAndSampler.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(texture), MetalNativeBridge.segment(sampler), index, stageMask);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setTextureAndSampler", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_setScissorRect(MemorySegment encoder, long x, long y, long width, long height) {
        try {
            MTLRenderCommandEncoderSetScissorRect.invokeExact(MetalNativeBridge.segment(encoder), x, y, width, height);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_setScissorRect", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_drawPrimitives(MemorySegment encoder, long primitiveType, long firstVertex, long vertexCount, long instanceCount, long baseInstance) {
        try {
            MTLRenderCommandEncoderDrawPrimitives.invokeExact(MetalNativeBridge.segment(encoder), primitiveType, firstVertex, vertexCount, instanceCount, baseInstance);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_drawPrimitives", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_drawIndexedPrimitives(MemorySegment encoder, long primitiveType, long indexCount, long indexType, MemorySegment indexBuffer, long indexBufferOffset, long instanceCount, long baseVertex, long baseInstance) {
        try {
            MTLRenderCommandEncoderDrawIndexedPrimitives.invokeExact(MetalNativeBridge.segment(encoder), primitiveType, indexCount, indexType, MetalNativeBridge.segment(indexBuffer), indexBufferOffset, instanceCount, baseVertex, baseInstance);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_drawIndexedPrimitives", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_multiDrawIndexed(MemorySegment encoder, long primitiveType, long indexType, MemorySegment indexBuffer, MemorySegment firstIndexOffsets, MemorySegment indexCounts, MemorySegment vertexOffsets, long drawCount, long instanceCount, long baseInstance) {
        try {
            MTLRenderCommandEncoderMultiDrawIndexed.invokeExact(MetalNativeBridge.segment(encoder), primitiveType, indexType, MetalNativeBridge.segment(indexBuffer), MetalNativeBridge.segment(firstIndexOffsets), MetalNativeBridge.segment(indexCounts), MetalNativeBridge.segment(vertexOffsets), drawCount, instanceCount, baseInstance);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_multiDrawIndexed", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_multiDrawIndexedFull(MemorySegment encoder, long primitiveType, long indexType, MemorySegment indexBuffer, MemorySegment drawParameters, long drawCount, long instanceCount, long baseInstance) {
        try {
            MTLRenderCommandEncoderMultiDrawIndexedFull.invokeExact(MetalNativeBridge.segment(encoder), primitiveType, indexType, MetalNativeBridge.segment(indexBuffer), MetalNativeBridge.segment(drawParameters), drawCount, instanceCount, baseInstance);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_multiDrawIndexedFull", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_drawIndexedPrimitivesIndirect(MemorySegment encoder, long primitiveType, long indexType, MemorySegment indexBuffer, MemorySegment indirectBuffer, long indirectBufferOffset, long drawCount, long stride) {
        try {
            MTLRenderCommandEncoderDrawIndexedPrimitivesIndirect.invokeExact(MetalNativeBridge.segment(encoder), primitiveType, indexType, MetalNativeBridge.segment(indexBuffer), MetalNativeBridge.segment(indirectBuffer), indirectBufferOffset, drawCount, stride);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_drawIndexedPrimitivesIndirect", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_drawPrimitivesIndirect(MemorySegment encoder, long primitiveType, MemorySegment indirectBuffer, long indirectBufferOffset, long drawCount, long stride) {
        try {
            MTLRenderCommandEncoderDrawPrimitivesIndirect.invokeExact(MetalNativeBridge.segment(encoder), primitiveType, MetalNativeBridge.segment(indirectBuffer), indirectBufferOffset, drawCount, stride);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_drawPrimitivesIndirect", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_drawIndexedPrimitivesTriangleFan(MemorySegment encoder, MemorySegment indexBuffer, MemorySegment fanIndexBuffer, long fanIndexBufferOffset, long indexType, long indexBufferOffset, long indexCount, long baseVertex, long instanceCount, long baseInstance) {
        try {
            MTLRenderCommandEncoderDrawIndexedPrimitivesTriangleFan.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(indexBuffer), MetalNativeBridge.segment(fanIndexBuffer), fanIndexBufferOffset, indexType, indexBufferOffset, indexCount, baseVertex, instanceCount, baseInstance);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderCommandEncoder_drawIndexedPrimitivesTriangleFan", throwable);
        }
    }

    public static void MTLCommandBuffer_clearColorDepthTexturesRegion(MemorySegment commandBuffer, MemorySegment colorTexture, float clearColorRed, float clearColorGreen, float clearColorBlue, float clearColorAlpha, MemorySegment depthTexture, double clearDepth, int x, int y, int width, int height, MemorySegment globalFence) {
        try {
            MTLCommandBufferClearColorDepthTexturesRegion.invokeExact(MetalNativeBridge.segment(commandBuffer), MetalNativeBridge.segment(colorTexture), clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, MetalNativeBridge.segment(depthTexture), clearDepth, x, y, width, height, MetalNativeBridge.segment(globalFence));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_clearColorDepthTexturesRegion", throwable);
        }
    }

    public static MemorySegment metallum_MTLVertexDescriptor_create() {
        try {
            return MTLVertexDescriptorCreate.invokeExact();
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLVertexDescriptor_create", throwable);
        }
    }

    public static void metallum_MTLVertexDescriptor_setAttribute(MemorySegment desc, long index, long format, long offset, long bufferIndex) {
        try {
            MTLVertexDescriptorSetAttribute.invokeExact(MetalNativeBridge.segment(desc), index, format, offset, bufferIndex);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLVertexDescriptor_setAttribute", throwable);
        }
    }

    public static void metallum_MTLVertexDescriptor_setLayout(MemorySegment desc, long bufferIndex, long stride, long stepFunction, long stepRate) {
        try {
            MTLVertexDescriptorSetLayout.invokeExact(MetalNativeBridge.segment(desc), bufferIndex, stride, stepFunction, stepRate);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLVertexDescriptor_setLayout", throwable);
        }
    }

    public static MemorySegment metallum_MTLRenderPipelineDescriptor_create() {
        try {
            return MTLRenderPipelineDescriptorCreate.invokeExact();
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderPipelineDescriptor_create", throwable);
        }
    }

    public static MemorySegment metallum_create_shader_function(MemorySegment device, String source, String entryPoint) {
        MemorySegment memorySegment;
        block8: {
            Arena arena = Arena.ofConfined();
            try {
                memorySegment = createShaderFunction.invokeExact(MetalNativeBridge.segment(device), MetalNativeBridge.toCString(arena, source), MetalNativeBridge.toCString(arena, entryPoint));
                if (arena == null) break block8;
            }
            catch (Throwable throwable) {
                try {
                    if (arena != null) {
                        try {
                            arena.close();
                        }
                        catch (Throwable throwable2) {
                            throwable.addSuppressed(throwable2);
                        }
                    }
                    throw throwable;
                }
                catch (Throwable throwable3) {
                    throw MetalNativeBridge.bridgeFailure("metallum_create_shader_function", throwable3);
                }
            }
            arena.close();
        }
        return memorySegment;
    }

    public static void metallum_MTLRenderPipelineDescriptor_setCompiledFunctions(MemorySegment desc, MemorySegment vertexFunction, MemorySegment fragmentFunction) {
        try {
            MTLRenderPipelineDescriptorSetCompiledFunctions.invokeExact(MetalNativeBridge.segment(desc), MetalNativeBridge.segment(vertexFunction), MetalNativeBridge.segment(fragmentFunction));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderPipelineDescriptor_setCompiledFunctions", throwable);
        }
    }

    public static void metallum_MTLRenderPipelineDescriptor_setVertexDescriptor(MemorySegment desc, MemorySegment vertexDesc) {
        try {
            MTLRenderPipelineDescriptorSetVertexDescriptor.invokeExact(MetalNativeBridge.segment(desc), MetalNativeBridge.segment(vertexDesc));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderPipelineDescriptor_setVertexDescriptor", throwable);
        }
    }

    public static void metallum_MTLRenderPipelineDescriptor_setAttachmentFormats(MemorySegment desc, MTLPixelFormat colorFormat, MTLPixelFormat depthFormat, MTLPixelFormat stencilFormat) {
        try {
            MTLRenderPipelineDescriptorSetAttachmentFormats.invokeExact(MetalNativeBridge.segment(desc), colorFormat.value, depthFormat.value, stencilFormat.value);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderPipelineDescriptor_setAttachmentFormats", throwable);
        }
    }

    public static void metallum_MTLRenderPipelineDescriptor_setBlendState(MemorySegment desc, int enabled, long srcRgb, long dstRgb, long opRgb, long srcAlpha, long dstAlpha, long opAlpha, long writeMask) {
        try {
            MTLRenderPipelineDescriptorSetBlendState.invokeExact(MetalNativeBridge.segment(desc), enabled, srcRgb, dstRgb, opRgb, srcAlpha, dstAlpha, opAlpha, writeMask);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLRenderPipelineDescriptor_setBlendState", throwable);
        }
    }

    public static MemorySegment metallum_MTLDevice_makeRenderPipelineState(MemorySegment device, MemorySegment descriptor) {
        try {
            return MTLDeviceMakeRenderPipelineState.invokeExact(MetalNativeBridge.segment(device), MetalNativeBridge.segment(descriptor));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLDevice_makeRenderPipelineState", throwable);
        }
    }

    public static void metallum_configure_layer(MemorySegment layer, double width, double height, int immediatePresentMode) {
        try {
            configureLayer.invokeExact(MetalNativeBridge.segment(layer), width, height, immediatePresentMode);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_configure_layer", throwable);
        }
    }

    public static void MTLCommandBuffer_encodePresentTextureToDrawable(MemorySegment commandBuffer, MemorySegment layer, MemorySegment sourceTexture, MemorySegment globalFence) {
        try {
            MTLCommandBufferEncodePresentTextureToDrawable.invokeExact(MetalNativeBridge.segment(commandBuffer), MetalNativeBridge.segment(layer), MetalNativeBridge.segment(sourceTexture), MetalNativeBridge.segment(globalFence));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_MTLCommandBuffer_encodePresentTextureToDrawable", throwable);
        }
    }

    public static void metallum_release_object(MemorySegment object) {
        try {
            releaseObject.invokeExact(MetalNativeBridge.segment(object));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_release_object", throwable);
        }
    }

    public static MemorySegment metallum_create_fence(MemorySegment device) {
        try {
            return createFence.invokeExact(MetalNativeBridge.segment(device));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_create_fence", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_updateFence(MemorySegment encoder, MemorySegment fence, long stages) {
        try {
            MTLRenderCommandEncoderUpdateFence.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(fence), stages);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("MTLRenderCommandEncoder_updateFence", throwable);
        }
    }

    public static void MTLRenderCommandEncoder_waitForFence(MemorySegment encoder, MemorySegment fence, long stages) {
        try {
            MTLRenderCommandEncoderWaitForFence.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(fence), stages);
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("MTLRenderCommandEncoder_waitForFence", throwable);
        }
    }

    public static void MTLBlitCommandEncoder_updateFence(MemorySegment encoder, MemorySegment fence) {
        try {
            MTLBlitCommandEncoderUpdateFence.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(fence));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("MTLBlitCommandEncoder_updateFence", throwable);
        }
    }

    public static void MTLBlitCommandEncoder_waitForFence(MemorySegment encoder, MemorySegment fence) {
        try {
            MTLBlitCommandEncoderWaitForFence.invokeExact(MetalNativeBridge.segment(encoder), MetalNativeBridge.segment(fence));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("MTLBlitCommandEncoder_waitForFence", throwable);
        }
    }

    public static MemorySegment metallum_get_buffer_contents(MemorySegment buffer) {
        try {
            return getBufferContents.invokeExact(MetalNativeBridge.segment(buffer));
        }
        catch (Throwable throwable) {
            throw MetalNativeBridge.bridgeFailure("metallum_get_buffer_contents", throwable);
        }
    }

    public static ByteBuffer nativeByteBufferView(MemorySegment pointer, long byteSize) {
        if (pointer == null || pointer.address() == 0L) {
            throw new IllegalArgumentException("Cannot create a ByteBuffer view for a null native pointer");
        }
        if (byteSize < 0L) {
            throw new IllegalArgumentException("Byte size must be non-negative");
        }
        return MemorySegment.ofAddress((long)pointer.address()).reinterpret(byteSize).asByteBuffer();
    }

    private static MemorySegment segment(MemorySegment pointer) {
        return pointer == null || pointer.address() == 0L ? MemorySegment.NULL : pointer;
    }

    private static MemorySegment toCString(Arena arena, String value) {
        return value == null ? MemorySegment.NULL : arena.allocateFrom(value);
    }

    public static boolean isNullHandle(@Nullable MemorySegment pointer) {
        return pointer == null || pointer.address() == 0L;
    }

    private static RuntimeException bridgeFailure(String symbol, Throwable throwable) {
        return new IllegalStateException("Native bridge call failed: " + symbol, throwable);
    }

    static {
        try {
            SymbolLookup lookup = MetalNativeBridge.createSymbolLookup();
            createSystemDefaultDevice = MetalNativeBridge.downcall(lookup, "metallum_create_system_default_device", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[0]));
            copyDeviceName = MetalNativeBridge.downcall(lookup, "metallum_copy_device_name", FunctionDescriptor.of((MemoryLayout)INT, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG}));
            NSWindowBackingScaleFactor = MetalNativeBridge.downcall(lookup, "metallum_NSWindow_backingScaleFactor", FunctionDescriptor.of((MemoryLayout)DOUBLE, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            createMetalLayer = MetalNativeBridge.downcall(lookup, "metallum_create_metal_layer", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, DOUBLE}));
            NSViewSetMetalLayer = MetalNativeBridge.downcall(lookup, "metallum_NSView_setMetalLayer", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            NSViewClearLayer = MetalNativeBridge.downcall(lookup, "metallum_NSView_clearLayer", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            setDebugLabelsEnabled = MetalNativeBridge.downcall(lookup, "metallum_set_debug_labels_enabled", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{INT}));
            initPipelines = MetalNativeBridge.downcall(lookup, "metallum_init_pipelines", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLDeviceMaxMemoryAllocationSize = MetalNativeBridge.downcall(lookup, "metallum_MTLDevice_maxMemoryAllocationSize", FunctionDescriptor.of((MemoryLayout)LONG, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLDeviceMakeCommandQueue = MetalNativeBridge.downcall(lookup, "metallum_MTLDevice_makeCommandQueue", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLCommandQueueMakeCommandBuffer = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandQueue_makeCommandBuffer", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLCommandBufferCommit = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_commit", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            createSemaphore = MetalNativeBridge.downcall(lookup, "metallum_create_semaphore", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[0]));
            MTLCommandBufferCommitWithSignal = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_commitWithSignal", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            semaphoreWait = MetalNativeBridge.downcallWithoutCritical(lookup, "metallum_semaphore_wait", FunctionDescriptor.of((MemoryLayout)INT, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG}));
            MTLCommandBufferIsCompleted = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_isCompleted", FunctionDescriptor.of((MemoryLayout)INT, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLCommandBufferWaitUntilCompleted = MetalNativeBridge.downcallWithoutCritical(lookup, "metallum_MTLCommandBuffer_waitUntilCompleted", FunctionDescriptor.of((MemoryLayout)INT, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG}));
            MTLCommandBufferPushDebugGroup = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_pushDebugGroup", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLCommandBufferPopDebugGroup = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_popDebugGroup", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLCommandBufferMakeBlitCommandEncoder = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_makeBlitCommandEncoder", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLCommandEncoderEndEncoding = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandEncoder_endEncoding", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLBlitCommandEncoderCopyFromBufferToBuffer = MetalNativeBridge.downcall(lookup, "metallum_MTLBlitCommandEncoder_copyFromBufferToBuffer", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, ValueLayout.ADDRESS, LONG, LONG}));
            MTLBlitCommandEncoderCopyFromBufferToTexture = MetalNativeBridge.downcall(lookup, "metallum_MTLBlitCommandEncoder_copyFromBufferToTexture", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG, LONG, LONG, LONG}));
            MTLBlitCommandEncoderCopyFromTextureToTexture = MetalNativeBridge.downcall(lookup, "metallum_MTLBlitCommandEncoder_copyFromTextureToTexture", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG, LONG, LONG}));
            MTLBlitCommandEncoderCopyFromTextureToBuffer = MetalNativeBridge.downcall(lookup, "metallum_MTLBlitCommandEncoder_copyFromTextureToBuffer", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG, LONG, LONG, LONG, LONG}));
            MTLDeviceMakeDepthStencilState = MetalNativeBridge.downcall(lookup, "metallum_MTLDevice_makeDepthStencilState", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, INT}));
            MTLCommandBufferMakeRenderCommandEncoder = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_makeRenderCommandEncoder", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, DOUBLE, DOUBLE, INT, FLOAT, FLOAT, FLOAT, FLOAT, INT, DOUBLE}));
            MTLRenderCommandEncoderSetRenderPipelineState = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setRenderPipelineState", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLRenderCommandEncoderSetDepthStencilState = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setDepthStencilState", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLRenderCommandEncoderSetDepthBias = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setDepthBias", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, FLOAT, FLOAT, FLOAT}));
            MTLRenderCommandEncoderSetFrontFacingWinding = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setFrontFacingWinding", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, INT}));
            MTLRenderCommandEncoderSetCullMode = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setCullMode", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG}));
            MTLRenderCommandEncoderSetTriangleFillMode = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setTriangleFillMode", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, INT}));
            MTLRenderCommandEncoderSetBuffer = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setBuffer", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, LONG, INT}));
            MTLRenderCommandEncoderSetBufferOffset = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setBufferOffset", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, INT}));
            MTLRenderCommandEncoderSetTexture = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setTexture", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, INT}));
            MTLRenderCommandEncoderSetTextureAndSampler = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setTextureAndSampler", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, INT}));
            MTLRenderCommandEncoderSetScissorRect = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_setScissorRect", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, LONG}));
            MTLRenderCommandEncoderClearDraw = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_clearDraw", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, DOUBLE, DOUBLE, INT, FLOAT, FLOAT, FLOAT, FLOAT, INT, DOUBLE}));
            MTLRenderCommandEncoderDrawPrimitives = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_drawPrimitives", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG}));
            MTLRenderCommandEncoderDrawIndexedPrimitives = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_drawIndexedPrimitives", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, ValueLayout.ADDRESS, LONG, LONG, LONG, LONG}));
            MTLRenderCommandEncoderMultiDrawIndexed = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_multiDrawIndexed", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, LONG, LONG}));
            MTLRenderCommandEncoderMultiDrawIndexedFull = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_multiDrawIndexedFull", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, LONG, LONG}));
            MTLRenderCommandEncoderDrawIndexedPrimitivesIndirect = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_drawIndexedPrimitivesIndirect", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, LONG, LONG}));
            MTLRenderCommandEncoderDrawPrimitivesIndirect = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderCommandEncoder_drawPrimitivesIndirect", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, ValueLayout.ADDRESS, LONG, LONG, LONG}));
            MTLRenderCommandEncoderDrawIndexedPrimitivesTriangleFan = MetalNativeBridge.downcallWithoutCritical(lookup, "metallum_MTLRenderCommandEncoder_drawIndexedPrimitivesTriangleFan", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG, LONG, LONG}));
            MTLCommandBufferClearColorDepthTexturesRegion = MetalNativeBridge.downcall(lookup, "metallum_MTLCommandBuffer_clearColorDepthTexturesRegion", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, FLOAT, FLOAT, FLOAT, FLOAT, ValueLayout.ADDRESS, DOUBLE, INT, INT, INT, INT, ValueLayout.ADDRESS}));
            MTLCommandBufferEncodePresentTextureToDrawable = MetalNativeBridge.downcallWithoutCritical(lookup, "metallum_MTLCommandBuffer_encodePresentTextureToDrawable", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            createBuffer = MetalNativeBridge.downcall(lookup, "metallum_create_buffer", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG}));
            createTexture2d = MetalNativeBridge.downcall(lookup, "metallum_create_texture_2d", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG, LONG, LONG, LONG, ValueLayout.ADDRESS}));
            createTextureView = MetalNativeBridge.downcall(lookup, "metallum_create_texture_view", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG}));
            createBufferTextureView = MetalNativeBridge.downcall(lookup, "metallum_create_buffer_texture_view", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG}));
            createSampler = MetalNativeBridge.downcall(lookup, "metallum_create_sampler", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, LONG, LONG, INT, DOUBLE}));
            MTLVertexDescriptorCreate = MetalNativeBridge.downcall(lookup, "metallum_MTLVertexDescriptor_create", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[0]));
            MTLVertexDescriptorSetAttribute = MetalNativeBridge.downcall(lookup, "metallum_MTLVertexDescriptor_setAttribute", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, LONG}));
            MTLVertexDescriptorSetLayout = MetalNativeBridge.downcall(lookup, "metallum_MTLVertexDescriptor_setLayout", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG, LONG}));
            MTLRenderPipelineDescriptorCreate = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderPipelineDescriptor_create", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[0]));
            createShaderFunction = MetalNativeBridge.downcallWithoutCritical(lookup, "metallum_create_shader_function", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLRenderPipelineDescriptorSetCompiledFunctions = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderPipelineDescriptor_setCompiledFunctions", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLRenderPipelineDescriptorSetVertexDescriptor = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderPipelineDescriptor_setVertexDescriptor", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLRenderPipelineDescriptorSetAttachmentFormats = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderPipelineDescriptor_setAttachmentFormats", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, LONG, LONG, LONG}));
            MTLRenderPipelineDescriptorSetBlendState = MetalNativeBridge.downcall(lookup, "metallum_MTLRenderPipelineDescriptor_setBlendState", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, INT, LONG, LONG, LONG, LONG, LONG, LONG, LONG}));
            MTLDeviceMakeRenderPipelineState = MetalNativeBridge.downcall(lookup, "metallum_MTLDevice_makeRenderPipelineState", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            configureLayer = MetalNativeBridge.downcall(lookup, "metallum_configure_layer", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, DOUBLE, DOUBLE, INT}));
            releaseObject = MetalNativeBridge.downcall(lookup, "metallum_release_object", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            getBufferContents = MetalNativeBridge.downcall(lookup, "metallum_get_buffer_contents", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            createFence = MetalNativeBridge.downcall(lookup, "metallum_create_fence", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS}));
            MTLRenderCommandEncoderUpdateFence = MetalNativeBridge.downcall(lookup, "MTLRenderCommandEncoder_updateFence", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG}));
            MTLRenderCommandEncoderWaitForFence = MetalNativeBridge.downcallWithoutCritical(lookup, "MTLRenderCommandEncoder_waitForFence", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, LONG}));
            MTLBlitCommandEncoderUpdateFence = MetalNativeBridge.downcall(lookup, "MTLBlitCommandEncoder_updateFence", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            MTLBlitCommandEncoderWaitForFence = MetalNativeBridge.downcallWithoutCritical(lookup, "MTLBlitCommandEncoder_waitForFence", FunctionDescriptor.ofVoid((MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS}));
            iosFindSurfaceView = MetalNativeBridge.isIOS() && lookup.find("metallum_ios_find_surface_view").isPresent() ? MetalNativeBridge.downcall(lookup, "metallum_ios_find_surface_view", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[0])) : null;
            iosGetViewMetalLayer = MetalNativeBridge.isIOS() && lookup.find("metallum_ios_get_view_metal_layer").isPresent() ? MetalNativeBridge.downcall(lookup, "metallum_ios_get_view_metal_layer", FunctionDescriptor.of((MemoryLayout)ValueLayout.ADDRESS, (MemoryLayout[])new MemoryLayout[]{ValueLayout.ADDRESS, ValueLayout.ADDRESS, DOUBLE})) : null;
        }
        catch (IOException e) {
            throw new IllegalStateException("Failed to load Metal native bridge", e);
        }
    }
}

