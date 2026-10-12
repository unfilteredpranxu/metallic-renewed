/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  amo
 *  com.metallum.client.metal.render.MetalCrossShaderCompiler$CompiledGlsl
 *  com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderCache
 *  com.mojang.blaze3d.vertex.VertexFormatElement$Type
 *  net.caffeinemc.mods.sodium.client.gl.shader.ShaderConstants
 *  net.caffeinemc.mods.sodium.client.gl.shader.ShaderLoader
 *  net.caffeinemc.mods.sodium.client.gl.shader.ShaderParser
 *  net.caffeinemc.mods.sodium.client.gl.shader.ShaderParser$ParsedShader
 *  net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderOptions
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.MetalCrossShaderCompiler;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.sodium.MetalSodiumCompiledPipeline;
import com.mojang.blaze3d.vertex.VertexFormatElement;
import java.util.HashMap;
import java.util.Map;
import net.caffeinemc.mods.sodium.client.gl.shader.ShaderConstants;
import net.caffeinemc.mods.sodium.client.gl.shader.ShaderLoader;
import net.caffeinemc.mods.sodium.client.gl.shader.ShaderParser;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderOptions;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class MetalSodiumShaderCache {
    private static final boolean SOLID_COLOR_DIAG = Boolean.parseBoolean(System.getProperty("metallum.solidcolor", "false"));
    private static final String SHADER_PATH = "blocks/block_layer_opaque";
    private static final Map<String, VertexFormatElement.Type> ATTRIBUTE_TYPES = Map.of((Object)"a_Position", (Object)VertexFormatElement.Type.UINT, (Object)"a_TexCoord", (Object)VertexFormatElement.Type.UINT, (Object)"a_LightAndData", (Object)VertexFormatElement.Type.UINT);
    private static final Map<String, Integer> ATTRIBUTE_LOCATIONS = Map.of((Object)"a_Position", (Object)0, (Object)"a_Color", (Object)1, (Object)"a_TexCoord", (Object)2, (Object)"a_LightAndData", (Object)3);
    private final MetalDevice device;
    private final Map<ChunkShaderOptions, MetalSodiumCompiledPipeline> pipelines = new HashMap();
    private static final Map<ChunkShaderOptions, MetalSodiumCompiledPipeline> GLOBAL_PIPELINES = new HashMap();

    public MetalSodiumShaderCache(MetalDevice device) {
        this.device = device;
    }

    public MetalSodiumCompiledPipeline get(ChunkShaderOptions options) {
        MetalSodiumCompiledPipeline cached = (MetalSodiumCompiledPipeline)GLOBAL_PIPELINES.get(options);
        if (cached != null) {
            return cached;
        }
        MetalSodiumCompiledPipeline compiled = this.pipelines.computeIfAbsent(options, arg_0 -> this.compile(arg_0));
        GLOBAL_PIPELINES.putIfAbsent(options, compiled);
        return compiled;
    }

    private MetalSodiumCompiledPipeline compile(ChunkShaderOptions options) {
        ShaderConstants constants = options.constants();
        ShaderParser.ParsedShader vertex = ShaderParser.parseShader((String)ShaderLoader.getShaderSource((amo)amo.a((String)"sodium", (String)"blocks/block_layer_opaque.vsh")), (ShaderConstants)constants);
        ShaderParser.ParsedShader fragment = ShaderParser.parseShader((String)ShaderLoader.getShaderSource((amo)amo.a((String)"sodium", (String)"blocks/block_layer_opaque.fsh")), (ShaderConstants)constants);
        String fragmentSrc = fragment.src();
        if (SOLID_COLOR_DIAG) {
            fragmentSrc = fragmentSrc.replace("void main() {", "void main() { fragColor = vec4(1.0, 0.0, 0.0, 1.0); return;");
        }
        MetalCrossShaderCompiler.CompiledGlsl compiled = MetalCrossShaderCompiler.compileGlsl((String)vertex.src(), (String)fragmentSrc, (Map)ATTRIBUTE_TYPES, (Map)ATTRIBUTE_LOCATIONS, (String)"sodium/blocks/block_layer_opaque");
        Map vertexBuffers = MetalSodiumCompiledPipeline.extractBuffers((String)compiled.vertexMsl(), (String)"ChunkData");
        Map fragmentBuffers = MetalSodiumCompiledPipeline.extractBuffers((String)compiled.fragmentMsl(), (String)"ChunkData");
        Map vertexTextures = MetalSodiumCompiledPipeline.extractTextures((String)compiled.vertexMsl());
        Map fragmentTextures = MetalSodiumCompiledPipeline.extractTextures((String)compiled.fragmentMsl());
        return new MetalSodiumCompiledPipeline(this.device, options.pass().getPipeline(), compiled, options.vertexType().getVertexFormat(), vertexBuffers, fragmentBuffers, vertexTextures, fragmentTextures);
    }

    public void close() {
        this.pipelines.clear();
    }
}

