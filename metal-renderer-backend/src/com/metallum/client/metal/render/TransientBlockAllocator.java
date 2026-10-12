/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.TransientBlockAllocator
 *  com.metallum.client.metal.render.TransientBlockAllocator$Allocation
 *  com.metallum.client.metal.render.TransientBlockAllocator$Allocator
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.TransientBlockAllocator;
import java.util.ArrayList;
import java.util.List;

/*
 * Exception performing whole class analysis ignored.
 */
final class TransientBlockAllocator<T> {
    private final long blockSize;
    private final Allocator<T> allocator;
    private T currentBlock;
    private long currentOffset;
    private List<T> previousBlocks = new ArrayList();

    TransientBlockAllocator(long blockSize, long maxAlignment, Allocator<T> allocator) {
        this.blockSize = blockSize;
        this.allocator = allocator;
    }

    Allocation<T> allocate(long size, long alignment, long minimumAllocation, long elementSize) {
        long effectiveAlignment = Math.max(alignment, Math.max(elementSize, 1L));
        long alignedSize = TransientBlockAllocator.roundUp((long)Math.max(size, minimumAllocation), (long)effectiveAlignment);
        if (alignedSize > this.blockSize) {
            Object big = this.allocator.create(alignedSize);
            this.previousBlocks.add(big);
            return new Allocation(big, 0L, size);
        }
        if (this.currentBlock == null || TransientBlockAllocator.roundUp((long)this.currentOffset, (long)effectiveAlignment) + alignedSize > this.blockSize) {
            this.newBlock();
        }
        long offset = TransientBlockAllocator.roundUp((long)this.currentOffset, (long)effectiveAlignment);
        this.currentOffset = offset + alignedSize;
        return new Allocation(this.currentBlock, offset, size);
    }

    boolean canAllocateInCurrentBlock(long size, long alignment) {
        if (this.currentBlock == null) {
            return false;
        }
        long alignedSize = TransientBlockAllocator.roundUp((long)size, (long)Math.max(alignment, 1L));
        return TransientBlockAllocator.roundUp((long)this.currentOffset, (long)alignment) + alignedSize <= this.blockSize;
    }

    Runnable rotate() {
        List toFree = this.previousBlocks;
        this.previousBlocks = new ArrayList();
        if (this.currentBlock != null) {
            this.previousBlocks.add(this.currentBlock);
            this.currentBlock = null;
            this.currentOffset = 0L;
        }
        return () -> {
            for (Object block : toFree) {
                this.allocator.free(block);
            }
        };
    }

    void close() {
        if (this.currentBlock != null) {
            this.allocator.free(this.currentBlock);
            this.currentBlock = null;
        }
        for (Object block : this.previousBlocks) {
            this.allocator.free(block);
        }
        this.previousBlocks = new ArrayList();
    }

    private void newBlock() {
        this.currentBlock = this.allocator.create(this.blockSize);
        this.currentOffset = 0L;
    }

    private static long roundUp(long value, long alignment) {
        return (value + alignment - 1L) / alignment * alignment;
    }
}

