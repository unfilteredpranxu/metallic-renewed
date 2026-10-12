/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.DiagLog
 *  com.metallum.client.metal.render.RotationThrottle
 */
package com.metallum.client.metal.render;

import com.metallum.client.metal.render.DiagLog;

/*
 * Exception performing whole class analysis ignored.
 */
public final class RotationThrottle {
    private static final double BUCKET_SLOW = 30.0;
    private static final double BUCKET_MEDIUM = 10.0;
    private static final double BUCKET_FAST = 5.0;
    private static double curPitch;
    private static double curYaw;
    private static long curBlockX;
    private static long curBlockZ;
    private static long curNanos;
    private static double prevYaw;
    private static long prevNanos;
    private static boolean hasPrev;
    private static double speedEstimate;
    private static int lastBucketX;
    private static int lastBucketY;
    private static double lastBucketDegrees;
    private static long lastBlockX;
    private static long lastBlockZ;
    private static long throttledHits;
    private static long throttledSkips;
    private static long throttledReportNanos;

    private RotationThrottle() {
    }

    public static void snapshot(float pitch, float yaw, double posX, double posZ) {
        long now = System.nanoTime();
        if (hasPrev) {
            double elapsed = (double)(now - prevNanos) / 1.0E9;
            if (elapsed > 0.0 && elapsed < 0.5) {
                double degPerSec = Math.abs((double)yaw - prevYaw) / elapsed;
                speedEstimate = speedEstimate * 0.9 + degPerSec * 0.1;
            }
        } else {
            hasPrev = true;
        }
        prevYaw = yaw;
        prevNanos = now;
        curPitch = pitch;
        curYaw = yaw;
        curBlockX = (long)Math.floor(posX);
        curBlockZ = (long)Math.floor(posZ);
        curNanos = now;
    }

    private static double bucketDegrees() {
        double s = speedEstimate;
        if (s < 30.0) {
            return 30.0;
        }
        if (s < 120.0) {
            return 10.0;
        }
        return 5.0;
    }

    public static boolean shouldThrottle() {
        boolean throttled;
        double bucket = RotationThrottle.bucketDegrees();
        int bucketX = (int)Math.floor(curPitch / bucket);
        int bucketY = (int)Math.floor(curYaw / bucket);
        boolean bl = throttled = bucket == lastBucketDegrees && bucketX == lastBucketX && bucketY == lastBucketY && curBlockX == lastBlockX && curBlockZ == lastBlockZ;
        if (throttled) {
            ++throttledHits;
        } else {
            ++throttledSkips;
        }
        long now = System.nanoTime();
        if (throttledHits + throttledSkips >= 300L && now - throttledReportNanos > 5000000000L) {
            throttledReportNanos = now;
            DiagLog.log((String)"[diag] rot-throttle hits=%d skip=%d", (Object[])new Object[]{throttledHits, throttledSkips});
            throttledHits = 0L;
            throttledSkips = 0L;
        }
        return throttled;
    }

    public static void record() {
        double bucket;
        lastBucketDegrees = bucket = RotationThrottle.bucketDegrees();
        lastBucketX = (int)Math.floor(curPitch / bucket);
        lastBucketY = (int)Math.floor(curYaw / bucket);
        lastBlockX = curBlockX;
        lastBlockZ = curBlockZ;
    }

    public static double currentPitch() {
        return curPitch;
    }

    public static double currentYaw() {
        return curYaw;
    }

    static {
        lastBucketX = Integer.MIN_VALUE;
        lastBucketY = Integer.MIN_VALUE;
    }
}

