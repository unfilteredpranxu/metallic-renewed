/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.shaded.asm;

import com.metallum.shaded.asm.Frame;
import com.metallum.shaded.asm.Label;
import com.metallum.shaded.asm.Symbol;
import com.metallum.shaded.asm.SymbolTable;

final class CurrentFrame
extends Frame {
    CurrentFrame(Label owner) {
        super(owner);
    }

    void execute(int opcode, int arg, Symbol symbolArg, SymbolTable symbolTable) {
        super.execute(opcode, arg, symbolArg, symbolTable);
        Frame successor = new Frame(null);
        this.merge(symbolTable, successor, 0);
        this.copyFrom(successor);
    }
}

