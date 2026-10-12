/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.MetalFakeGlProgram
 *  com.metallum.client.metal.render.sodium.MetalSodiumActiveState
 *  com.metallum.client.metal.render.sodium.MetalSodiumCommandList
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderCache
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderChunkRenderer
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface
 *  com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers
 *  fxt
 *  fzf
 *  gfj
 *  hnh
 *  net.caffeinemc.mods.sodium.client.gl.device.CommandList
 *  net.caffeinemc.mods.sodium.client.gl.device.RenderDevice
 *  net.caffeinemc.mods.sodium.client.render.chunk.DefaultChunkRenderer
 *  net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkFogMode
 *  net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface
 *  net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderOptions
 *  net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass
 *  net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexType
 *  net.caffeinemc.mods.sodium.client.util.FogParameters
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.MetalBackend;
import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.MetalRenderPass;
import com.metallum.client.metal.render.sodium.MetalFakeGlProgram;
import com.metallum.client.metal.render.sodium.MetalSodiumActiveState;
import com.metallum.client.metal.render.sodium.MetalSodiumCommandList;
import com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline;
import com.metallum.client.metal.render.sodium.MetalSodiumShaderCache;
import com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface;
import com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers;
import java.util.OptionalDouble;
import java.util.OptionalInt;
import net.caffeinemc.mods.sodium.client.gl.device.CommandList;
import net.caffeinemc.mods.sodium.client.gl.device.RenderDevice;
import net.caffeinemc.mods.sodium.client.render.chunk.DefaultChunkRenderer;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkFogMode;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderOptions;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass;
import net.caffeinemc.mods.sodium.client.render.chunk.vertex.format.ChunkVertexType;
import net.caffeinemc.mods.sodium.client.util.FogParameters;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class MetalSodiumShaderChunkRenderer
extends DefaultChunkRenderer {
    private final MetalSodiumShaderCache shaderCache;
    private final MetalSodiumUniformBuffers uniformBuffers;
    private final MetalSodiumShaderInterface shaderInterface = new MetalSodiumShaderInterface();
    private MetalSodiumCompiledPipeline activePipeline;
    private MetalRenderPass activeRenderPass;
    private static final double MOVE_THRESHOLD = 0.05;

    public MetalSodiumShaderChunkRenderer(MetalDevice device, ChunkVertexType vertexType) {
        super(RenderDevice.INSTANCE, vertexType);
        this.shaderCache = new MetalSodiumShaderCache(device);
        this.uniformBuffers = new MetalSodiumUniformBuffers(device);
    }

    protected void begin(TerrainRenderPass pass, FogParameters parameters, fzf terrainSampler) {
        this.metalBegin(pass, parameters, terrainSampler);
    }

    public void metalBegin(TerrainRenderPass pass, FogParameters parameters, fzf terrainSampler) {
        hnh player = gfj.V().s;
        MetalCommandEncoder.markFrameMoving((player != null && player.method_18798().i() > 0.05 ? 1 : 0) != 0);
        fxt target = pass.getTarget();
        MetalCommandEncoder encoder = (MetalCommandEncoder)MetalBackend.activeDevice().createCommandEncoder();
        this.activeRenderPass = (MetalRenderPass)encoder.createRenderPass(() -> "sodium-terrain", target.d(), OptionalInt.empty(), target.e() == null ? null : target.f(), OptionalDouble.empty());
        ChunkShaderOptions options = new ChunkShaderOptions(ChunkFogMode.SMOOTH, pass, this.vertexType);
        this.uniformBuffers.markPassStart();
        this.activePipeline = this.shaderCache.get(options);
        if (!this.activePipeline.isValid()) {
            throw new IllegalStateException("Sodium Metal pipeline invalid for " + String.valueOf(options));
        }
        this.shaderInterface.setupState(pass, parameters, terrainSampler);
        this.activeProgram = new MetalFakeGlProgram((ChunkShaderInterface)this.shaderInterface);
        MetalSodiumCommandList.setActiveSodiumState((MetalSodiumActiveState)new MetalSodiumActiveState(this.activePipeline, this.shaderInterface, this.uniformBuffers));
    }

    protected void end(TerrainRenderPass pass) {
        this.metalEnd(pass);
    }

    public void metalEnd(TerrainRenderPass pass) {
        MetalSodiumCommandList.clearActiveSodiumState();
        this.shaderInterface.resetState();
        this.activePipeline = null;
        this.activeProgram = null;
        if (this.activeRenderPass != null) {
            this.activeRenderPass.close();
            this.activeRenderPass = null;
        }
    }

    public void delete(CommandList commandList) {
        MetalSodiumCommandList.clearActiveSodiumState();
        this.shaderCache.close();
        this.uniformBuffers.close();
        super.delete(commandList);
    }
}

