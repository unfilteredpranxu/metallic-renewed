/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.agent;

public class NopLogger {
    public static final NopLogger INSTANCE = new NopLogger();

    private NopLogger() {
    }

    public String getName() {
        return "NOP";
    }

    public boolean isTraceEnabled() {
        return false;
    }

    public void trace(String string) {
    }

    public void trace(String string, Object object) {
    }

    public void trace(String string, Object object, Object object2) {
    }

    public void trace(String string, Throwable throwable) {
    }

    public void trace(String string, Object ... objectArray) {
    }

    public boolean isDebugEnabled() {
        return false;
    }

    public void debug(String string) {
    }

    public void debug(String string, Object object) {
    }

    public void debug(String string, Object object, Object object2) {
    }

    public void debug(String string, Throwable throwable) {
    }

    public void debug(String string, Object ... objectArray) {
    }

    public boolean isInfoEnabled() {
        return false;
    }

    public void info(String string) {
    }

    public void info(String string, Object object) {
    }

    public void info(String string, Object object, Object object2) {
    }

    public void info(String string, Throwable throwable) {
    }

    public void info(String string, Object ... objectArray) {
    }

    public boolean isWarnEnabled() {
        return false;
    }

    public void warn(String string) {
    }

    public void warn(String string, Object object) {
    }

    public void warn(String string, Object object, Object object2) {
    }

    public void warn(String string, Throwable throwable) {
    }

    public void warn(String string, Object ... objectArray) {
    }

    public boolean isErrorEnabled() {
        return false;
    }

    public void error(String string) {
    }

    public void error(String string, Object object) {
    }

    public void error(String string, Object object, Object object2) {
    }

    public void error(String string, Throwable throwable) {
    }

    public void error(String string, Object ... objectArray) {
    }
}

