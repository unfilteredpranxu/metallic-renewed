/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.MetalRenderPass
 *  com.mojang.blaze3d.buffers.GpuBufferSlice
 *  com.mojang.blaze3d.buffers.GpuBufferSlice$MappedView
 *  com.mojang.blaze3d.pipeline.RenderPipeline
 *  com.mojang.blaze3d.systems.RenderPass
 *  net.caffeinemc.mods.sodium.client.gpu.device.context.VKIndirectContext
 *  net.caffeinemc.mods.sodium.client.render.chunk.region.RenderRegion
 *  net.caffeinemc.mods.sodium.client.render.viewport.CameraTransform
 *  net.caffeinemc.mods.sodium.mixin.core.RenderPassAccessor
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalRenderPass;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.systems.RenderPass;
import java.nio.ByteBuffer;
import net.caffeinemc.mods.sodium.client.gpu.device.context.VKIndirectContext;
import net.caffeinemc.mods.sodium.client.render.chunk.region.RenderRegion;
import net.caffeinemc.mods.sodium.client.render.viewport.CameraTransform;
import net.caffeinemc.mods.sodium.mixin.core.RenderPassAccessor;

public final class MetalDrawContext
extends VKIndirectContext {
    private MetalRenderPass metalPass;

    public void setContext(RenderPass pass, RenderPipeline pipeline) {
        this.pass = pass;
        this.metalPass = (MetalRenderPass)((RenderPassAccessor)pass).getBackend();
    }

    public void updateData(RenderRegion region, CameraTransform camera) {
        GpuBufferSlice pushConstantsBufferSlice;
        float x = MetalDrawContext.getCameraTranslation((int)region.getOriginX(), (int)camera.intX, (float)camera.fracX);
        float y = MetalDrawContext.getCameraTranslation((int)region.getOriginY(), (int)camera.intY, (float)camera.fracY);
        float z = MetalDrawContext.getCameraTranslation((int)region.getOriginZ(), (int)camera.intZ, (float)camera.fracZ);
        try (GpuBufferSlice.MappedView mapped = this.metalPass.allocateTransient(20L, 4L, 128);){
            ByteBuffer data = mapped.data();
            data.putFloat(0, x);
            data.putFloat(4, y);
            data.putFloat(8, z);
            data.putInt(12, Math.toIntExact(System.currentTimeMillis() - region.getCreationTime()));
            data.putInt(16, region.getId());
            pushConstantsBufferSlice = mapped.slice();
        }
        this.metalPass.setUniform("push_constants", pushConstantsBufferSlice);
    }
}

