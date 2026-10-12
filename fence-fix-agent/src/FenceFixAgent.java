/*
 * Decompiled with CFR 0.152.
 */
import java.io.ByteArrayInputStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import javassist.CannotCompileException;
import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtField;
import javassist.CtMethod;
import javassist.CtNewMethod;
import javassist.LoaderClassPath;
import javassist.expr.ExprEditor;
import javassist.expr.MethodCall;

public class FenceFixAgent {
    private static final String TARGET = "com/metallum/client/metal/render/MetalCommandEncoder";

    public static void premain(String string, Instrumentation instrumentation) {
        final long l = Long.getLong("fencefix.capms", 16L);
        System.out.println("[FenceFixAgent] v4 initialized (submit wait cap=" + l + "ms)");
        instrumentation.addTransformer(new ClassFileTransformer(){

            @Override
            public byte[] transform(ClassLoader classLoader, String string, Class<?> clazz, ProtectionDomain protectionDomain, byte[] byArray) {
                if (!FenceFixAgent.TARGET.equals(string)) {
                    return null;
                }
                System.out.println("[FenceFixAgent] Intercepting MetalCommandEncoder class load...");
                try {
                    ClassPool classPool = new ClassPool(true);
                    if (classLoader != null) {
                        classPool.appendClassPath(new LoaderClassPath(classLoader));
                    }
                    CtClass ctClass = classPool.makeClass(new ByteArrayInputStream(byArray));
                    ctClass.addField(CtField.make("private static long fencefix_submits;", ctClass));
                    ctClass.addField(CtField.make("private static long fencefix_late;", ctClass));
                    ctClass.addField(CtField.make("private static long fencefix_last;", ctClass));
                    ctClass.addMethod(CtNewMethod.make("private static void fencefix_note(boolean ok) {  fencefix_submits++; if (!ok) fencefix_late++;  long now = System.currentTimeMillis();  if (now - fencefix_last >= 5000L) {    fencefix_last = now;    Runtime rt = Runtime.getRuntime();    long mb = (rt.totalMemory() - rt.freeMemory()) >> 20;    System.out.println(\"[FenceFixAgent] 5s stats: submits=\" + fencefix_submits      + \" gpuNotDoneInTime=\" + fencefix_late + \" heapUsedMB=\" + mb);    fencefix_submits = 0L; fencefix_late = 0L;  }}", ctClass));
                    final int[] nArray = new int[]{0};
                    CtMethod ctMethod = ctClass.getDeclaredMethod("submit");
                    ctMethod.instrument(new ExprEditor(){

                        @Override
                        public void edit(MethodCall methodCall) throws CannotCompileException {
                            if (methodCall.getMethodName().equals("awaitSubmitCompletion")) {
                                methodCall.replace("{ boolean ok = $proceed($1, Math.min($2, " + l + "L)); fencefix_note(ok); $_ = true; }");
                                nArray[0] = nArray[0] + 1;
                            }
                        }
                    });
                    System.out.println("[FenceFixAgent] Patched " + nArray[0] + " awaitSubmitCompletion call(s) in submit()");
                    ctMethod.addCatch("{ System.out.println(\"[FenceFixAgent] submit() exception suppressed: \" + $e); return; }", classPool.get("java.lang.IllegalStateException"));
                    int n = 0;
                    for (CtMethod ctMethod2 : ctClass.getDeclaredMethods()) {
                        if (!ctMethod2.getName().equals("awaitSubmitCompletion") || ctMethod2.getReturnType() != CtClass.booleanType) continue;
                        ctMethod2.addCatch("{ if ($e.getMessage() != null && $e.getMessage().indexOf(\"current submit\") >= 0) return false; throw $e; }", classPool.get("java.lang.IllegalStateException"));
                        ++n;
                    }
                    System.out.println("[FenceFixAgent] Guarded " + n + " awaitSubmitCompletion method(s) against current-submit fence checks");
                    byte[] byArray2 = ctClass.toBytecode();
                    ctClass.detach();
                    return byArray2;
                }
                catch (Throwable throwable) {
                    System.err.println("[FenceFixAgent] Failed to patch: " + String.valueOf(throwable));
                    throwable.printStackTrace();
                    return null;
                }
            }
        });
    }
}

