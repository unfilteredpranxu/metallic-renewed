/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.metallum.client.metal.render.DiagLog
 */
package com.metallum.client.metal.render;

import com.metallum.Metallum;
import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.OpenOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.FileAttribute;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;

/*
 * Exception performing whole class analysis ignored.
 */
public final class DiagLog {
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH:mm:ss.SSS");
    private static final boolean ENABLED = Boolean.parseBoolean(System.getProperty("metallum.diag", "false"));
    private static final long WINDOW_SECONDS = Long.parseLong(System.getProperty("metallum.diag.window", "120"));
    private static final long START_NANOS = System.nanoTime();
    private static final Object LOCK = new Object();
    private static Path logPath;

    private DiagLog() {
    }

    public static void init(Path logsDir) {
        if (!ENABLED) {
            return;
        }
        try {
            Files.createDirectories(logsDir, new FileAttribute[0]);
            logPath = logsDir.resolve("metallum-diag.log");
            DiagLog.writeRaw((String)"==== Metallum diag start ====");
        }
        catch (IOException e) {
            logPath = null;
            Metallum.LOGGER.error("[diag] DiagLog init failed (fallback: no diag file): {}", (Object)e.toString());
        }
    }

    public static void log(String format, Object ... args) {
        Object message;
        if (!ENABLED || logPath == null) {
            return;
        }
        if (WINDOW_SECONDS > 0L && System.nanoTime() - START_NANOS > WINDOW_SECONDS * 1000000000L) {
            return;
        }
        try {
            message = args.length == 0 ? format : String.format(format, args);
        }
        catch (RuntimeException e) {
            message = format + " [diag-format-error: " + String.valueOf(e) + "]";
        }
        DiagLog.writeRaw((String)(LocalTime.now().format(TIME) + " " + (String)message));
    }

    /*
     * WARNING - Removed try catching itself - possible behaviour change.
     */
    private static void writeRaw(String line) {
        try {
            Object object = LOCK;
            synchronized (object) {
                Files.writeString((Path)logPath, (CharSequence)(line + System.lineSeparator()), (Charset)StandardCharsets.UTF_8, (OpenOption[])new OpenOption[]{StandardOpenOption.CREATE, StandardOpenOption.APPEND, StandardOpenOption.WRITE});
            }
        }
        catch (IOException e) {
            logPath = null;
            Metallum.LOGGER.error("[diag] DiagLog write failed (disabled): {}", (Object)e.toString());
        }
    }
}

