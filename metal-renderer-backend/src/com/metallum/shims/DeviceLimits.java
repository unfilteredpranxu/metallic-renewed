/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.shims.DeviceLimits
 */
package com.metallum.shims;

public record DeviceLimits(int minUniformBufferOffsetAlignment, int maxVertexAttributes, int maxVertexBuffers, long maxMemoryAllocationSize, int maxStorageBufferSize, int maxTextureArrayLayers) {
    private final int minUniformBufferOffsetAlignment;
    private final int maxVertexAttributes;
    private final int maxVertexBuffers;
    private final long maxMemoryAllocationSize;
    private final int maxStorageBufferSize;
    private final int maxTextureArrayLayers;

    public DeviceLimits(int n, int n2, int n3, long l, int n4, int n5) {
        this.minUniformBufferOffsetAlignment = n;
        this.maxVertexAttributes = n2;
        this.maxVertexBuffers = n3;
        this.maxMemoryAllocationSize = l;
        this.maxStorageBufferSize = n4;
        this.maxTextureArrayLayers = n5;
    }

    public long maxMemoryAllocationSize() {
        return this.maxMemoryAllocationSize;
    }

    public int minUniformBufferOffsetAlignment() {
        return this.minUniformBufferOffsetAlignment;
    }

    public int maxVertexAttributes() {
        return this.maxVertexAttributes;
    }

    public int maxVertexBuffers() {
        return this.maxVertexBuffers;
    }

    public int maxStorageBufferSize() {
        return this.maxStorageBufferSize;
    }

    public int maxTextureArrayLayers() {
        return this.maxTextureArrayLayers;
    }
}

