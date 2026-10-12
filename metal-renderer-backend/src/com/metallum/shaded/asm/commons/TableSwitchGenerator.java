/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.shaded.asm.commons;

import com.metallum.shaded.asm.Label;

public interface TableSwitchGenerator {
    public void generateCase(int var1, Label var2);

    public void generateDefault();
}

