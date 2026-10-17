/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.mojang.blaze3d.GpuFormat
 *  com.mojang.blaze3d.PrimitiveTopology
 *  com.mojang.blaze3d.pipeline.BindGroupLayout
 *  com.mojang.blaze3d.pipeline.BindGroupLayout$UniformDescription
 *  com.mojang.blaze3d.pipeline.RenderPipeline
 *  com.mojang.blaze3d.shaders.ShaderSource
 *  com.mojang.blaze3d.shaders.ShaderType
 *  com.mojang.blaze3d.vertex.VertexFormat
 *  com.mojang.blaze3d.vertex.VertexFormatElement
 *  com.mojang.blaze3d.vulkan.VulkanBindGroupLayout$Entry
 *  com.mojang.blaze3d.vulkan.VulkanBindGroupLayout$VulkanBindGroupEntryType
 *  com.mojang.blaze3d.vulkan.glsl.IntermediaryShaderModule
 *  com.mojang.blaze3d.vulkan.glsl.ShaderCompileException
 *  com.mojang.blaze3d.vulkan.glsl.SpvSampler
 *  com.mojang.blaze3d.vulkan.glsl.SpvUniformBuffer
 *  com.mojang.blaze3d.vulkan.glsl.SpvVariable
 *  java.lang.MatchException
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.jspecify.annotations.Nullable
 *  org.lwjgl.PointerBuffer
 *  org.lwjgl.system.MemoryStack
 *  org.lwjgl.system.MemoryUtil
 *  org.lwjgl.util.spvc.Spvc
 *  org.lwjgl.util.spvc.SpvcMslShaderInterfaceVar2
 *  org.lwjgl.util.spvc.SpvcReflectedResource
 *  org.lwjgl.util.spvc.SpvcReflectedResource$Buffer
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.MetalCompiledRenderPipeline;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.MetalPipelineSupport;
import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.mojang.blaze3d.GpuFormat;
import com.mojang.blaze3d.PrimitiveTopology;
import com.mojang.blaze3d.pipeline.BindGroupLayout;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.shaders.ShaderSource;
import com.mojang.blaze3d.shaders.ShaderType;
import com.mojang.blaze3d.vertex.VertexFormat;
import com.mojang.blaze3d.vertex.VertexFormatElement;
import com.mojang.blaze3d.vulkan.VulkanBindGroupLayout;
import com.mojang.blaze3d.vulkan.glsl.IntermediaryShaderModule;
import com.mojang.blaze3d.vulkan.glsl.ShaderCompileException;



import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

import org.lwjgl.PointerBuffer;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.util.spvc.Spvc;
import org.lwjgl.util.spvc.SpvcMslShaderInterfaceVar2;
import org.lwjgl.util.spvc.SpvcReflectedResource;

@Environment(value=EnvType.CLIENT)
final class MetalCrossShaderCompiler {
    private static final Set<String> BUILT_IN_UNIFORMS = Set.of("Projection", "Lighting", "Fog", "Globals");
    private static final int MSL_VERSION_4_0 = 262144;
    private static final Pattern VERTEX_ENTRY_PATTERN = Pattern.compile("\\bvertex\\s+\\w+\\s+(\\w+)\\s*\\(");
    private static final Pattern FRAGMENT_ENTRY_PATTERN = Pattern.compile("\\bfragment\\s+\\w+\\s+(\\w+)\\s*\\(");

    private MetalCrossShaderCompiler() {
    }

