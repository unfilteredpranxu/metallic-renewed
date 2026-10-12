# Angel Aura Amethyst (iOS) Remaster - Project Overview

## Project Introduction

This is a Minecraft launcher optimized for iOS/iPadOS and developed from the official Amethyst project. It aims to provide a smoother gaming experience, better localization support, and enhanced features such as mod and shader management, modpack imports, and automatic download-source switching.

## Technology Stack and Architecture

*   **Primary languages**: Objective-C (native iOS components), Java (game logic), C/C++ (some low-level libraries and graphics adapters)
*   **Build system**: The project uses `Makefile` and `CMake`.
*   **Build environment**: GitHub Actions (macOS 14), Xcode 15.4/16, iPhoneOS 17.5 SDK
*   **Minimum supported OS**: iOS 14.0
*   **Core dependencies**:
    *   **Java runtimes**: iOS ports of OpenJDK 8, 17, and 21.
    *   **Graphics adapters**: MetalANGLE (Metal to OpenGL ES), GL4ES (OpenGL ES to OpenGL), Mesa 3D, and MobileGlues.
    *   **AWT support**: Caciocavallo (a pure-Java implementation of Java AWT).
    *   **Other**: LWJGL (Java game development library), OpenAL (audio), and TouchController (touch controls).

## Directory Structure

*   `Natives/`: Native iOS code (Objective-C, C, C++), including UI controllers, the app entry point, and the Java VM launcher.
    *   `authenticator/`: Account authentication for Microsoft, local, and third-party accounts.
    *   `customcontrols/`: Custom control layouts.
    *   `external/`: Third-party dependencies (AFNetworking, AltKit, fishhook, MobileGlues, etc.).
    *   `input/`: Input handling (controllers, gyroscope, keyboard).
    *   `installer/`: Installers for Fabric, Forge, and modpacks.
*   `JavaApp/`: Java-side application logic and libraries.
*   `TouchController/`: TouchController static library for touch-control communication.
*   `depends/`: Build-time dependencies, such as Java runtimes.
*   `artifacts/`: Build output, including the final `.ipa` package and intermediate files.

## Build and Run

### Build Requirements

*   Build on macOS (macOS 14 recommended).
*   Xcode 15.4 or later.
*   Xcode command-line tools.
*   CMake, ldid, wget, and JDK 8.
*   On iOS 14.5 and later, TrollStore is recommended for the best installation experience.

### Build Commands

1.  **Prepare the environment**: Make sure all dependencies are installed.
2.  **Build**:
    ```bash
    make all
    ```
    This runs the following steps in order:
    *   `make dep_mg`: Build the MobileGlues dependency.
    *   `make native`: Build native libraries.
    *   `make java`: Build the Java application.
    *   `make jre`: Download and unpack the iOS JRE.
    *   `make assets`: Compile app assets (such as icons).
    *   `make payload`: Assemble the app bundle (`AngelAuraAmethyst.app`).
    *   `make package`: Create the final `.ipa` or `.tipa` package.

3.  **Optional build parameters**:
    *   `RELEASE=1`: Build a Release version.
    *   `SLIMMED=1`: Build a slimmed version (without the Java runtime).
    *   `TROLLSTORE_JIT_ENT=1`: Create a TrollStore-specific TIPA package.
    *   `PLATFORM=<value>`: Select a target platform (2=iOS, 3=tvOS, 7=iOS Simulator, 11=visionOS, etc.).

4.  **Deploy**:
    *   On a jailbroken device: `make deploy` (run on the device).
    *   With TrollStore: Install the generated `.tipa` file directly.
    *   With AltStore/SideStore: Install the generated `.ipa` file.

Note: Builds run on macOS 14 provided by GitHub Actions, not on this device.

### Startup Flow

1.  App startup (`main.m`): Check the environment, redirect logs, configure directories, and perform other initialization.
2.  UI initialization (`AppDelegate.m`, `SceneDelegate.m`): Set up the main window and initial view controller.
3.  JVM startup (`JavaLauncher.m`): Configure Java environment variables and JVM arguments, then load and start the Java VM.
4.  Java application: The JVM loads the `PojavLauncher` class and runs Minecraft's startup logic.

