/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.asm.commons;

import com.metallum.asm.Label;

public interface TableSwitchGenerator {
    public void generateCase(int var1, Label var2);

    public void generateDefault();
}