    static MetalCompiledRenderPipeline compile(MetalDevice device, RenderPipeline pipeline, ShaderSource shaderSource) {
        try {
            IntermediaryShaderModule vertexSpirv = device.getOrCompileShader(pipeline.getVertexShader(), ShaderType.VERTEX, pipeline.getShaderDefines(), shaderSource);
            IntermediaryShaderModule fragmentSpirv = device.getOrCompileShader(pipeline.getFragmentShader(), ShaderType.FRAGMENT, pipeline.getShaderDefines(), shaderSource);
            if (vertexSpirv == IntermediaryShaderModule.INVALID || fragmentSpirv == IntermediaryShaderModule.INVALID) {
                throw new IllegalStateException("Couldn't compile shader for pipeline " + String.valueOf(pipeline.getLocation()));
            }
            ArrayList<VulkanBindGroupLayout.Entry> layoutEntries = new ArrayList<VulkanBindGroupLayout.Entry>();
            MetalCrossShaderCompiler.addToBindGroup(layoutEntries, vertexSpirv, pipeline);
            MetalCrossShaderCompiler.addToBindGroup(layoutEntries, fragmentSpirv, pipeline);
            List<String> vertexOutputs = MetalCrossShaderCompiler.extractVariableNames(vertexSpirv.outputs());
            vertexSpirv.rebind(MetalCrossShaderCompiler.tolerateUnprovidedInputs(MetalPipelineSupport.vertexAttributeNames(pipeline), vertexSpirv.inputs()), layoutEntries);
            boolean enablePointSize = pipeline.getPrimitiveTopology() == PrimitiveTopology.POINTS;
            MslShader vertexMsl = MetalCrossShaderCompiler.spirvToMsl(vertexSpirv.spirv(), layoutEntries.size(), MetalCrossShaderCompiler.vertexAttributeFormats(pipeline), enablePointSize);
            fragmentSpirv.rebind(MetalCrossShaderCompiler.tolerateUnprovidedInputs(vertexOutputs, fragmentSpirv.inputs()), layoutEntries);
            MslShader fragmentMsl = MetalCrossShaderCompiler.spirvToMsl(fragmentSpirv.spirv(), layoutEntries.size(), Map.of(), true);
            String vertexEntryPoint = MetalCrossShaderCompiler.extractEntryPoint(vertexMsl.source(), VERTEX_ENTRY_PATTERN, "main0");
            String fragmentEntryPoint = MetalCrossShaderCompiler.extractEntryPoint(fragmentMsl.source(), FRAGMENT_ENTRY_PATTERN, "main0");
            List<MetalCompiledRenderPipeline.ResourceBinding> resources = MetalCrossShaderCompiler.buildResourceBindings(layoutEntries, vertexMsl, fragmentMsl);
            return new MetalCompiledRenderPipeline(device, pipeline, vertexMsl.source(), fragmentMsl.source(), vertexEntryPoint, fragmentEntryPoint, resources);
        }
        catch (ShaderCompileException e) {
            throw new IllegalStateException("Failed to compile Metal cross shader for pipeline " + String.valueOf(pipeline.getLocation()), e);
        }
    }

        private static String getSpvName(Object obj) {
        if (obj == null) return "";
        try {
            java.lang.reflect.Method m = obj.getClass().getMethod("name");
            m.setAccessible(true);
            return (String) m.invoke(obj);
        } catch (Throwable t) {
            try {
                java.lang.reflect.Method m = obj.getClass().getDeclaredMethod("name");
                m.setAccessible(true);
                return (String) m.invoke(obj);
            } catch (Throwable t2) {
                try {
                    java.lang.reflect.Field f = obj.getClass().getDeclaredField("name");
                    f.setAccessible(true);
                    return (String) f.get(obj);
                } catch (Throwable t3) {
                    return "";
                }
            }
        }
    }

    private static int getSpvDimensions(Object obj) {
        if (obj == null) return 0;
        try {
            java.lang.reflect.Method m = obj.getClass().getMethod("dimensions");
            m.setAccessible(true);
            return ((Number) m.invoke(obj)).intValue();
        } catch (Throwable t) {
            try {
                java.lang.reflect.Method m = obj.getClass().getDeclaredMethod("dimensions");
                m.setAccessible(true);
                return ((Number) m.invoke(obj)).intValue();
            } catch (Throwable t2) {
                try {
                    java.lang.reflect.Field f = obj.getClass().getDeclaredField("dimensions");
                    f.setAccessible(true);
                    return ((Number) f.get(obj)).intValue();
                } catch (Throwable t3) {
                    return 0;
                }
            }
        }
    }

