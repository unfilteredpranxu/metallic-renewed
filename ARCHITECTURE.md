# Metallic Architecture & Engineering Guide

## 1. Graphics Pipeline Overview

Metallic delivers pure, direct Apple Metal 3 acceleration for Minecraft on iOS.

```
+-----------------------------------------------------------+
|                      Minecraft 26.2                       |
|                   (Blaze3D Engine Core)                   |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|              Sodium 0.9.x Rendering Engine                |
|           Chunk Mesh Builder & Draw Dispatcher            |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|          MetalSodium Bridge Mod (metalsodium)             |
|   - Forces DrawBackend to VK_INDIRECT                     |
|   - Provides MetalDrawContext for push constant updates   |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|         Pure Metal 3 Renderer ("Metal by Tok")            |
|                   (com.metallum.*)                        |
|   - MetalBackend / MetalDevice                            |
|   - MetalCommandEncoder (safe fence synchronization)      |
|   - MetalRenderPass / MetalSurface (CAMetalLayer)         |
|   - MetalCrossShaderCompiler (SPIRV-Cross -> MSL)         |
+-----------------------------+-----------------------------+
                              |
                              v
+-----------------------------------------------------------+
|                   Apple Metal 3 Framework                 |
|             (Native iOS GPU Hardware Driver)              |
+-----------------------------------------------------------+
```

---

## 2. Fence Synchronization & Crash Prevention

### The Problem
During frame completion, Sodium's `GpuBufferPool.tryRecycleBuffers()` calls `fence.awaitCompletion(0L)` to check if buffers from previous frames can be reused.

Under Metallum's default implementation, `MetalCommandEncoder.awaitSubmitCompletion()` executed:
```java
if (submitIndex == this.currentSubmitIndex) {
    throw new IllegalStateException("Cannot wait on a fence for the current submit");
}
```
Because the current frame's command buffer was still actively recording, this threw an `IllegalStateException`, crashing Sodium and exiting Minecraft.

### The Solution: Non-Throwing Fence Query
Instead of throwing an exception, querying a fence for an uncommitted submit index returns `false`:
```java
if (submitIndex == this.currentSubmitIndex) {
    return false; // Not ready yet, keep in pendingRecycle list!
}
```

In bytecode, the exception-throwing block:
```
BB 00 89  new <java/lang/IllegalStateException>
59        dup
13 03 02  ldc "Cannot wait on a fence for the current submit"
B7 00 8E  invokespecial <java/lang/IllegalStateException.<init>(Ljava/lang/String;)V>
BF        athrow
```
is cleanly replaced with:
```
03        iconst_0
AC        ireturn
00*9      9x nop
```
This preserves the exact StackMapTable offset `tag 0x14` (`same_frame`) required by Java 21 / 25 bytecode verification.

---

## 3. UI Layout Architecture

The native iOS interface is structured across specialized `UIViewController` subclasses in `ios-app/Natives/`:

1. **`LauncherCardLayoutViewController`:**
   - Central container replacing the legacy 3-pane split view.
   - Embeds the top horizontal pill (`LauncherMenuViewController`) and the right launcher sidebar (`LauncherRightPanelViewController`).

2. **`LauncherMenuViewController`:**
   - Configured as a floating capsule navigation pill at the top of the screen.
   - Contains navigation items: Home, Help, Settings, Storage, Mods, Downloads.

3. **`LauncherRightPanelViewController`:**
   - Floating right action panel.
   - Styled with pink launch buttons (`#FF69B4` / `#FF6EA7`).
   - Houses the profile avatar, version indicators, and game launch triggers.

4. **`BingWallpaper` Neutralization:**
   - Prevents auto-downloading Bing autumn wallpapers by directing remote image requests to local loopback (`127.0.0.1:9`).
   - Sets a consistent, minimalist dark slate background (`#0A0A0A`).
