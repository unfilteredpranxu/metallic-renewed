/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.sodium.MetalSodiumActiveState
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface
 *  com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline;
import com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface;
import com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers;

public record MetalSodiumActiveState(MetalSodiumCompiledPipeline pipeline, MetalSodiumShaderInterface shaderInterface, MetalSodiumUniformBuffers uniformBuffers) {
    private final MetalSodiumCompiledPipeline pipeline;
    private final MetalSodiumShaderInterface shaderInterface;
    private final MetalSodiumUniformBuffers uniformBuffers;

    public MetalSodiumActiveState(MetalSodiumCompiledPipeline pipeline, MetalSodiumShaderInterface shaderInterface, MetalSodiumUniformBuffers uniformBuffers) {
        this.pipeline = pipeline;
        this.shaderInterface = shaderInterface;
        this.uniformBuffers = uniformBuffers;
    }

    public MetalSodiumCompiledPipeline pipeline() {
        return this.pipeline;
    }

    public MetalSodiumShaderInterface shaderInterface() {
        return this.shaderInterface;
    }

    public MetalSodiumUniformBuffers uniformBuffers() {
        return this.uniformBuffers;
    }
}