    private static void addToBindGroup(List<VulkanBindGroupLayout.Entry> entries, IntermediaryShaderModule shader, RenderPipeline pipeline) throws ShaderCompileException {
        String name;
        List uniforms = BindGroupLayout.flattenUniforms((List)pipeline.getBindGroupLayouts());
        List samplers = BindGroupLayout.flattenSamplers((List)pipeline.getBindGroupLayouts());
        for (Object buffer : shader.uniformBuffers()) {
            name = getSpvName(buffer);
            if (MetalCrossShaderCompiler.findUniform(uniforms, name) == null && !BUILT_IN_UNIFORMS.contains(name)) {
                throw new ShaderCompileException("Unable to find shader defined uniform (" + name + ")");
            }
            MetalCrossShaderCompiler.addBindingIfAbsent(entries, VulkanBindGroupLayout.VulkanBindGroupEntryType.UNIFORM_BUFFER, name, null);
        }
        for (Object sampler : shader.samplers()) {
            name = getSpvName(sampler);
            BindGroupLayout.UniformDescription uniform = MetalCrossShaderCompiler.findUniform(uniforms, name);
            int dimensions = getSpvDimensions(sampler);
            if (uniform != null) {
                if (dimensions != 5) {
                    throw new ShaderCompileException("UTB (" + name + ") must have type of SpvDimBuffer");
                }
                MetalCrossShaderCompiler.addBindingIfAbsent(entries, VulkanBindGroupLayout.VulkanBindGroupEntryType.TEXEL_BUFFER, name, uniform.gpuFormat());
                continue;
            }
            if (!samplers.contains(name)) {
                throw new ShaderCompileException("Unable to find shader defined uniform (" + name + ")");
            }
            if (dimensions != 1 && dimensions != 3) {
                throw new ShaderCompileException("Sampled texture (" + name + ") must have type of SpvDim2D or SpvDimCube");
            }
            MetalCrossShaderCompiler.addBindingIfAbsent(entries, VulkanBindGroupLayout.VulkanBindGroupEntryType.SAMPLED_IMAGE, name, null);
        }
    }

    private static // Could not load outer class - annotation placement on inner may be incorrect
    BindGroupLayout.UniformDescription findUniform(List<BindGroupLayout.UniformDescription> uniforms, String name) {
        for (BindGroupLayout.UniformDescription uniform : uniforms) {
            if (!uniform.name().equals(name)) continue;
            return uniform;
        }
        return null;
    }

    private static void addBindingIfAbsent(List<VulkanBindGroupLayout.Entry> entries, VulkanBindGroupLayout.VulkanBindGroupEntryType type, String name, GpuFormat texelBufferFormat) {
        for (VulkanBindGroupLayout.Entry entry : entries) {
            if (entry.type() != type || !entry.name().equals(name)) continue;
            return;
        }
        entries.add(new VulkanBindGroupLayout.Entry(type, name, texelBufferFormat));
    }

    private static List<String> tolerateUnprovidedInputs(List<String> provided, List<?> shaderInputs) {
        ArrayList<String> result = null;
        for (Object input : shaderInputs) {
            String name = getSpvName(input);
            if (provided.contains(name)) continue;
            if (result == null) {
                result = new ArrayList<String>(provided);
            }
            if (result.contains(name)) continue;
            result.add(name);
        }
        return result == null ? provided : result;
    }

    private static List<String> extractVariableNames(List<?> variables) {
        ArrayList<String> names = new ArrayList<String>(variables.size());
        for (Object variable : variables) {
            names.add(getSpvName(variable));
        }
        return names;
    }

    private static String extractEntryPoint(String msl, Pattern pattern, String fallback) {
        Matcher matcher = pattern.matcher(msl);
        return matcher.find() ? matcher.group(1) : fallback;
    }

