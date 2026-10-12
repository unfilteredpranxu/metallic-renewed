/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.shaded.asm.tree;

import com.metallum.shaded.asm.AnnotationVisitor;
import com.metallum.shaded.asm.Attribute;
import com.metallum.shaded.asm.ClassVisitor;
import com.metallum.shaded.asm.ConstantDynamic;
import com.metallum.shaded.asm.Handle;
import com.metallum.shaded.asm.Label;
import com.metallum.shaded.asm.MethodVisitor;
import com.metallum.shaded.asm.Type;
import com.metallum.shaded.asm.TypePath;
import com.metallum.shaded.asm.tree.AbstractInsnNode;
import com.metallum.shaded.asm.tree.AnnotationNode;
import com.metallum.shaded.asm.tree.FieldInsnNode;
import com.metallum.shaded.asm.tree.FrameNode;
import com.metallum.shaded.asm.tree.IincInsnNode;
import com.metallum.shaded.asm.tree.InsnList;
import com.metallum.shaded.asm.tree.InsnNode;
import com.metallum.shaded.asm.tree.IntInsnNode;
import com.metallum.shaded.asm.tree.InvokeDynamicInsnNode;
import com.metallum.shaded.asm.tree.JumpInsnNode;
import com.metallum.shaded.asm.tree.LabelNode;
import com.metallum.shaded.asm.tree.LdcInsnNode;
import com.metallum.shaded.asm.tree.LineNumberNode;
import com.metallum.shaded.asm.tree.LocalVariableAnnotationNode;
import com.metallum.shaded.asm.tree.LocalVariableNode;
import com.metallum.shaded.asm.tree.LookupSwitchInsnNode;
import com.metallum.shaded.asm.tree.MethodInsnNode;
import com.metallum.shaded.asm.tree.MultiANewArrayInsnNode;
import com.metallum.shaded.asm.tree.ParameterNode;
import com.metallum.shaded.asm.tree.TableSwitchInsnNode;
import com.metallum.shaded.asm.tree.TryCatchBlockNode;
import com.metallum.shaded.asm.tree.TypeAnnotationNode;
import com.metallum.shaded.asm.tree.TypeInsnNode;
import com.metallum.shaded.asm.tree.UnsupportedClassVersionException;
import com.metallum.shaded.asm.tree.Util;
import com.metallum.shaded.asm.tree.VarInsnNode;
import java.util.ArrayList;
import java.util.List;

