/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.systems.CommandEncoderBackend
 *  com.mojang.blaze3d.systems.GpuSurface$Configuration
 *  com.mojang.blaze3d.systems.GpuSurface$PresentMode
 *  com.mojang.blaze3d.systems.GpuSurfaceBackend
 *  com.mojang.blaze3d.systems.SurfaceException
 *  com.mojang.blaze3d.textures.GpuTextureView
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.NonNull
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.mojang.blaze3d.systems.CommandEncoderBackend;
import com.mojang.blaze3d.systems.GpuSurface;
import com.mojang.blaze3d.systems.GpuSurfaceBackend;
import com.mojang.blaze3d.systems.SurfaceException;
import com.mojang.blaze3d.textures.GpuTextureView;
import java.lang.foreign.MemorySegment;
import java.util.Collection;
import java.util.EnumSet;
import java.util.Set;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.NonNull;

@Environment(value=EnvType.CLIENT)
final class MetalSurface
implements GpuSurfaceBackend {
    private static final Set<GpuSurface.PresentMode> SUPPORTED_PRESENT_MODES = EnumSet.of(GpuSurface.PresentMode.FIFO, GpuSurface.PresentMode.MAILBOX);
    private final MetalDevice device;
    private final MemorySegment metalLayer;
    private GpuSurface.Configuration configuration;
    private MetalCommandEncoder pendingPresentEncoder;

    MetalSurface(MetalDevice device, MemorySegment metalLayer) {
        this.device = device;
        this.metalLayer = metalLayer;
    }

    public void configure(GpuSurface.Configuration config) throws SurfaceException {
        if (config.width() <= 0 || config.height() <= 0) {
            throw new SurfaceException("Metal surface configuration must be positive, got " + config.width() + "x" + config.height());
        }
        MetalNativeBridge.metallum_configure_layer(this.metalLayer, config.width(), config.height(), config.presentMode() == GpuSurface.PresentMode.MAILBOX ? 1 : 0);
        this.configuration = config;
    }

    public boolean isSuboptimal() {
        return false;
    }

    public void acquireNextTexture() {
    }

    public void blitFromTexture(@NonNull CommandEncoderBackend commandEncoder, @NonNull GpuTextureView textureView) {
        if (!(commandEncoder instanceof MetalCommandEncoder)) {
            throw new IllegalArgumentException("Metal surface requires MetalCommandEncoder");
        }
        MetalCommandEncoder metalEncoder = (MetalCommandEncoder)commandEncoder;
        metalEncoder.presentTextureToDrawable(this.metalLayer, textureView);
        this.pendingPresentEncoder = metalEncoder;
    }

    public void present() {
        this.pendingPresentEncoder.submit();
    }

    public void close() {
    }

    public @NonNull Collection<// Could not load outer class - annotation placement on inner may be incorrect
    GpuSurface.PresentMode> supportedPresentModes() {
        return SUPPORTED_PRESENT_MODES;
    }
}

