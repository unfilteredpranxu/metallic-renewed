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
public class TypeInsnNode
extends AbstractInsnNode {
    public String desc;

    public TypeInsnNode(int opcode, String type) {
        super(opcode);
        this.desc = type;
    }

    public void setOpcode(int opcode) {
        this.opcode = opcode;
    }

    @Override
    public int getType() {
        return 3;
    }

    @Override
    public void accept(MethodVisitor methodVisitor) {
        methodVisitor.visitTypeInsn(this.opcode, this.desc);
        this.acceptAnnotations(methodVisitor);
    }

    @Override
    public AbstractInsnNode clone(Map<LabelNode, LabelNode> clonedLabels) {
        return new TypeInsnNode(this.opcode, this.desc).cloneAnnotations(this);
    }
}

