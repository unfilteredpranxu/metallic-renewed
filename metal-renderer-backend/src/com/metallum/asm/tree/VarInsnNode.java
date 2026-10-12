/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.asm.tree;

import com.metallum.asm.MethodVisitor;
import com.metallum.asm.tree.AbstractInsnNode;
import com.metallum.asm.tree.LabelNode;
import java.util.Map;

/*
 * This class specifies class file version 49.0 but uses Java 6 signatures.  Assumed Java 6.
 */
public class VarInsnNode
extends AbstractInsnNode {
    public int var;

    public VarInsnNode(int opcode, int varIndex) {
        super(opcode);
        this.var = varIndex;
    }

    public void setOpcode(int opcode) {
        this.opcode = opcode;
    }

    @Override
    public int getType() {
        return 2;
    }

    @Override
    public void accept(MethodVisitor methodVisitor) {
        methodVisitor.visitVarInsn(this.opcode, this.var);
        this.acceptAnnotations(methodVisitor);
    }

    @Override
    public AbstractInsnNode clone(Map<LabelNode, LabelNode> clonedLabels) {
        return new VarInsnNode(this.opcode, this.var).cloneAnnotations(this);
    }
}

