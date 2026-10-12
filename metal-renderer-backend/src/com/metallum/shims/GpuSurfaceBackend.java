/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.GpuSurface$Configuration
 *  com.metallum.shims.GpuSurface$PresentMode
 *  com.metallum.shims.GpuSurfaceBackend
 *  com.metallum.shims.SurfaceException
 *  com.mojang.renderpearl.api.textures.GpuTextureView
 *  com.mojang.renderpearl.backend.api.CommandEncoderBackend
 *  org.jspecify.annotations.NonNull
 */
package com.metallum.shims;

import com.metallum.shims.GpuSurface;
import com.metallum.shims.SurfaceException;
import com.mojang.renderpearl.api.textures.GpuTextureView;
import com.mojang.renderpearl.backend.api.CommandEncoderBackend;
import java.util.Collection;
import org.jspecify.annotations.NonNull;

public interface GpuSurfaceBackend
extends AutoCloseable {
    public void configure(GpuSurface.Configuration var1) throws SurfaceException;

    public boolean isSuboptimal();

    public void acquireNextTexture();

    public void blitFromTexture(@NonNull CommandEncoderBackend var1, @NonNull GpuTextureView var2);

    public void present();

    @Override
    public void close();

    public @NonNull Collection<// Could not load outer class - annotation placement on inner may be incorrect
    GpuSurface.PresentMode> supportedPresentModes();
}

