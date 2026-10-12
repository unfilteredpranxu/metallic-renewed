/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.MetalDiag
 */
package com.metallum.client.metal.render;

import java.nio.ByteBuffer;
import java.util.HashMap;

public final class MetalDiag {
    private static int srcn = 0;
    private static final HashMap<Integer, Integer> viewTex = new HashMap();
    private static final HashMap<Integer, Integer> viewParam = new HashMap();
    private static final HashMap<String, Integer> lastView = new HashMap();
    private static final HashMap<String, Integer> lastTex = new HashMap();
    private static int statn = 0;

    public static void viewTexPut(Object object, Object object2, int n, int n2) {
        if (object != null && object2 != null) {
            viewTex.put(System.identityHashCode(object), System.identityHashCode(object2));
            int n3 = System.identityHashCode(object2);
            Integer n4 = (Integer)viewParam.get(n3);
            if (n4 == null || n4 != (n << 16 | n2 & 0xFFFF)) {
                viewParam.put(n3, n << 16 | n2 & 0xFFFF);
                System.out.println("[MetalDiag] viewCreated tex#" + n3 + " p=" + n + "," + n2);
            }
        }
    }

    public static void bind(String string, Object object) {
        int n = System.identityHashCode(object);
        Integer n2 = (Integer)lastView.get(string);
        if (n2 == null || n2 != n) {
            lastView.put(string, n);
            Integer n3 = (Integer)viewTex.get(n);
            int n4 = n3 == null ? -1 : n3;
            Integer n5 = (Integer)lastTex.get(string);
            System.out.println("[MetalDiag] bind '" + string + "' view#" + n + " tex#" + (n4 < 0 ? "?" : String.valueOf(n4)) + (String)(n2 == null ? "" : " (was view #" + n2 + ")"));
            lastTex.put(string, n4);
        }
    }

    public static void w2t(int n, int n2, int n3, int n4, int n5) {
        System.out.println("[MetalDiag] wtT2 tex#" + n + " v=" + n2 + "," + n3 + "," + n4 + "," + n5);
    }

    public static void bufStats(int n, ByteBuffer byteBuffer, int n2, int n3, int n4, int n5) {
        if (statn >= 200 || n2 <= 0 || n2 > 0x100000) {
            return;
        }
        ++statn;
        int n6 = Math.min(n2, byteBuffer.remaining());
        int n7 = 0;
        for (int i = 0; i < n6; ++i) {
            if (byteBuffer.get(i) == 0) continue;
            ++n7;
        }
        System.out.println("[MetalDiag] stat tex#" + n + " y=" + n3 + " w=" + n4 + " h=" + n5 + " size=" + n2 + " nonzero=" + n7 + "/" + n6);
    }

    public static void src(String string) {
        if (srcn < 3 && string != null) {
            ++srcn;
            String string2 = string.length() > 220 ? string.substring(0, 220) : string;
            System.out.println("[MetalDiag] shaderSrcHead>> " + string2.replace("\n", "\\n"));
        }
    }
}

