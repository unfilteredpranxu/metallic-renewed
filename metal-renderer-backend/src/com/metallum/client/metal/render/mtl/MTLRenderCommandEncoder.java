/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  java.lang.foreign.MemorySegment
 *  net.fabricmc.api.EnvType
 *  net.fabricmc.api.Environment
 */
package com.metallum.client.metal.render.mtl;

import com.metallum.client.metal.render.bridge.MetalNativeBridge;
import com.metallum.client.metal.render.mtl.MTLCommandEncoder;
import com.metallum.client.metal.render.mtl.MTLCullMode;
import com.metallum.client.metal.render.mtl.MTLIndexType;
import com.metallum.client.metal.render.mtl.MTLPrimitiveType;
import com.metallum.client.metal.render.mtl.MTLRenderStages;
import com.metallum.client.metal.render.mtl.MTLTriangleFillMode;
import com.metallum.client.metal.render.mtl.MTLWinding;
import java.lang.foreign.MemorySegment;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;

@Environment(value=EnvType.CLIENT)
public final class MTLRenderCommandEncoder
extends MTLCommandEncoder {
    MTLRenderCommandEncoder(MemorySegment handle) {
        super(handle);
    }

    public void setRenderPipelineState(MemorySegment pipeline) {
        MetalNativeBridge.MTLRenderCommandEncoder_setRenderPipelineState(this.handle(), pipeline);
    }

    public void setDepthStencilState(MemorySegment depthStencilState) {
        MetalNativeBridge.MTLRenderCommandEncoder_setDepthStencilState(this.handle(), depthStencilState);
    }

    public void setDepthBias(float depthBias, float slopeScale, float clamp) {
        MetalNativeBridge.MTLRenderCommandEncoder_setDepthBias(this.handle(), depthBias, slopeScale, clamp);
    }

    public void setFrontFacingWinding(MTLWinding winding) {
        MetalNativeBridge.MTLRenderCommandEncoder_setFrontFacingWinding(this.handle(), winding.value);
    }

    public void setCullMode(MTLCullMode cullMode) {
        MetalNativeBridge.MTLRenderCommandEncoder_setCullMode(this.handle(), cullMode.value);
    }

    public void setTriangleFillMode(MTLTriangleFillMode fillMode) {
        MetalNativeBridge.MTLRenderCommandEncoder_setTriangleFillMode(this.handle(), fillMode.value);
    }

    public void setBuffer(MemorySegment buffer, long offset, long index, int stageMask) {
        MetalNativeBridge.MTLRenderCommandEncoder_setBuffer(this.handle(), buffer, offset, index, stageMask);
    }

    public void setBufferOffset(long offset, long index, int stageMask) {
        MetalNativeBridge.MTLRenderCommandEncoder_setBufferOffset(this.handle(), offset, index, stageMask);
    }

    public void setTexture(MemorySegment texture, long index, int stageMask) {
        MetalNativeBridge.MTLRenderCommandEncoder_setTexture(this.handle(), texture, index, stageMask);
    }

    public void setTextureAndSampler(MemorySegment texture, MemorySegment sampler, long index, int stageMask) {
        MetalNativeBridge.MTLRenderCommandEncoder_setTextureAndSampler(this.handle(), texture, sampler, index, stageMask);
    }

    public void setScissorRect(long x, long y, long width, long height) {
        MetalNativeBridge.MTLRenderCommandEncoder_setScissorRect(this.handle(), x, y, width, height);
    }

    public void clearDraw(MemorySegment colorTexture, MemorySegment depthTexture, double viewportWidth, double viewportHeight, boolean clearColorEnabled, float clearColorRed, float clearColorGreen, float clearColorBlue, float clearColorAlpha, boolean clearDepthEnabled, double clearDepth) {
        MetalNativeBridge.MTLRenderCommandEncoder_clearDraw(this.handle(), colorTexture, depthTexture, viewportWidth, viewportHeight, clearColorEnabled ? 1 : 0, clearColorRed, clearColorGreen, clearColorBlue, clearColorAlpha, clearDepthEnabled ? 1 : 0, clearDepth);
    }

    public void drawPrimitives(MTLPrimitiveType primitiveType, int firstVertex, int vertexCount, int instanceCount, int baseInstance) {
        MetalNativeBridge.MTLRenderCommandEncoder_drawPrimitives(this.handle(), primitiveType.value, firstVertex, vertexCount, instanceCount, baseInstance);
    }

    public void drawIndexedPrimitives(MTLPrimitiveType primitiveType, int indexCount, MTLIndexType indexType, MemorySegment indexBuffer, long offset, int instanceCount, int baseVertex, int baseInstance) {
        MetalNativeBridge.MTLRenderCommandEncoder_drawIndexedPrimitives(this.handle(), primitiveType.value, indexCount, indexType.value, indexBuffer, offset, instanceCount, baseVertex, baseInstance);
    }

    public void drawIndexedPrimitivesIndirect(MTLPrimitiveType primitiveType, MTLIndexType indexType, MemorySegment indexBuffer, MemorySegment indirectBuffer, long indirectBufferOffset, int drawCount, long stride) {
        MetalNativeBridge.MTLRenderCommandEncoder_drawIndexedPrimitivesIndirect(this.handle(), primitiveType.value, indexType.value, indexBuffer, indirectBuffer, indirectBufferOffset, drawCount, stride);
    }

    public void drawPrimitivesIndirect(MTLPrimitiveType primitiveType, MemorySegment indirectBuffer, long indirectBufferOffset, int drawCount, long stride) {
        MetalNativeBridge.MTLRenderCommandEncoder_drawPrimitivesIndirect(this.handle(), primitiveType.value, indirectBuffer, indirectBufferOffset, drawCount, stride);
    }

    public void drawIndexedPrimitivesTriangleFan(MemorySegment indexBuffer, MemorySegment fanIndexBuffer, long fanIndexBufferOffset, long indexType, long offset, int indexCount, int baseVertex, int instanceCount, int baseInstance) {
        MetalNativeBridge.MTLRenderCommandEncoder_drawIndexedPrimitivesTriangleFan(this.handle(), indexBuffer, fanIndexBuffer, fanIndexBufferOffset, indexType, offset, indexCount, baseVertex, instanceCount, baseInstance);
    }

    public void updateFence(MemorySegment fence, MTLRenderStages stages) {
        MetalNativeBridge.MTLRenderCommandEncoder_updateFence(this.handle(), fence, stages.value);
    }

    public void waitForFence(MemorySegment fence, MTLRenderStages stages) {
        MetalNativeBridge.MTLRenderCommandEncoder_waitForFence(this.handle(), fence, stages.value);
    }
}

