/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.MetalFakeGlProgram
 *  net.caffeinemc.mods.sodium.client.gl.shader.GlProgram
 *  net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.sodium;

import net.caffeinemc.mods.sodium.client.gl.shader.GlProgram;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
final class MetalFakeGlProgram
extends GlProgram<ChunkShaderInterface> {
    MetalFakeGlProgram(ChunkShaderInterface shaderInterface) {
        super(1, ctx -> shaderInterface);
    }

    public void bind() {
    }

    public void unbind() {
    }

    public void delete() {
    }
}

