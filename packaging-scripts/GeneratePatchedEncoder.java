import java.io.*;
import javassist.*;
import javassist.expr.*;

public class GeneratePatchedEncoder {
    public static void main(String[] args) throws Exception {
        File pristineFile = new File("C:/Users/User/.gemini/antigravity/scratch/air-ios/pristine_encoder.class");
        System.out.println("Reading pristine class: " + pristineFile.length() + " bytes");

        ClassPool pool = new ClassPool(true);
        CtClass ctClass = pool.makeClass(new FileInputStream(pristineFile));

        // 1. In submit(), cap awaitSubmitCompletion timeout or catch ISE
        CtMethod submitMethod = ctClass.getDeclaredMethod("submit");
        submitMethod.instrument(new ExprEditor() {
            @Override
            public void edit(MethodCall m) throws CannotCompileException {
                if (m.getMethodName().equals("awaitSubmitCompletion")) {
                    m.replace("{ boolean ok = $proceed($1, Math.min($2, 16L)); $_ = true; }");
                }
            }
        });
        submitMethod.addCatch("{ System.out.println(\"[FenceFix] submit() exception suppressed: \" + $e); return; }", pool.get("java.lang.IllegalStateException"));

        // 2. In awaitSubmitCompletion(), if current submit exception is thrown, catch and return false!
        int count = 0;
        for (CtMethod m : ctClass.getDeclaredMethods()) {
            if (m.getName().equals("awaitSubmitCompletion") && m.getReturnType() == CtClass.booleanType) {
                m.addCatch("{ if ($e.getMessage() != null && $e.getMessage().indexOf(\"current submit\") >= 0) return false; throw $e; }", pool.get("java.lang.IllegalStateException"));
                count++;
            }
        }
        System.out.println("Guarded " + count + " awaitSubmitCompletion method(s).");

        byte[] patchedBytes = ctClass.toBytecode();
        File outFile = new File("C:/Users/User/.gemini/antigravity/scratch/MetalCommandEncoder_fixed.class");
        try (FileOutputStream fos = new FileOutputStream(outFile)) {
            fos.write(patchedBytes);
        }
        System.out.println("Wrote patched class: " + outFile.length() + " bytes");
    }
}
