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
public class InsnNode
extends AbstractInsnNode {
    public InsnNode(int opcode) {
        super(opcode);
    }

    @Override
    public int getType() {
        return 0;
    }

    @Override
    public void accept(MethodVisitor methodVisitor) {
        methodVisitor.visitInsn(this.opcode);
        this.acceptAnnotations(methodVisitor);
    }

    @Override
    public AbstractInsnNode clone(Map<LabelNode, LabelNode> clonedLabels) {
        return new InsnNode(this.opcode).cloneAnnotations(this);
    }
}

