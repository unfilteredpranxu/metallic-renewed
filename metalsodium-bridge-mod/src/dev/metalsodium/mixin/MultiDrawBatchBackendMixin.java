/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  net.caffeinemc.mods.sodium.client.gpu.device.backend.DrawBackend
 *  org.spongepowered.asm.mixin.Mixin
 *  org.spongepowered.asm.mixin.injection.At
 *  org.spongepowered.asm.mixin.injection.Redirect
 */
package dev.metalsodium.mixin;

import dev.metalsodium.MetalSodium;
import net.caffeinemc.mods.sodium.client.gpu.device.backend.DrawBackend;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(targets={"net.caffeinemc.mods.sodium.client.gpu.device.batch.MultiDrawBatch"})
public abstract class MultiDrawBatchBackendMixin {
    @Redirect(method={"newBatch"}, require=0, at=@At(value="FIELD", opcode=178, target="Lnet/caffeinemc/mods/sodium/client/gpu/device/backend/DrawBackend;BACKEND:Lnet/caffeinemc/mods/sodium/client/gpu/device/backend/DrawBackend;"))
    private static DrawBackend metalsodium$backend() {
        return MetalSodium.isMetal() ? DrawBackend.VK_INDIRECT : DrawBackend.BACKEND;
    }
}

