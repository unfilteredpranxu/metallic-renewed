/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  java.lang.foreign.MemorySegment
 */
package com.metallum.client.metal.render.mtl;

import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLBlendFactor;
import com.metallum.client.metal.render.mtl.MTLBlendOperation;
import com.metallum.client.metal.render.mtl.MTLPixelFormat;
import com.metallum.client.metal.render.mtl.MTLVertexDescriptor;
import java.lang.foreign.MemorySegment;

public final class MTLRenderPipelineDescriptor
implements AutoCloseable {
    private final MemorySegment handle = MetalNativeBridge.metallum_MTLRenderPipelineDescriptor_create();
    private boolean closed;

    public MemorySegment handle() {
        return this.handle;
    }

    public void setCompiledFunctions(MemorySegment vertexFunction, MemorySegment fragmentFunction) {
        MetalNativeBridge.metallum_MTLRenderPipelineDescriptor_setCompiledFunctions(this.handle, vertexFunction, fragmentFunction);
    }

    public void setVertexDescriptor(MTLVertexDescriptor vertexDescriptor) {
        MetalNativeBridge.metallum_MTLRenderPipelineDescriptor_setVertexDescriptor(this.handle, vertexDescriptor.handle());
    }

    public void setAttachmentFormats(MTLPixelFormat colorFormat, MTLPixelFormat depthFormat, MTLPixelFormat stencilFormat) {
        MetalNativeBridge.metallum_MTLRenderPipelineDescriptor_setAttachmentFormats(this.handle, colorFormat, depthFormat, stencilFormat);
    }

    public void setBlendState(MTLBlendFactor sourceColorBlendFactor, MTLBlendFactor destinationColorBlendFactor, MTLBlendOperation colorBlendOperation, MTLBlendFactor sourceAlphaBlendFactor, MTLBlendFactor destinationAlphaBlendFactor, MTLBlendOperation alphaBlendOperation, long writeMask) {
        MetalNativeBridge.metallum_MTLRenderPipelineDescriptor_setBlendState(this.handle, 1, sourceColorBlendFactor.value, destinationColorBlendFactor.value, colorBlendOperation.value, sourceAlphaBlendFactor.value, destinationAlphaBlendFactor.value, alphaBlendOperation.value, writeMask);
    }

    public void disableBlending(long writeMask) {
        MetalNativeBridge.metallum_MTLRenderPipelineDescriptor_setBlendState(this.handle, 0, 0L, 0L, 0L, 0L, 0L, 0L, writeMask);
    }

    @Override
    public void close() {
        if (!this.closed) {
            this.closed = true;
            MetalNativeBridge.metallum_release_object(this.handle);
        }
    }
}

