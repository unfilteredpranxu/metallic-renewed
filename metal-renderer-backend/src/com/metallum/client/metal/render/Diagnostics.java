/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.Diagnostics
 */
package com.metallum.client.metal.render;

import com.metallum.Metallum;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public final class Diagnostics {
    private static final boolean ENABLED = Boolean.parseBoolean(System.getProperty("metallum.diag", "false"));
    private static final Set<String> ONCE = ConcurrentHashMap.newKeySet();
    private static final ConcurrentHashMap<String, Long> LAST_RUN = new ConcurrentHashMap();

    private Diagnostics() {
    }

    public static boolean isEnabled() {
        return ENABLED;
    }

    static void once(String key, String format, Object ... args) {
        if (ENABLED && ONCE.add(key)) {
            Metallum.LOGGER.error("[diag] " + format, args);
        }
    }

    public static boolean shouldRun(String key, long intervalMs) {
        if (!ENABLED) {
            return false;
        }
        long now = System.nanoTime();
        Long last = (Long)LAST_RUN.get(key);
        if (last != null && now - last < intervalMs * 1000000L) {
            return false;
        }
        LAST_RUN.put(key, now);
        return true;
    }
}