public class MethodNode
extends MethodVisitor {
    public int access;
    public String name;
    public String desc;
    public String signature;
    public List<String> exceptions;
    public List<ParameterNode> parameters;
    public List<AnnotationNode> visibleAnnotations;
    public List<AnnotationNode> invisibleAnnotations;
    public List<TypeAnnotationNode> visibleTypeAnnotations;
    public List<TypeAnnotationNode> invisibleTypeAnnotations;
    public List<Attribute> attrs;
    public Object annotationDefault;
    public int visibleAnnotableParameterCount;
    public List<AnnotationNode>[] visibleParameterAnnotations;
    public int invisibleAnnotableParameterCount;
    public List<AnnotationNode>[] invisibleParameterAnnotations;
    public InsnList instructions;
    public List<TryCatchBlockNode> tryCatchBlocks;
    public int maxStack;
    public int maxLocals;
    public List<LocalVariableNode> localVariables;
    public List<LocalVariableAnnotationNode> visibleLocalVariableAnnotations;
    public List<LocalVariableAnnotationNode> invisibleLocalVariableAnnotations;
    private boolean visited;

    public MethodNode() {
        this(589824);
        if (this.getClass() != MethodNode.class) {
            throw new IllegalStateException();
        }
    }

    public MethodNode(int api) {
        super(api);
        this.instructions = new InsnList();
    }

    public MethodNode(int access, String name, String descriptor, String signature, String[] exceptions) {
        this(589824, access, name, descriptor, signature, exceptions);
        if (this.getClass() != MethodNode.class) {
            throw new IllegalStateException();
        }
    }

    public MethodNode(int api, int access, String name, String descriptor, String signature, String[] exceptions) {
        super(api);
        this.access = access;
        this.name = name;
        this.desc = descriptor;
        this.signature = signature;
        this.exceptions = Util.asArrayList(exceptions);
        if ((access & 0x400) == 0) {
            this.localVariables = new ArrayList<LocalVariableNode>(5);
        }
        this.tryCatchBlocks = new ArrayList<TryCatchBlockNode>();
        this.instructions = new InsnList();
    }

    public void visitParameter(String name, int access) {
        if (this.parameters == null) {
            this.parameters = new ArrayList<ParameterNode>(5);
        }
        this.parameters.add(new ParameterNode(name, access));
    }

    public AnnotationVisitor visitAnnotationDefault() {
        return new AnnotationNode((List<Object>)new ArrayList<Object>(0){

            @Override
            public boolean add(Object o) {
                MethodNode.this.annotationDefault = o;
                return super.add(o);
            }
        });
    }

    public AnnotationVisitor visitAnnotation(String descriptor, boolean visible) {
        AnnotationNode annotation = new AnnotationNode(descriptor);
        if (visible) {
            this.visibleAnnotations = Util.add(this.visibleAnnotations, annotation);
        } else {
            this.invisibleAnnotations = Util.add(this.invisibleAnnotations, annotation);
        }
        return annotation;
    }

    public AnnotationVisitor visitTypeAnnotation(int typeRef, TypePath typePath, String descriptor, boolean visible) {
        TypeAnnotationNode typeAnnotation = new TypeAnnotationNode(typeRef, typePath, descriptor);
        if (visible) {
            this.visibleTypeAnnotations = Util.add(this.visibleTypeAnnotations, typeAnnotation);
        } else {
            this.invisibleTypeAnnotations = Util.add(this.invisibleTypeAnnotations, typeAnnotation);
        }
        return typeAnnotation;
    }

    public void visitAnnotableParameterCount(int parameterCount, boolean visible) {
        if (visible) {
            this.visibleAnnotableParameterCount = parameterCount;
        } else {
            this.invisibleAnnotableParameterCount = parameterCount;
        }
    }

    public AnnotationVisitor visitParameterAnnotation(int parameter, String descriptor, boolean visible) {
        AnnotationNode annotation = new AnnotationNode(descriptor);
        if (visible) {
            if (this.visibleParameterAnnotations == null) {
                int params = Type.getArgumentCount(this.desc);
                this.visibleParameterAnnotations = new List[params];
            }
            this.visibleParameterAnnotations[parameter] = Util.add(this.visibleParameterAnnotations[parameter], annotation);
        } else {
            if (this.invisibleParameterAnnotations == null) {
                int params = Type.getArgumentCount(this.desc);
                this.invisibleParameterAnnotations = new List[params];
            }
            this.invisibleParameterAnnotations[parameter] = Util.add(this.invisibleParameterAnnotations[parameter], annotation);
        }
        return annotation;
    }

    public void visitAttribute(Attribute attribute) {
        this.attrs = Util.add(this.attrs, attribute);
    }

    public void visitCode() {
    }

    public void visitFrame(int type, int numLocal, Object[] local, int numStack, Object[] stack) {
        this.instructions.add(new FrameNode(type, numLocal, local == null ? null : this.getLabelNodes(local), numStack, stack == null ? null : this.getLabelNodes(stack)));
    }

    public void visitInsn(int opcode) {
        this.instructions.add(new InsnNode(opcode));
    }

    public void visitIntInsn(int opcode, int operand) {
        this.instructions.add(new IntInsnNode(opcode, operand));
    }

    public void visitVarInsn(int opcode, int varIndex) {
        this.instructions.add(new VarInsnNode(opcode, varIndex));
    }

    public void visitTypeInsn(int opcode, String type) {
        this.instructions.add(new TypeInsnNode(opcode, type));
    }

    public void visitFieldInsn(int opcode, String owner, String name, String descriptor) {
        this.instructions.add(new FieldInsnNode(opcode, owner, name, descriptor));
    }

    public void visitMethodInsn(int opcodeAndSource, String owner, String name, String descriptor, boolean isInterface) {
        if (this.api < 327680 && (opcodeAndSource & 0x100) == 0) {
            super.visitMethodInsn(opcodeAndSource, owner, name, descriptor, isInterface);
            return;
        }
        int opcode = opcodeAndSource & 0xFFFFFEFF;
        this.instructions.add(new MethodInsnNode(opcode, owner, name, descriptor, isInterface));
    }

    public void visitInvokeDynamicInsn(String name, String descriptor, Handle bootstrapMethodHandle, Object ... bootstrapMethodArguments) {
        this.instructions.add(new InvokeDynamicInsnNode(name, descriptor, bootstrapMethodHandle, bootstrapMethodArguments));
    }

    public void visitJumpInsn(int opcode, Label label) {
        this.instructions.add(new JumpInsnNode(opcode, this.getLabelNode(label)));
    }

    public void visitLabel(Label label) {
        this.instructions.add(this.getLabelNode(label));
    }

    public void visitLdcInsn(Object value) {
        this.instructions.add(new LdcInsnNode(value));
    }

    public void visitIincInsn(int varIndex, int increment) {
        this.instructions.add(new IincInsnNode(varIndex, increment));
    }

    public void visitTableSwitchInsn(int min, int max, Label dflt, Label ... labels) {
        this.instructions.add(new TableSwitchInsnNode(min, max, this.getLabelNode(dflt), this.getLabelNodes(labels)));
    }

    public void visitLookupSwitchInsn(Label dflt, int[] keys, Label[] labels) {
        this.instructions.add(new LookupSwitchInsnNode(this.getLabelNode(dflt), keys, this.getLabelNodes(labels)));
    }

    public void visitMultiANewArrayInsn(String descriptor, int numDimensions) {
        this.instructions.add(new MultiANewArrayInsnNode(descriptor, numDimensions));
    }

    public AnnotationVisitor visitInsnAnnotation(int typeRef, TypePath typePath, String descriptor, boolean visible) {
        AbstractInsnNode currentInsn = this.instructions.getLast();
        while (currentInsn.getOpcode() == -1) {
            currentInsn = currentInsn.getPrevious();
        }
        TypeAnnotationNode typeAnnotation = new TypeAnnotationNode(typeRef, typePath, descriptor);
        if (visible) {
            currentInsn.visibleTypeAnnotations = Util.add(currentInsn.visibleTypeAnnotations, typeAnnotation);
        } else {
            currentInsn.invisibleTypeAnnotations = Util.add(currentInsn.invisibleTypeAnnotations, typeAnnotation);
        }
        return typeAnnotation;
    }

    public void visitTryCatchBlock(Label start, Label end, Label handler, String type) {
        TryCatchBlockNode tryCatchBlock = new TryCatchBlockNode(this.getLabelNode(start), this.getLabelNode(end), this.getLabelNode(handler), type);
        this.tryCatchBlocks = Util.add(this.tryCatchBlocks, tryCatchBlock);
    }

    public AnnotationVisitor visitTryCatchAnnotation(int typeRef, TypePath typePath, String descriptor, boolean visible) {
        TryCatchBlockNode tryCatchBlock = this.tryCatchBlocks.get((typeRef & 0xFFFF00) >> 8);
        TypeAnnotationNode typeAnnotation = new TypeAnnotationNode(typeRef, typePath, descriptor);
        if (visible) {
            tryCatchBlock.visibleTypeAnnotations = Util.add(tryCatchBlock.visibleTypeAnnotations, typeAnnotation);
        } else {
            tryCatchBlock.invisibleTypeAnnotations = Util.add(tryCatchBlock.invisibleTypeAnnotations, typeAnnotation);
        }
        return typeAnnotation;
    }

    public void visitLocalVariable(String name, String descriptor, String signature, Label start, Label end, int index) {
        LocalVariableNode localVariable = new LocalVariableNode(name, descriptor, signature, this.getLabelNode(start), this.getLabelNode(end), index);
        this.localVariables = Util.add(this.localVariables, localVariable);
    }

    public AnnotationVisitor visitLocalVariableAnnotation(int typeRef, TypePath typePath, Label[] start, Label[] end, int[] index, String descriptor, boolean visible) {
        LocalVariableAnnotationNode localVariableAnnotation = new LocalVariableAnnotationNode(typeRef, typePath, this.getLabelNodes(start), this.getLabelNodes(end), index, descriptor);
        if (visible) {
            this.visibleLocalVariableAnnotations = Util.add(this.visibleLocalVariableAnnotations, localVariableAnnotation);
        } else {
            this.invisibleLocalVariableAnnotations = Util.add(this.invisibleLocalVariableAnnotations, localVariableAnnotation);
        }
        return localVariableAnnotation;
    }

    public void visitLineNumber(int line, Label start) {
        this.instructions.add(new LineNumberNode(line, this.getLabelNode(start)));
    }

    public void visitMaxs(int maxStack, int maxLocals) {
        this.maxStack = maxStack;
        this.maxLocals = maxLocals;
    }

    public void visitEnd() {
    }

    protected LabelNode getLabelNode(Label label) {
        if (!(label.info instanceof LabelNode)) {
            label.info = new LabelNode();
        }
        return (LabelNode)label.info;
    }

    private LabelNode[] getLabelNodes(Label[] labels) {
        LabelNode[] labelNodes = new LabelNode[labels.length];
        int n = labels.length;
        for (int i = 0; i < n; ++i) {
            labelNodes[i] = this.getLabelNode(labels[i]);
        }
        return labelNodes;
    }

    private Object[] getLabelNodes(Object[] objects) {
        Object[] labelNodes = new Object[objects.length];
        for (Object o : objects) {
            if (o instanceof Label) {
                o = this.getLabelNode((Label)o);
            }
            labelNodes[i] = o;
        }
        return labelNodes;
    }

    public void check(int api) {
        AbstractInsnNode insn;
        int i;
        if (api == 262144) {
            if (this.parameters != null && !this.parameters.isEmpty()) {
                throw new UnsupportedClassVersionException();
            }
            if (this.visibleTypeAnnotations != null && !this.visibleTypeAnnotations.isEmpty()) {
                throw new UnsupportedClassVersionException();
            }
            if (this.invisibleTypeAnnotations != null && !this.invisibleTypeAnnotations.isEmpty()) {
                throw new UnsupportedClassVersionException();
            }
            if (this.tryCatchBlocks != null) {
                for (i = this.tryCatchBlocks.size() - 1; i >= 0; --i) {
                    TryCatchBlockNode tryCatchBlock = this.tryCatchBlocks.get(i);
                    if (tryCatchBlock.visibleTypeAnnotations != null && !tryCatchBlock.visibleTypeAnnotations.isEmpty()) {
                        throw new UnsupportedClassVersionException();
                    }
                    if (tryCatchBlock.invisibleTypeAnnotations == null || tryCatchBlock.invisibleTypeAnnotations.isEmpty()) continue;
                    throw new UnsupportedClassVersionException();
                }
            }
            for (i = this.instructions.size() - 1; i >= 0; --i) {
                Object value;
                insn = this.instructions.get(i);
                if (insn.visibleTypeAnnotations != null && !insn.visibleTypeAnnotations.isEmpty()) {
                    throw new UnsupportedClassVersionException();
                }
                if (insn.invisibleTypeAnnotations != null && !insn.invisibleTypeAnnotations.isEmpty()) {
                    throw new UnsupportedClassVersionException();
                }
                if (insn instanceof MethodInsnNode) {
                    boolean isInterface = ((MethodInsnNode)insn).itf;
                    if (isInterface == (insn.opcode == 185)) continue;
                    throw new UnsupportedClassVersionException();
                }
                if (insn instanceof InvokeDynamicInsnNode) {
                    throw new UnsupportedClassVersionException();
                }
                if (!(insn instanceof LdcInsnNode) || !((value = ((LdcInsnNode)insn).cst) instanceof Handle) && (!(value instanceof Type) || ((Type)value).getSort() != 11)) continue;
                throw new UnsupportedClassVersionException();
            }
            if (this.visibleLocalVariableAnnotations != null && !this.visibleLocalVariableAnnotations.isEmpty()) {
                throw new UnsupportedClassVersionException();
            }
            if (this.invisibleLocalVariableAnnotations != null && !this.invisibleLocalVariableAnnotations.isEmpty()) {
                throw new UnsupportedClassVersionException();
            }
        }
        if (api < 458752) {
            for (i = this.instructions.size() - 1; i >= 0; --i) {
                Object value;
                insn = this.instructions.get(i);
                if (!(insn instanceof LdcInsnNode) || !((value = ((LdcInsnNode)insn).cst) instanceof ConstantDynamic)) continue;
                throw new UnsupportedClassVersionException();
            }
        }
    }

    public void accept(ClassVisitor classVisitor) {
        String[] exceptionsArray = this.exceptions == null ? null : this.exceptions.toArray(new String[0]);
        MethodVisitor methodVisitor = classVisitor.visitMethod(this.access, this.name, this.desc, this.signature, exceptionsArray);
        if (methodVisitor != null) {
            this.accept(methodVisitor);
        }
    }

    public void accept(MethodVisitor methodVisitor) {
        AnnotationNode annotation;
        int j;
        int m;
        List<AnnotationNode> parameterAnnotations;
        TypeAnnotationNode typeAnnotation;
        AnnotationNode annotation2;
        int i;
        int n;
        if (this.parameters != null) {
            n = this.parameters.size();
            for (i = 0; i < n; ++i) {
                this.parameters.get(i).accept(methodVisitor);
            }
        }
        if (this.annotationDefault != null) {
            AnnotationVisitor annotationVisitor = methodVisitor.visitAnnotationDefault();
            AnnotationNode.accept(annotationVisitor, null, this.annotationDefault);
            if (annotationVisitor != null) {
                annotationVisitor.visitEnd();
            }
        }
        if (this.visibleAnnotations != null) {
            n = this.visibleAnnotations.size();
            for (i = 0; i < n; ++i) {
                annotation2 = this.visibleAnnotations.get(i);
                annotation2.accept(methodVisitor.visitAnnotation(annotation2.desc, true));
            }
        }
        if (this.invisibleAnnotations != null) {
            n = this.invisibleAnnotations.size();
            for (i = 0; i < n; ++i) {
                annotation2 = this.invisibleAnnotations.get(i);
                annotation2.accept(methodVisitor.visitAnnotation(annotation2.desc, false));
            }
        }
        if (this.visibleTypeAnnotations != null) {
            n = this.visibleTypeAnnotations.size();
            for (i = 0; i < n; ++i) {
                typeAnnotation = this.visibleTypeAnnotations.get(i);
                typeAnnotation.accept(methodVisitor.visitTypeAnnotation(typeAnnotation.typeRef, typeAnnotation.typePath, typeAnnotation.desc, true));
            }
        }
        if (this.invisibleTypeAnnotations != null) {
            n = this.invisibleTypeAnnotations.size();
            for (i = 0; i < n; ++i) {
                typeAnnotation = this.invisibleTypeAnnotations.get(i);
                typeAnnotation.accept(methodVisitor.visitTypeAnnotation(typeAnnotation.typeRef, typeAnnotation.typePath, typeAnnotation.desc, false));
            }
        }
        if (this.visibleAnnotableParameterCount > 0) {
            methodVisitor.visitAnnotableParameterCount(this.visibleAnnotableParameterCount, true);
        }
        if (this.visibleParameterAnnotations != null) {
            n = this.visibleParameterAnnotations.length;
            for (i = 0; i < n; ++i) {
                parameterAnnotations = this.visibleParameterAnnotations[i];
                if (parameterAnnotations == null) continue;
                m = parameterAnnotations.size();
                for (j = 0; j < m; ++j) {
                    annotation = parameterAnnotations.get(j);
                    annotation.accept(methodVisitor.visitParameterAnnotation(i, annotation.desc, true));
                }
            }
        }
        if (this.invisibleAnnotableParameterCount > 0) {
            methodVisitor.visitAnnotableParameterCount(this.invisibleAnnotableParameterCount, false);
        }
        if (this.invisibleParameterAnnotations != null) {
            n = this.invisibleParameterAnnotations.length;
            for (i = 0; i < n; ++i) {
                parameterAnnotations = this.invisibleParameterAnnotations[i];
                if (parameterAnnotations == null) continue;
                m = parameterAnnotations.size();
                for (j = 0; j < m; ++j) {
                    annotation = parameterAnnotations.get(j);
                    annotation.accept(methodVisitor.visitParameterAnnotation(i, annotation.desc, false));
                }
            }
        }
        if (this.visited) {
            this.instructions.resetLabels();
        }
        if (this.attrs != null) {
            n = this.attrs.size();
            for (i = 0; i < n; ++i) {
                methodVisitor.visitAttribute(this.attrs.get(i));
            }
        }
        if (this.instructions.size() > 0) {
            methodVisitor.visitCode();
            if (this.tryCatchBlocks != null) {
                n = this.tryCatchBlocks.size();
                for (i = 0; i < n; ++i) {
                    this.tryCatchBlocks.get(i).updateIndex(i);
                    this.tryCatchBlocks.get(i).accept(methodVisitor);
                }
            }
            this.instructions.accept(methodVisitor);
            if (this.localVariables != null) {
                n = this.localVariables.size();
                for (i = 0; i < n; ++i) {
                    this.localVariables.get(i).accept(methodVisitor);
                }
            }
            if (this.visibleLocalVariableAnnotations != null) {
                n = this.visibleLocalVariableAnnotations.size();
                for (i = 0; i < n; ++i) {
                    this.visibleLocalVariableAnnotations.get(i).accept(methodVisitor, true);
                }
            }
            if (this.invisibleLocalVariableAnnotations != null) {
                n = this.invisibleLocalVariableAnnotations.size();
                for (i = 0; i < n; ++i) {
                    this.invisibleLocalVariableAnnotations.get(i).accept(methodVisitor, false);
                }
            }
            methodVisitor.visitMaxs(this.maxStack, this.maxLocals);
            this.visited = true;
        }
        methodVisitor.visitEnd();
    }
}