    private static List<MetalCompiledRenderPipeline.ResourceBinding> buildResourceBindings(List<VulkanBindGroupLayout.Entry> entries, MslShader vertexMsl, MslShader fragmentMsl) {
        ArrayList<MetalCompiledRenderPipeline.ResourceBinding> resources = new ArrayList<MetalCompiledRenderPipeline.ResourceBinding>(entries.size() + 1);
        for (int index = 0; index < entries.size(); ++index) {
            VulkanBindGroupLayout.Entry entry = entries.get(index);
            MetalCompiledRenderPipeline.ResourceKind kind = switch (entry.type()) {
                default -> throw new MatchException(null, null);
                case VulkanBindGroupLayout.VulkanBindGroupEntryType.UNIFORM_BUFFER -> MetalCompiledRenderPipeline.ResourceKind.UNIFORM_BUFFER;
                case VulkanBindGroupLayout.VulkanBindGroupEntryType.SAMPLED_IMAGE -> MetalCompiledRenderPipeline.ResourceKind.SAMPLED_IMAGE;
                case VulkanBindGroupLayout.VulkanBindGroupEntryType.TEXEL_BUFFER -> MetalCompiledRenderPipeline.ResourceKind.TEXEL_BUFFER;
            };
            GpuFormat texelFormat = entry.type() == VulkanBindGroupLayout.VulkanBindGroupEntryType.TEXEL_BUFFER ? entry.texelBufferFormat() : null;
            resources.add(new MetalCompiledRenderPipeline.ResourceBinding(kind, entry.name(), index, MetalCrossShaderCompiler.stageMask(entry.name(), vertexMsl, fragmentMsl), texelFormat));
        }
        int pushConstantStageMask = (vertexMsl.hasPushConstants() ? 1 : 0) | (fragmentMsl.hasPushConstants() ? 2 : 0);
        if (pushConstantStageMask != 0) {
            resources.add(new MetalCompiledRenderPipeline.ResourceBinding(MetalCompiledRenderPipeline.ResourceKind.UNIFORM_BUFFER, "push_constants", entries.size(), pushConstantStageMask, null));
        }
        return resources;
    }

    private static int stageMask(String name, MslShader vertexMsl, MslShader fragmentMsl) {
        int mask = 0;
        if (vertexMsl.activeResources().contains(name)) {
            mask |= 1;
        }
        if (fragmentMsl.activeResources().contains(name)) {
            mask |= 2;
        }
        if (mask == 0) {
            mask = 3;
        }
        return mask;
    }

    private static Map<String, GpuFormat> vertexAttributeFormats(RenderPipeline pipeline) {
        LinkedHashMap<String, GpuFormat> formats = new LinkedHashMap<String, GpuFormat>();
        for (VertexFormat binding : pipeline.getVertexFormatBindings()) {
            if (binding == null) continue;
            for (VertexFormatElement element : binding.getElements()) {
                formats.putIfAbsent(element.name(), element.format());
            }
        }
        return formats;
    }

