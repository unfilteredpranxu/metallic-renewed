/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.MetalMslSanitizer
 */
package com.metallum.client.metal.render;

import java.util.regex.Pattern;

public final class MetalMslSanitizer {
    private static final Pattern MSL_SAMPLER_PARAM_PATTERN = Pattern.compile("(\\btexture2d\\s*<[^>]+>\\s+)sampler\\b");
    private static final Pattern MSL_SAMPLER_USE_PATTERN = Pattern.compile("\\bsampler\\.sample\\b");

    private MetalMslSanitizer() {
    }

    public static String sanitizeMsl(String msl) {
        String out = MSL_SAMPLER_PARAM_PATTERN.matcher(msl).replaceAll("$1samplerTex");
        return MSL_SAMPLER_USE_PATTERN.matcher(out).replaceAll("samplerTex.sample");
    }
}

