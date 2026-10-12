/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.DiagLog
 *  com.metallum.client.metal.render.Diagnostics
 *  com.metallum.client.metal.render.MetalTransientMemory$MappedView
 *  com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface
 *  com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers
 *  com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers$RegionUniformSlices
 *  com.mojang.blaze3d.buffers.GpuBufferSlice
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 *  org.joml.Matrix4fc
 *  org.jspecify.annotations.Nullable
 */
package com.metallum.client.metal.render.sodium;

import com.metallum.client.metal.render.DiagLog;
import com.metallum.client.metal.render.Diagnostics;
import com.metallum.client.metal.render.MetalBackend;
import com.metallum.client.metal.render.MetalCommandEncoder;
import com.metallum.client.metal.render.MetalDevice;
import com.metallum.client.metal.render.MetalGpuBuffer;
import com.metallum.client.metal.render.MetalTransientMemory;
import com.metallum.client.metal.render.sodium.MetalSodiumShaderInterface;
import com.metallum.client.metal.render.sodium.MetalSodiumUniformBuffers;
import com.mojang.blaze3d.buffers.GpuBufferSlice;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
import org.joml.Matrix4fc;
import org.jspecify.annotations.Nullable;

/*
 * Exception performing whole class analysis ignored.
 */
@Environment(value=EnvType.CLIENT)
public final class MetalSodiumUniformBuffers
implements AutoCloseable {
    private static final int USAGE = 136;
    private static final long REGION_UNIFORM_SIZE = 32L;
    private static final long REGION_UNIFORM_ALIGNMENT = 16L;
    private static final int CURRENT_TIME_OFFSET = 16;
    private static final int RING_GROUPS = 3;
    private static final int UNIFORM_COUNT = 9;
    private static final int IDX_PROJECTION = 0;
    private static final int IDX_MODEL_VIEW = 1;
    private static final int IDX_TEX_COORD_SHRINK = 2;
    private static final int IDX_FADE_PERIOD_INV = 3;
    private static final int IDX_FOG_COLOR = 4;
    private static final int IDX_ENVIRONMENT_FOG = 5;
    private static final int IDX_RENDER_FOG = 6;
    private static final int IDX_TEXEL_SIZE = 7;
    private static final int IDX_USE_RGSS = 8;
    private static final int[] UNIFORM_SIZES = new int[]{64, 64, 8, 4, 16, 8, 8, 8, 4};
    private final MetalGpuBuffer[][] groups = new MetalGpuBuffer[3][9];
    private boolean passUniformsWritten;

    public MetalSodiumUniformBuffers(MetalDevice device) {
        for (int g = 0; g < 3; ++g) {
            for (int i = 0; i < 9; ++i) {
                this.groups[g][i] = new MetalGpuBuffer(device, 136, UNIFORM_SIZES[i]);
            }
        }
    }

    static int groupForFrame(long frame) {
        if (frame < 0L) {
            return 0;
        }
        return (int)(frame % 3L);
    }

    public @Nullable MetalGpuBuffer forBinding(String name) {
        int idx;
        switch (name) {
            case "u_ProjectionMatrix": {
                int n = 0;
                break;
            }
            case "u_ModelViewMatrix": {
                int n = 1;
                break;
            }
            case "u_TexCoordShrink": {
                int n = 2;
                break;
            }
            case "u_FadePeriodInv": {
                int n = 3;
                break;
            }
            case "u_FogColor": {
                int n = 4;
                break;
            }
            case "u_EnvironmentFog": {
                int n = 5;
                break;
            }
            case "u_RenderFog": {
                int n = 6;
                break;
            }
            case "u_TexelSize": {
                int n = 7;
                break;
            }
            case "u_UseRGSS": {
                int n = 8;
                break;
            }
            default: {
                int n = idx = -1;
            }
        }
        if (idx < 0) {
            return null;
        }
        return this.groups[MetalSodiumUniformBuffers.groupForFrame((long)MetalCommandEncoder.currentFrameIndex())][idx];
    }

    public void markPassStart() {
        this.passUniformsWritten = false;
    }

    public void uploadPassUniforms(MetalSodiumShaderInterface shaderInterface) {
        if (this.passUniformsWritten) {
            return;
        }
        MetalGpuBuffer[] group = this.groups[MetalSodiumUniformBuffers.groupForFrame((long)MetalCommandEncoder.currentFrameIndex())];
        Matrix4fc projection = shaderInterface.projectionMatrix();
        Matrix4fc modelView = shaderInterface.modelViewMatrix();
        if (projection != null) {
            MetalSodiumUniformBuffers.writeMatrix((MetalGpuBuffer)group[0], (Matrix4fc)projection);
        }
        if (modelView != null) {
            MetalSodiumUniformBuffers.writeMatrix((MetalGpuBuffer)group[1], (Matrix4fc)modelView);
        }
        MetalSodiumUniformBuffers.writeFloats((MetalGpuBuffer)group[2], (int)8, (float[])new float[]{shaderInterface.texCoordShrinkX(), shaderInterface.texCoordShrinkY()});
        MetalSodiumUniformBuffers.writeFloat((MetalGpuBuffer)group[3], (float)shaderInterface.fadePeriodInv());
        MetalSodiumUniformBuffers.writeFloats((MetalGpuBuffer)group[4], (int)16, (float[])new float[]{shaderInterface.fogColorR(), shaderInterface.fogColorG(), shaderInterface.fogColorB(), shaderInterface.fogColorA()});
        MetalSodiumUniformBuffers.writeFloats((MetalGpuBuffer)group[5], (int)8, (float[])new float[]{shaderInterface.environmentFogStart(), shaderInterface.environmentFogEnd()});
        MetalSodiumUniformBuffers.writeFloats((MetalGpuBuffer)group[6], (int)8, (float[])new float[]{shaderInterface.renderFogStart(), shaderInterface.renderFogEnd()});
        MetalSodiumUniformBuffers.writeFloats((MetalGpuBuffer)group[7], (int)8, (float[])new float[]{shaderInterface.texelSizeX(), shaderInterface.texelSizeY()});
        MetalSodiumUniformBuffers.writeInt((MetalGpuBuffer)group[8], (int)(shaderInterface.useRGSS() ? 1 : 0));
        this.passUniformsWritten = true;
    }

    public RegionUniformSlices allocateRegionUniforms(MetalSodiumShaderInterface shaderInterface) {
        MetalCommandEncoder encoder = (MetalCommandEncoder)MetalBackend.activeDevice().createCommandEncoder();
        MetalTransientMemory.MappedView view = encoder.allocateTransientUniform(32L, 16L);
        GpuBufferSlice block = view.slice();
        ByteBuffer data = view.data().order(ByteOrder.nativeOrder());
        data.rewind();
        data.asFloatBuffer().put(shaderInterface.regionOffsetX()).put(shaderInterface.regionOffsetY()).put(shaderInterface.regionOffsetZ());
        data.position(16);
        data.putInt(shaderInterface.currentTime());
        if (Diagnostics.shouldRun((String)"sodium-fade", (long)5000L)) {
            float rx = shaderInterface.regionOffsetX();
            float ry = shaderInterface.regionOffsetY();
            float rz = shaderInterface.regionOffsetZ();
            int ct = shaderInterface.currentTime();
            float fpi = shaderInterface.fadePeriodInv();
            boolean nan = Float.isNaN(rx) || Float.isNaN(ry) || Float.isNaN(rz) || Float.isNaN(fpi);
            DiagLog.log((String)"[diag] sodium regionUniform regionOffset=(%.2f,%.2f,%.2f) currentTime=%d fadePeriodInv=%.6f%s", (Object[])new Object[]{Float.valueOf(rx), Float.valueOf(ry), Float.valueOf(rz), ct, Float.valueOf(fpi), nan ? " NAN-DETECTED" : ""});
        }
        return new RegionUniformSlices(new GpuBufferSlice(block.buffer(), block.offset(), 16L), new GpuBufferSlice(block.buffer(), block.offset() + 16L, 4L));
    }

    private static void writeMatrix(MetalGpuBuffer buffer, Matrix4fc matrix) {
        float[] values = new float[16];
        matrix.get(values);
        ByteBuffer dst = buffer.currentStorage().order(ByteOrder.nativeOrder());
        dst.rewind();
        dst.asFloatBuffer().put(values);
    }

    private static void writeFloats(MetalGpuBuffer buffer, int bufferSize, float ... values) {
        ByteBuffer dst = buffer.currentStorage().order(ByteOrder.nativeOrder());
        dst.rewind();
        dst.limit(bufferSize);
        dst.asFloatBuffer().put(values);
    }

    private static void writeFloat(MetalGpuBuffer buffer, float value) {
        ((ByteBuffer)buffer.currentStorage().order(ByteOrder.nativeOrder()).rewind()).putFloat(value);
    }

    private static void writeInt(MetalGpuBuffer buffer, int value) {
        ((ByteBuffer)buffer.currentStorage().order(ByteOrder.nativeOrder()).rewind()).putInt(value);
    }

    @Override
    public void close() {
        for (int g = 0; g < 3; ++g) {
            for (int i = 0; i < 9; ++i) {
                this.groups[g][i].close();
            }
        }
    }
}

