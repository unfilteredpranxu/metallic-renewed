/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.shaded.asm.commons;

import com.metallum.shaded.asm.Attribute;
import com.metallum.shaded.asm.ByteVector;
import com.metallum.shaded.asm.ClassReader;
import com.metallum.shaded.asm.ClassWriter;
import com.metallum.shaded.asm.Label;

public final class ModuleTargetAttribute
extends Attribute {
    public String platform;

    public ModuleTargetAttribute(String platform) {
        super("ModuleTarget");
        this.platform = platform;
    }

    public ModuleTargetAttribute() {
        this(null);
    }

    protected Attribute read(ClassReader classReader, int offset, int length, char[] charBuffer, int codeOffset, Label[] labels) {
        return new ModuleTargetAttribute(classReader.readUTF8(offset, charBuffer));
    }

    protected ByteVector write(ClassWriter classWriter, byte[] code, int codeLength, int maxStack, int maxLocals) {
        ByteVector byteVector = new ByteVector();
        byteVector.putShort(this.platform == null ? 0 : classWriter.newUTF8(this.platform));
        return byteVector;
    }
}

