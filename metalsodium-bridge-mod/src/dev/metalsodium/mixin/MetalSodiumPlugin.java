/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  org.objectweb.asm.tree.ClassNode
 *  org.spongepowered.asm.mixin.extensibility.IMixinConfigPlugin
 *  org.spongepowered.asm.mixin.extensibility.IMixinInfo
 */
package dev.metalsodium.mixin;

import java.util.List;
import java.util.Set;
import org.objectweb.asm.tree.ClassNode;
import org.spongepowered.asm.mixin.extensibility.IMixinConfigPlugin;
import org.spongepowered.asm.mixin.extensibility.IMixinInfo;

public class MetalSodiumPlugin
implements IMixinConfigPlugin {
    public void onLoad(String string) {
        System.out.println("[MetalSodium] mixin config loaded (pkg=" + string + ")");
    }

    public String getRefMapperConfig() {
        return null;
    }

    public boolean shouldApplyMixin(String string, String string2) {
        return true;
    }

    public void acceptTargets(Set<String> set, Set<String> set2) {
        System.out.println("[MetalSodium] targets: " + String.valueOf(set));
    }

    public List<String> getMixins() {
        return null;
    }

    public void preApply(String string, ClassNode classNode, String string2, IMixinInfo iMixinInfo) {
        System.out.println("[MetalSodium] applying " + string2 + " -> " + string);
    }

    public void postApply(String string, ClassNode classNode, String string2, IMixinInfo iMixinInfo) {
        System.out.println("[MetalSodium] applied  " + string2 + " -> " + string);
    }
}