    private static void registerIntegerInputConversions(MemoryStack stack, long compiler, Map<String, GpuFormat> attributeFormats) throws ShaderCompileException {
        if (attributeFormats.isEmpty()) {
            return;
        }
        PointerBuffer pResources = stack.mallocPointer(1);
        MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_create_shader_resources((long)compiler, (PointerBuffer)pResources), "spvc_compiler_create_shader_resources");
        PointerBuffer pList = stack.mallocPointer(1);
        PointerBuffer pCount = stack.mallocPointer(1);
        MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_resources_get_resource_list_for_type((long)pResources.get(0), (int)3, (PointerBuffer)pList, (PointerBuffer)pCount), "spvc_resources_get_resource_list_for_type(STAGE_INPUT)");
        int count = (int)pCount.get(0);
        if (count == 0) {
            return;
        }
        SpvcReflectedResource.Buffer list = SpvcReflectedResource.create((long)pList.get(0), (int)count);
        for (int i = 0; i < count; ++i) {
            long typeHandle;
            int baseType;
            int width;
            SpvcReflectedResource input = (SpvcReflectedResource)list.get(i);
            GpuFormat format = attributeFormats.get(input.nameString());
            if (format == null || !format.name().endsWith("_UINT")) continue;
            width = format.name().contains("8") ? 1 : (format.name().contains("16") ? 2 : 0);
            if (width == 0 || (baseType = Spvc.spvc_type_get_basetype((long)(typeHandle = Spvc.spvc_compiler_get_type_handle((long)compiler, (int)input.type_id())))) != 3 && baseType != 5 && baseType != 7 && baseType != 9) continue;
            SpvcMslShaderInterfaceVar2 var = SpvcMslShaderInterfaceVar2.malloc((MemoryStack)stack);
            Spvc.spvc_msl_shader_interface_var_init_2((SpvcMslShaderInterfaceVar2)var);
            var.location(Spvc.spvc_compiler_get_decoration((long)compiler, (int)input.id(), (int)30));
            var.vecsize(Spvc.spvc_type_get_vector_size((long)typeHandle));
            var.format(width);
            var.rate(0);
            MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_msl_add_shader_input_2((long)compiler, (SpvcMslShaderInterfaceVar2)var), "spvc_compiler_msl_add_shader_input_2");
        }
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    private static MslShader spirvToMsl(ByteBuffer spirvBytes, int pushConstantBinding, Map<String, GpuFormat> attributeFormats, boolean enablePointSize) throws ShaderCompileException {
        try (MemoryStack stack = MemoryStack.stackPush();){
            MslShader mslShader;
            IntBuffer spirvWords = spirvBytes.asIntBuffer();
            int wordCount = spirvWords.remaining();
            if (wordCount < 5) {
                throw new ShaderCompileException("SPIR-V is too small: " + wordCount + " words (minimum 5 required). ByteBuffer remaining=" + spirvBytes.remaining() + " byteOrder=" + String.valueOf(spirvBytes.order()));
            }
            int magic = spirvWords.get(0);
            PointerBuffer pContext = stack.mallocPointer(1);
            MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_context_create((PointerBuffer)pContext), "spvc_context_create");
            long context = pContext.get(0);
            try {
                boolean hasPushConstants;
                PointerBuffer pIr = stack.mallocPointer(1);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_context_parse_spirv((long)context, (IntBuffer)spirvWords, (long)wordCount, (PointerBuffer)pIr), "spvc_context_parse_spirv");
                long ir = pIr.get(0);
                if (ir == 0L) {
                    String lastError = Spvc.spvc_context_get_last_error_string((long)context);
                    throw new ShaderCompileException("spvc_context_parse_spirv returned SPVC_SUCCESS but parsed_ir is NULL. This indicates a version mismatch between the loaded libspvc.dylib and LWJGL's Java bindings, or symbol interposition from another library (e.g. libMoltenVK.dylib). SPIR-V: " + wordCount + " words, magic=0x" + Integer.toHexString(magic) + ". Last error: " + lastError);
                }
                PointerBuffer pCompiler = stack.mallocPointer(1);
                int createCompilerResult = Spvc.spvc_context_create_compiler((long)context, (int)3, (long)ir, (int)0, (PointerBuffer)pCompiler);
                if (createCompilerResult != 0) {
                    String lastError = Spvc.spvc_context_get_last_error_string((long)context);
                    throw new ShaderCompileException("SPIRV-Cross error at spvc_context_create_compiler: " + createCompilerResult + " (context=0x" + Long.toHexString(context) + ", ir=0x" + Long.toHexString(ir) + ", backend=MSL, mode=COPY). Last error: " + lastError);
                }
                long compiler = pCompiler.get(0);
                PointerBuffer pOptions = stack.mallocPointer(1);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_create_compiler_options((long)compiler, (PointerBuffer)pOptions), "spvc_compiler_create_compiler_options");
                long options = pOptions.get(0);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_options_set_uint((long)options, (int)134217759, (int)1), "spvc_compiler_options_set_uint(MSL_PLATFORM)");
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_options_set_uint((long)options, (int)0x8000011, (int)262144), "spvc_compiler_options_set_uint(MSL_VERSION)");
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_options_set_bool((long)options, (int)134217777, (boolean)true), "spvc_compiler_options_set_bool(MSL_ENABLE_DECORATION_BINDING)");
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_options_set_bool((long)options, (int)0x8000022, (boolean)true), "spvc_compiler_options_set_bool(MSL_TEXTURE_BUFFER_NATIVE)");
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_options_set_bool((long)options, (int)0x1000004, (boolean)true), "spvc_compiler_options_set_bool(FLIP_VERTEX_Y)");
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_options_set_bool((long)options, (int)134217753, (boolean)enablePointSize), "spvc_compiler_options_set_bool(MSL_ENABLE_POINT_SIZE_BUILTIN)");
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_install_compiler_options((long)compiler, (long)options), "spvc_compiler_install_compiler_options");
                MetalCrossShaderCompiler.registerIntegerInputConversions(stack, compiler, attributeFormats);
                PointerBuffer pActiveSet = stack.mallocPointer(1);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_get_active_interface_variables((long)compiler, (PointerBuffer)pActiveSet), "spvc_compiler_get_active_interface_variables");
                long activeSet = pActiveSet.get(0);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_set_enabled_interface_variables((long)compiler, (long)activeSet), "spvc_compiler_set_enabled_interface_variables");
                Set<String> activeResources = MetalCrossShaderCompiler.collectActiveResourceNames(stack, compiler, activeSet);
                PointerBuffer pResources = stack.mallocPointer(1);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_create_shader_resources((long)compiler, (PointerBuffer)pResources), "spvc_compiler_create_shader_resources");
                long resources = pResources.get(0);
                PointerBuffer pList = stack.mallocPointer(1);
                PointerBuffer pCount = stack.mallocPointer(1);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_resources_get_resource_list_for_type((long)resources, (int)9, (PointerBuffer)pList, (PointerBuffer)pCount), "spvc_resources_get_resource_list_for_type");
                boolean bl = hasPushConstants = pCount.get(0) > 0L;
                if (hasPushConstants) {
                    SpvcReflectedResource.Buffer list = SpvcReflectedResource.create((long)pList.get(0), (int)1);
                    Spvc.spvc_compiler_set_decoration((long)compiler, (int)((SpvcReflectedResource)list.get(0)).id(), (int)33, (int)pushConstantBinding);
                }
                PointerBuffer pSource = stack.mallocPointer(1);
                MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_compile((long)compiler, (PointerBuffer)pSource), "spvc_compiler_compile");
                mslShader = new MslShader(MemoryUtil.memUTF8((long)pSource.get(0)), hasPushConstants, activeResources);
            }
            catch (Throwable throwable) {
                Spvc.spvc_context_destroy((long)context);
                throw throwable;
            }
            Spvc.spvc_context_destroy((long)context);
            return mslShader;
        }
    }

    private static Set<String> collectActiveResourceNames(MemoryStack stack, long compiler, long activeSet) throws ShaderCompileException {
        PointerBuffer pResources = stack.mallocPointer(1);
        MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_compiler_create_shader_resources_for_active_variables((long)compiler, (PointerBuffer)pResources, (long)activeSet), "spvc_compiler_create_shader_resources_for_active_variables");
        long resources = pResources.get(0);
        HashSet<String> names = new HashSet<String>();
        MetalCrossShaderCompiler.collectResourceNames(stack, resources, 1, names);
        MetalCrossShaderCompiler.collectResourceNames(stack, resources, 7, names);
        MetalCrossShaderCompiler.collectResourceNames(stack, resources, 10, names);
        MetalCrossShaderCompiler.collectResourceNames(stack, resources, 11, names);
        return names;
    }

    private static void collectResourceNames(MemoryStack stack, long resources, int resourceType, Set<String> out) throws ShaderCompileException {
        PointerBuffer pList = stack.mallocPointer(1);
        PointerBuffer pCount = stack.mallocPointer(1);
        MetalCrossShaderCompiler.checkSpvc(Spvc.spvc_resources_get_resource_list_for_type((long)resources, (int)resourceType, (PointerBuffer)pList, (PointerBuffer)pCount), "spvc_resources_get_resource_list_for_type");
        int count = (int)pCount.get(0);
        if (count == 0) {
            return;
        }
        SpvcReflectedResource.Buffer list = SpvcReflectedResource.create((long)pList.get(0), (int)count);
        for (int i = 0; i < count; ++i) {
            out.add(((SpvcReflectedResource)list.get(i)).nameString());
        }
    }

    private static void checkSpvc(int result, String stage) throws ShaderCompileException {
        if (result != 0) {
            throw new ShaderCompileException("SPIRV-Cross error at " + stage + ": " + result);
        }
    }

    static {
        MetalNativeBridge.ensureSpvcLibraryConfigured();
    }

    record MslShader(String source, boolean hasPushConstants, Set<String> activeResources) {
    }
}




