/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.shaded.asm.tree;

import com.metallum.shaded.asm.MethodVisitor;
import com.metallum.shaded.asm.tree.AbstractInsnNode;
import com.metallum.shaded.asm.tree.LabelNode;
import java.util.Map;

/*
 * This class specifies class file version 49.0 but uses Java 6 signatures.  Assumed Java 6.
 */
public class LineNumberNode
extends AbstractInsnNode {
    public int line;
    public LabelNode start;

    public LineNumberNode(int line, LabelNode start) {
        super(-1);
        this.line = line;
        this.start = start;
    }

    @Override
    public int getType() {
        return 15;
    }

    @Override
    public void accept(MethodVisitor methodVisitor) {
        methodVisitor.visitLineNumber(this.line, this.start.getLabel());
    }

    @Override
    public AbstractInsnNode clone(Map<LabelNode, LabelNode> clonedLabels) {
        return new LineNumberNode(this.line, LineNumberNode.clone(this.start, clonedLabels));
    }
}