## Development Guidelines

*   **Code style**: Follow Apple's conventions for Objective-C and keep C/C++ style consistent with the project.
*   **Branch management**: Use Git for version control and develop features on `feature/` branches.
*   **Localization**: The project is fully localized in Chinese; localize text added in future development.
*   **Git commit convention**:
    
    ```
    <type>(<scope>): <subject>
    ```
    
    **type (required)**
    Indicates the category of the commit. Use one of these labels:
    - feat: New feature
    - fix/to: Bug fix, whether reported by QA or found during development
      - fix: Includes the change that fixes the issue; use for a one-commit fix.
      - to: Makes a change without fixing the issue yet; use for multi-commit work, followed by a `fix` commit.
    - docs: Documentation
    - style: Formatting changes that do not affect behavior
    - refactor: Code restructuring that adds no feature and fixes no bug
    - perf: Performance or user-experience improvement
    - test: Add tests
    - chore: Build process or auxiliary-tool changes
    - revert: Revert a previous version
    - merge: Merge code
    - sync: Sync bugs from the mainline or another branch
    
    **scope (optional)**
    Describes the area affected by the commit, such as the data, control, or view layer.
    Use `*` if the change affects more than one scope.
    
    **subject (required)**
    Briefly describes the purpose of the commit in no more than 50 characters.
    Use English and omit a trailing period or other punctuation.
    
    **Examples**:
    - fix(DAO): Add missing username to user query
    - feat(Controller): Implement user query API
    
    **Benefits**:
    - Makes it easier to trace commit history and understand what changed.
    - Encourages deliberate commits instead of bundling unrelated changes together.
    - Consistent commit messages can be used to generate a changelog automatically.

## Key Feature Modules

*   **Mod management** (`ModsManagerViewController`, `ModService`): View, enable/disable, and delete mods; search for mods by name.
*   **Mod downloads** (`ModVersionViewController`): Download mods from the Modrinth API and select versions.
*   **Shader management** (`ShadersManagerViewController`, `ShaderService`): View, enable/disable, and delete shader packs.
*   **Shader downloads** (`ShaderVersionViewController`): Download shader packs from the Modrinth API and select versions.
*   **Modpack import** (`ModpackImportViewController`, `ModpackImportService`): Import modpacks in ZIP format.
*   **Accounts** (`authenticator/`): Microsoft, local, demo, and third-party authentication accounts.
*   **Custom controls** (`customcontrols/`): Customize the in-game control layout.
*   **Preferences** (`PLPreferences`, `PLProfiles`): Manage settings and game profiles, with a card-based settings layout.
*   **Custom icons** (`CustomIconManager`): Customize the app icon (in development).
*   **Background wallpaper** (`BackgroundManager`): Customize the launcher's background.
*   **TouchController support** (`TouchControllerBridge`): Communicate with the TouchController mod through a local UDP proxy to provide touch controls on iOS.

## GitHub Actions Workflows

The project uses GitHub Actions for automated builds:

*   **development.yml**: Main build workflow, triggered by pushes to branches other than `l10n_main` or by pull requests.
*   **development_speedup.yml**: Faster build workflow.

Build artifacts:
*   `org.angelauramc.amethyst-ios.ipa`: Standard IPA package
*   `org.angelauramc.amethyst-ios-trollstore.tipa`: TrollStore-specific package
*   `AngelAuraAmethyst.dSYM`: Debug symbols

## Additional Information

1.  After changing source code, commit and push the changes to a GitHub branch to build and test the project.
2.  If network problems occur while pushing to GitHub, ask the user to disable their network proxy.
3.  This project is built with Xcode 15.4/16 and the iPhoneOS 17.5 SDK; the minimum supported OS is iOS 14.0.
4.  Use the Git username `herbrine8403` and email `weishixvn@outlook.com` when committing.
5.  The project supports iOS, tvOS, the iOS Simulator, and visionOS builds, selected with the `PLATFORM` parameter.
6.  When the renderer is set to Auto, the launcher automatically selects a suitable renderer, including MobileGlues.
7.  The JVM version is selected automatically based on the game version (Java 8/17/21).