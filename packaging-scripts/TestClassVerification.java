import java.io.*;
import java.lang.reflect.*;

public class TestClassVerification {
    public static void main(String[] args) throws Exception {
        File file = new File("C:/Users/User/.gemini/antigravity/scratch/air-ios/pristine_encoder.class");
        byte[] bytes = new byte[(int)file.length()];
        try (DataInputStream dis = new DataInputStream(new FileInputStream(file))) {
            dis.readFully(bytes);
        }

        // Patch offset 0x5E7F
        // Original: BB 00 89 59 13 03 02 B7 00 8E BF (11 bytes)
        // Replace with: 03 AC 00 00 00 00 00 00 00 00 00 (iconst_0, ireturn, 9x nop)
        bytes[0x5E7F] = 0x03; // iconst_0
        bytes[0x5E80] = (byte)0xAC; // ireturn
        for (int i = 0x5E81; i <= 0x5E89; i++) {
            bytes[i] = 0x00; // nop
        }

        File outFile = new File("C:/Users/User/.gemini/antigravity/scratch/MetalCommandEncoder_clean.class");
        try (FileOutputStream fos = new FileOutputStream(outFile)) {
            fos.write(bytes);
        }
        System.out.println("Saved clean patched class: " + outFile.length() + " bytes.");

        // Now test loading this class in a custom ClassLoader with verification!
        ClassLoader cl = new ClassLoader() {
            @Override
            protected Class<?> findClass(String name) throws ClassNotFoundException {
                if (name.equals("com.metallum.client.metal.render.MetalCommandEncoder")) {
                    return defineClass(name, bytes, 0, bytes.length);
                }
                return super.findClass(name);
            }
        };

        try {
            // Load and initialize
            Class<?> clazz = Class.forName("com.metallum.client.metal.render.MetalCommandEncoder", false, cl);
            System.out.println("Class loaded successfully without VerifyError: " + clazz.getName());
            System.out.println("TEST PASSED!");
        } catch (Throwable t) {
            System.err.println("TEST FAILED with error: " + t);
            t.printStackTrace();
        }
    }
}
