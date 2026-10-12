/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.MetalGlBufferRegistry
 *  com.metallum.client.metal.render.sodium.MetalGlBufferRegistry$MetalGlBufferEntry
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface
 *  com.mojang.blaze3d.systems.RenderSystem
 *  com.mojang.blaze3d.textures.FilterMode
 *  com.mojang.blaze3d.textures.GpuTextureView
 *  fzf
 *  gfj
 *  gfv
 *  ilo
 *  net.caffeinemc.mods.sodium.client.gl.buffer.GlBuffer
 *  net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface
 *  net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass
 *  net.caffeinemc.mods.sodium.client.util.FogParameters
 *  net.caffeinemc.mods.sodium.mixin.core.render.texture.TextureAtlasAccessor
 *  org.joml.Matrix4f
 *  org.joml.Matrix4fc
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.sodium.MetalGlBufferRegistry;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.textures.FilterMode;
import com.mojang.blaze3d.textures.GpuTextureView;
import net.caffeinemc.mods.sodium.client.gl.buffer.GlBuffer;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass;
import net.caffeinemc.mods.sodium.client.util.FogParameters;
import net.caffeinemc.mods.sodium.mixin.core.render.texture.TextureAtlasAccessor;
import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.jspecify.annotations.Nullable;

public final class MetalSodiumShaderInterface
implements ChunkShaderInterface {
    private static final int SUB_TEXEL_PRECISION_BITS = 4;
    private final Matrix4f projectionMatrix = new Matrix4f();
    private final Matrix4f modelViewMatrix = new Matrix4f();
    private float regionOffsetX;
    private float regionOffsetY;
    private float regionOffsetZ;
    private float texCoordShrinkX;
    private float texCoordShrinkY;
    private float texelSizeX;
    private float texelSizeY;
    private boolean useRGSS;
    private int currentTime;
    private float fadePeriodInv;
    private float fogColorR;
    private float fogColorG;
    private float fogColorB;
    private float fogColorA;
    private float environmentFogStart;
    private float environmentFogEnd;
    private float renderFogStart;
    private float renderFogEnd;
    private @Nullable MetalGpuBuffer chunkDataBuffer;
    private @Nullable GpuTextureView blockTex;
    private @Nullable GpuTextureView lightTex;
    private @Nullable fzf terrainSampler;
    private @Nullable fzf lightSampler;

    public void setupState(TerrainRenderPass pass, FogParameters parameters, fzf sampler) {
        this.blockTex = pass.getAtlas();
        this.lightTex = gfj.V().i.q().a();
        this.terrainSampler = sampler;
        this.lightSampler = RenderSystem.getSamplerCache().a(FilterMode.LINEAR);
        TextureAtlasAccessor textureAtlas = (TextureAtlasAccessor)gfj.V().af().b(ilo.d);
        double subTexelPrecision = 16.0;
        double subTexelOffset = 3.0517578125E-5;
        this.texCoordShrinkX = (float)(subTexelOffset - 1.0 / (double)textureAtlas.sodium$getWidth() / subTexelPrecision);
        this.texCoordShrinkY = (float)(subTexelOffset - 1.0 / (double)textureAtlas.sodium$getHeight() / subTexelPrecision);
        this.texelSizeX = 1.0f / (float)textureAtlas.sodium$getWidth();
        this.texelSizeY = 1.0f / (float)textureAtlas.sodium$getHeight();
        this.fadePeriodInv = (float)(1.0 / ((Double)gfj.V().k.r().b() * 1000.0));
        this.useRGSS = gfj.V().k.N().b() == gfv.b;
        this.fogColorR = parameters.red();
        this.fogColorG = parameters.green();
        this.fogColorB = parameters.blue();
        this.fogColorA = parameters.alpha();
        this.environmentFogStart = parameters.environmentalStart();
        this.environmentFogEnd = parameters.environmentalEnd();
        this.renderFogStart = parameters.renderStart();
        this.renderFogEnd = parameters.renderEnd();
    }

    public void resetState() {
        this.blockTex = null;
        this.lightTex = null;
        this.terrainSampler = null;
        this.lightSampler = null;
        this.chunkDataBuffer = null;
    }

    public void setProjectionMatrix(Matrix4fc matrix) {
        this.projectionMatrix.set(matrix);
    }

    public void setModelViewMatrix(Matrix4fc matrix) {
        this.modelViewMatrix.set(matrix);
    }

    public void setRegionOffset(float x, float y, float z) {
        this.regionOffsetX = x;
        this.regionOffsetY = y;
        this.regionOffsetZ = z;
    }

    public void setChunkData(GlBuffer data, int time) {
        MetalGlBufferRegistry.MetalGlBufferEntry entry = MetalGlBufferRegistry.get((int)data.handle());
        this.chunkDataBuffer = entry == null ? null : entry.buffer();
        this.currentTime = time;
    }

    public Matrix4fc projectionMatrix() {
        return this.projectionMatrix;
    }

    public Matrix4fc modelViewMatrix() {
        return this.modelViewMatrix;
    }

    public float regionOffsetX() {
        return this.regionOffsetX;
    }

    public float regionOffsetY() {
        return this.regionOffsetY;
    }

    public float regionOffsetZ() {
        return this.regionOffsetZ;
    }

    public float texCoordShrinkX() {
        return this.texCoordShrinkX;
    }

    public float texCoordShrinkY() {
        return this.texCoordShrinkY;
    }

    public float texelSizeX() {
        return this.texelSizeX;
    }

    public float texelSizeY() {
        return this.texelSizeY;
    }

    public boolean useRGSS() {
        return this.useRGSS;
    }

    public int currentTime() {
        return this.currentTime;
    }

    public float fadePeriodInv() {
        return this.fadePeriodInv;
    }

    public float fogColorR() {
        return this.fogColorR;
    }

    public float fogColorG() {
        return this.fogColorG;
    }

    public float fogColorB() {
        return this.fogColorB;
    }

    public float fogColorA() {
        return this.fogColorA;
    }

    public float environmentFogStart() {
        return this.environmentFogStart;
    }

    public float environmentFogEnd() {
        return this.environmentFogEnd;
    }

    public float renderFogStart() {
        return this.renderFogStart;
    }

    public float renderFogEnd() {
        return this.renderFogEnd;
    }

    public @Nullable MetalGpuBuffer chunkDataBuffer() {
        return this.chunkDataBuffer;
    }

    public @Nullable GpuTextureView blockTex() {
        return this.blockTex;
    }

    public @Nullable GpuTextureView lightTex() {
        return this.lightTex;
    }

    public @Nullable fzf terrainSampler() {
        return this.terrainSampler;
    }

    public @Nullable fzf lightSampler() {
        return this.lightSampler;
    }
}

