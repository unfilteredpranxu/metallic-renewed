import javassist.*;
import javassist.bytecode.*;

public class Disasm {
    public static void main(String[] args) throws Exception {
        ClassPool cp = new ClassPool(true);
        CtClass cc = cp.makeClass(new java.io.FileInputStream("C:/Users/User/.gemini/antigravity/scratch/air-ios/agent_extracted/classes262/com/metallum/client/metal/render/MetalCommandEncoder.class"));
        CtMethod m = cc.getMethod("awaitSubmitCompletion", "(JJ)Z");
        MethodInfo mi = m.getMethodInfo();
        CodeAttribute ca = mi.getCodeAttribute();
        CodeIterator ci = ca.iterator();
        while (ci.hasNext()) {
            int pos = ci.next();
            int op = ci.byteAt(pos);
            System.out.printf("%4d: %-15s (0x%02X)\n", pos, Mnemonic.OPCODE[op], op);
        }
    }
}