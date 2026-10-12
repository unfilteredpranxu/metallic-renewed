# Building Metallic

This guide explains how to compile each component and produce the final `mettalic-alpha-1.1.ipa`.

---

## 1. Prerequisites

### For the iOS Launcher Application:
- macOS with Xcode 15+ installed (or an iOS toolchain / Theos).
- iOS 14.0+ SDK.
- Xcode Command Line Tools (`xcode-select --install`).

### For the Java Agents & Mods:
- JDK 21 or newer (`javac`, `jar`).
- Fabric Loom / Gradle (for `metalsodium` mod).

---

## 2. Building the iOS Application

From the `ios-app/` directory:

```bash
cd ios-app
# Using the bundled Makefile
make
```

Or open `Amethyst.xcodeproj` in Xcode:
1. Select target `AngelAuraAmethyst`.
2. Set configuration to `Release`.
3. Choose destination `Any iOS Device (arm64)`.
4. Run **Product > Archive** or **Product > Build**.

The compiled `.app` bundle will be generated in `build/Release-iphoneos/AngelAuraAmethyst.app`.

---

## 3. Building the Java Agents

### Pure Metal Renderer (`metal-renderer-backend`)
```bash
cd metal-renderer-backend
javac -d bin -cp "path/to/blaze3d.jar:path/to/minecraft.jar" $(find src -name "*.java")
jar cvfe metallum_agent.jar com.metallum.agent.MetallumAgent -C bin .
```

### Standalone Fence Fix Agent (`fence-fix-agent`)
```bash
cd fence-fix-agent
javac -d bin -cp "path/to/javassist.jar" src/FenceFixAgent.java
jar cvfe fence_fix_agent.jar FenceFixAgent -C bin .
```

---

## 4. Building the Metal Sodium Bridge Mod (`metalsodium-bridge-mod`)

```bash
cd metalsodium-bridge-mod
# Compile classes against Sodium 0.9.x and Minecraft Blaze3D
javac -d bin -cp "sodium-fabric-0.9.2.jar:minecraft-26.2.jar" $(find src -name "*.java")
cp fabric.mod.json bin/
cp metalsodium.mixins.json bin/
jar cvf metalsodium-0.1.2.jar -C bin .
```

---

## 5. Assembling and Packaging the IPA

To produce the final iOS `.ipa` with proper Unix executable permissions (`0755`):

```powershell
cd packaging-scripts
dotnet run FixZipAndWrap.cs
```

This ensures:
1. All Mach-O binaries (`AngelAuraAmethyst`, `libjvm.dylib`, `*.dylib`) have Unix executable mode `0755`.
2. The zip Central Directory Host OS attribute is set to Unix (`0x03`).
3. Sideloaders (TrollStore, SideStore, AltStore, LiveContainer) recognize all binaries as executable without permission errors.
