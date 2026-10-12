/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  net.caffeinemc.mods.sodium.client.gpu.device.context.VKIndirectContext
 *  org.spongepowered.asm.mixin.Mixin
 *  org.spongepowered.asm.mixin.injection.At
 *  org.spongepowered.asm.mixin.injection.Redirect
 */
package dev.metalsodium.mixin;

import com.metallum.client.metal.render.MetalDrawContext;
import dev.metalsodium.MetalSodium;
import net.caffeinemc.mods.sodium.client.gpu.device.context.VKIndirectContext;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(targets={"net.caffeinemc.mods.sodium.client.gpu.device.context.DrawContext"})
public abstract class DrawContextNewMixin {
    @Redirect(method={"create"}, require=0, at=@At(value="NEW", target="net/caffeinemc/mods/sodium/client/gpu/device/context/VKIndirectContext"))
    private static VKIndirectContext metalsodium$newContext() {
        if (MetalSodium.isMetal()) {
            System.out.println("[MetalSodium] DrawContext.create -> MetalDrawContext");
            return new MetalDrawContext();
        }
        return new VKIndirectContext();
    }
}

