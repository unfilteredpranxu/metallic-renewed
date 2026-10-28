# Metallic Launcher

**Metallic Launcher** is the Metallic iOS/iPadOS launcher. The component map below describes the original Alpha 1.1 source export; current UI checkpoints, build limitations and device-validation status are recorded in [the refinement tracker](docs/METALLIC_RENEWED_UI_REFINEMENT_TRACKER.md).

---

## 📁 Repository Directory Structure

```text
metallic-alpha-1.1-source-code/
├── README.md                           # This overview and component map
├── ARCHITECTURE.md                     # Deep dive into graphics pipelines, agents & UI architecture
├── BUILDING.md                         # Build instructions for iOS App, Java Agents & Mods
│
├── ios-app/                            # Native iOS Application (Xcode Project & C++/Obj-C/Swift codebase)
│   ├── Amethyst.xcodeproj/             # Full Xcode Project configuration
│   ├── Natives/                        # iOS Objective-C / Swift / C++ source files
│   │   ├── LauncherCardLayoutViewController.m # Card Layout controller
│   │   ├── LauncherRightPanelViewController.m# Right Action Panel (Pink launch buttons)
│   │   ├── LauncherMenuViewController.m       # Top Horizontal Navigation Pill
│   │   ├── LauncherNewsViewController.m       # News & Announcement banner controller
│   │   ├── SurfaceViewController.m            # OpenGL / Vulkan / Metal render surface
│   │   └── ...
│   ├── JavaApp/                        # Launcher Java entrypoint, Caciocavallo, and LWJGL runtime bridges
│   ├── ThirdParty/                     # Bundled dependencies (AltKit, UnzipKit, DBNumberedSlider, etc.)
│   ├── Makefile                        # CLI build Makefile for iOS app bundle
│   └── entitlements.*.xml              # Entitlements for TrollStore, SideStore, and Sideloading
│
├── metal-renderer-backend/             # Pure Apple Metal 3 Renderer Backend (Java & MTL)
│   ├── MetalCommandEncoder_clean.class # Clean bytecode with non-throwing fence wait
│   └── src/com/metallum/
│       ├── client/metal/render/        # Metal graphics backend implementation
│       │   ├── MetalBackend.java       # Primary Metal GpuDevice backend
│       │   ├── MetalCommandEncoder.java# Command encoder with clean fence sync
│       │   ├── MetalDevice.java        # Apple Metal device interface
│       │   ├── MetalFence.java         # GPU synchronization fence wrapper
│       │   ├── MetalRenderPass.java    # Metal render command encoder pass
│       │   ├── MetalSurface.java       # Metal CAMetalLayer drawable surface
│       │   ├── MetalGpuBuffer.java     # Metal MTLBuffer allocation & management
│       │   ├── MetalDrawContext.java   # Chunk indirect draw submission context
│       │   ├── MetalCrossShaderCompiler.java # SPIRV-Cross to MSL shader compiler
│       │   ├── MetalTransientMemory.java # Transient uniform & push constant ring buffer
│       │   ├── mtl/                    # Java bindings for Metal enum types & descriptors
│       │   └── bridge/                 # Metal native JNI bridging
│       ├── shims/                      # Compatibility shims for Blaze3D / Minecraft rendering
│       └── agent/                      # MetallumAgent Java agent runtime transformer
│
├── fence-fix-agent/                    # Standalone Fence Fix Java Agent
│   └── src/
│       └── FenceFixAgent.java          # Dynamic Javassist transformer suppressing current-submit fence crashes
│
├── metalsodium-bridge-mod/             # Fabric Mod bridging Sodium 0.9.x to Metallum
│   ├── fabric.mod.json                 # Fabric mod metadata
│   ├── metalsodium.mixins.json         # Mixin configuration
│   └── src/
│       ├── dev/metalsodium/
│       │   ├── MetalSodium.java        # Backend detection & indirect context provider
│       │   └── mixin/                  # Sodium mixins:
│       │       ├── DrawBackendMixin.java         # Directs Sodium to VK_INDIRECT on Metal
│       │       ├── DrawContextNewMixin.java      # Instantiates MetalDrawContext
│       │       ├── DrawContextMixin.java         # Fallback DrawContext factory
│       │       ├── DrawContextBackendMixin.java  # Staging buffer backend redirect
│       │       ├── MultiDrawBatchBackendMixin.java # MultiDraw batch backend redirect
│       │       └── StagingBufferMixin.java       # Mapped staging buffer redirect
│       └── com/metallum/client/metal/render/
│           └── MetalDrawContext.java   # Optimized chunk push constant update routine
│
├── bundle-templates/                   # iOS App Bundle Configuration & Assets
│   ├── Info.plist                      # Version 1.1, "metallic", Card Layout default
│   ├── custom_layout.json              # Card layout JSON schema & defaults
│   ├── announcements-fallback.json     # Sanitized offline fallback announcements
│   ├── help-faq.json                   # In-app help documentation
│   ├── glfw_keycodes.plist             # Keyboard & controller key mappings
│   ├── JIT26Script.js                  # JIT enablement script for iOS 14-17
│   ├── UniversalJIT26.js               # Universal JIT runner
│   └── UniversalJIT26Extension.js      # JIT extension script
│
└── packaging-scripts/                  # IPA Packaging & Bytecode Modification Scripts
    ├── GeneratePatchedEncoder.java     # Bytecode patcher preserving Java 21 StackMapTable
    ├── Disasm.java                     # Bytecode inspection and disassembler tool
    ├── TestClassVerification.java      # In-JVM classfile verifier
    ├── FixZipAndWrap.cs                # C# tool creating IPAs with valid Unix 0755 permissions
    └── PackageIpa.ps1                  # PowerShell end-to-end packaging pipeline
```

---

## 🚀 Key Highlights of Metallic Alpha 1.1

1. **Pure Apple Metal 3 Architecture ("Metal by Tok"):**
   - Zero translation layers: runs directly against Apple Silicon Metal API (`MTLDevice`, `MTLCommandQueue`, `MTLRenderCommandEncoder`).
   - Does NOT use MoltenVK or Vulkan translation layers for Minecraft 26.2.

2. **Clean Sodium Synchronization & Non-Throwing Fences:**
   - Bytecode-level fix in `MetalCommandEncoder.class` replacing the `IllegalStateException: Cannot wait on a fence for the current submit` with `iconst_0; ireturn;` (`false`).
   - Guarantees 100% compliance with Java 21+ `StackMapTable` verifier rules without needing `-noverify`.
   - Allows Sodium's `GpuBufferPool.tryRecycleBuffers()` to defer recycling until the command buffer has finished rendering.

3. **Modern Card Layout:**
   - Defaulted to the unified Card Layout (`LauncherCardLayoutViewController`).
   - Top floating horizontal navigation pill.
   - Clean user dashboard with grey avatar and welcome card.
   - Distinctive pink action buttons (`#FF69B4` / `#FF6EA7`).
   - Remote advertisement URLs neutralized to maintain a clean interface.
