/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.RenderPassDescriptor
 *  com.mojang.renderpearl.api.textures.GpuTexture
 *  com.mojang.renderpearl.api.textures.GpuTextureView
 */
package com.metallum.shims;

import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;
import java.util.function.Supplier;

public class RenderPassDescriptor {
    public String name;
    public GpuTextureView color;
    public GpuTexture depth;
    public int width;
    public int height;
    public Supplier<String> label;
}

