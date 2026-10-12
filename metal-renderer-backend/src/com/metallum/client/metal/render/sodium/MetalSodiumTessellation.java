/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.MetalSodiumCommandList
 *  com.metallum.client.metal.render.sodium.MetalSodiumTessellation
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBuffer
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferTarget
 *  net.caffeinemc.mods.sodium.client.gl.device.CommandList
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.GlPrimitiveType
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.GlTessellation
 *  net.caffeinemc.mods.sodium.client.gl.tessellation.TessellationBinding
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.sodium.MetalSodiumCommandList;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBuffer;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBufferTarget;
import net.caffeinemc.mods.sodium.client.gl.device.CommandList;
import net.caffeinemc.mods.sodium.client.gl.tessellation.GlPrimitiveType;
import net.caffeinemc.mods.sodium.client.gl.tessellation.GlTessellation;
import net.caffeinemc.mods.sodium.client.gl.tessellation.TessellationBinding;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.jspecify.annotations.Nullable;

@Environment(value=EnvType.CLIENT)
public final class MetalSodiumTessellation
implements GlTessellation {
    private final GlPrimitiveType primitiveType;
    private final MetalGpuBuffer vertexBuffer;
    private final @Nullable MetalGpuBuffer indexBuffer;

    MetalSodiumTessellation(GlPrimitiveType primitiveType, TessellationBinding[] bindings) {
        this.primitiveType = primitiveType;
        MetalGpuBuffer vertex = null;
        MetalGpuBuffer index = null;
        for (TessellationBinding binding : bindings) {
            MetalGpuBuffer metal = MetalSodiumCommandList.requireBuffer((GlBuffer)binding.buffer());
            if (binding.target() == GlBufferTarget.ARRAY_BUFFER) {
                vertex = metal;
                continue;
            }
            if (binding.target() != GlBufferTarget.ELEMENT_BUFFER) continue;
            index = metal;
        }
        if (vertex == null) {
            throw new IllegalStateException("Sodium tessellation missing vertex buffer binding");
        }
        this.vertexBuffer = vertex;
        this.indexBuffer = index;
    }

    public MetalGpuBuffer vertexBuffer() {
        return this.vertexBuffer;
    }

    public @Nullable MetalGpuBuffer indexBuffer() {
        return this.indexBuffer;
    }

    public GlPrimitiveType getPrimitiveType() {
        return this.primitiveType;
    }

    public void bind(CommandList commandList) {
    }

    public void unbind(CommandList commandList) {
    }

    public void delete(CommandList commandList) {
    }
}

