/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.RenderArea
 *  com.mojang.renderpearl.api.textures.GpuTextureView
 */
package com.metallum.shims;

import com.mojang.renderpearl.api.textures.GpuTextureView;

public class RenderArea {
    private final int x;
    private final int y;
    private final int width;
    private final int height;

    public RenderArea(int n, int n2, int n3, int n4) {
        this.x = n;
        this.y = n2;
        this.width = n3;
        this.height = n4;
    }

    public int x() {
        return this.x;
    }

    public int y() {
        return this.y;
    }

    public int width() {
        return this.width;
    }

    public int height() {
        return this.height;
    }

    public boolean fillsTexture(GpuTextureView gpuTextureView) {
        return this.x == 0 && this.y == 0 && this.width == gpuTextureView.getWidth(0) && this.height == gpuTextureView.getHeight(0);
    }
}

