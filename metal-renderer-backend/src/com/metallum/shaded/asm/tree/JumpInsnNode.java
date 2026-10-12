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
public class JumpInsnNode
extends AbstractInsnNode {
    public LabelNode label;

    public JumpInsnNode(int opcode, LabelNode label) {
        super(opcode);
        this.label = label;
    }

    public void setOpcode(int opcode) {
        this.opcode = opcode;
    }

    @Override
    public int getType() {
        return 7;
    }

    @Override
    public void accept(MethodVisitor methodVisitor) {
        methodVisitor.visitJumpInsn(this.opcode, this.label.getLabel());
        this.acceptAnnotations(methodVisitor);
    }

    @Override
    public AbstractInsnNode clone(Map<LabelNode, LabelNode> clonedLabels) {
        return new JumpInsnNode(this.opcode, JumpInsnNode.clone(this.label, clonedLabels)).cloneAnnotations(this);
    }
}

