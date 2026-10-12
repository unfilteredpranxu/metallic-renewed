/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  org.spongepowered.asm.mixin.Mixin
 *  org.spongepowered.asm.mixin.injection.At
 *  org.spongepowered.asm.mixin.injection.Inject
 *  org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable
 */
package dev.metalsodium.mixin;

import dev.metalsodium.MetalSodium;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(targets={"net.caffeinemc.mods.sodium.client.gpu.device.context.DrawContext"})
public abstract class DrawContextMixin {
    @Inject(method={"create"}, at={@At(value="HEAD")}, cancellable=true)
    private static void metalsodium$create(CallbackInfoReturnable<Object> callbackInfoReturnable) {
        if (MetalSodium.isMetal()) {
            callbackInfoReturnable.setReturnValue(MetalSodium.newMetalDrawContext());
        }
    }
}

