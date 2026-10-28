<div align="center">
  <img src="Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png" alt="Metallic icon" width="120" style="border-radius: 24px;">
</div>

<h1 align="center">Metallic</h1>
<p align="center"><sub>Metallic Launcher</sub></p>

> Metallic retains the Amethyst/Air and PojavLauncher foundation. The inherited upstream documentation, badges and links below describe those source projects, not a verified Metallic release. Contributor credits and third-party licenses remain applicable. Current status: [UI refinement tracker](../docs/METALLIC_RENEWED_UI_REFINEMENT_TRACKER.md).

<div align="center">
  <img alt="Build status" src="https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/actions/workflows/development.yml/badge.svg?branch=main">
  <img alt="Downloads" src="https://img.shields.io/github/downloads/herbrine8403/Amethyst-iOS-MyRemastered/total?label=Downloads&style=flat">
  <img alt="Version" src="https://img.shields.io/github/v/release/herbrine8403/Amethyst-iOS-MyRemastered?style=flat">
  <img alt="License" src="https://img.shields.io/github/license/herbrine8403/Amethyst-iOS-MyRemastered?style=flat">
  <img alt="Last commit" src="https://img.shields.io/github/last-commit/herbrine8403/Amethyst-iOS-MyRemastered?color=c78aff&label=last%20commit&style=flat">
</div>

<p align="center">
  <a href="./README.md">English</a> | <a href="./README_CN.md">Chinese</a>
</p>

> [!IMPORTANT]
> **This is the only official Air repository:** [herbrine8403/Amethyst-iOS-MyRemastered](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered).
> Beware of unofficial forks or mirrors using the name "Air." Verify that the repository owner is [@herbrine8403](https://github.com/herbrine8403) and that the URL matches the link above.

---

A premium Minecraft: Java Edition launcher for iOS and iPadOS, extensively reworked from the official Amethyst project. It offers a refined mobile experience, comprehensive mod management, intelligent renderer selection, and deep platform integration.

---

## Contents

- [Key Features](#key-features)
- [Getting Started](#getting-started)
  - [Device Requirements](#device-requirements)
  - [Sideloading Preparation](#sideloading-preparation)
  - [Installation Steps](#installation-steps)
  - [Enable JIT](#enable-jit)
- [Contributors](#contributors)
- [Third-Party Components](#third-party-components)
- [Donations](#donations)

## Key Features

- **Modern UI** -- A thoroughly polished interface with a contemporary design.
- **Resource management and downloads** -- Browse, enable, disable, and delete mods, shader packs, resource packs, and other resources; download from Modrinth and CurseForge.
- **Modpack import** -- Import ZIP modpacks directly in the launcher.
- **Download-source switching** -- Switch between Mojang's official servers, BMCLAPI mirrors, and other sources for the best download speed.
- **Full Chinese localization** -- A fully translated interface for a native Chinese-language experience.
- **Account restrictions lifted** -- Use local, demo, or third-party authentication accounts to download and play without a Microsoft account.
- **Multiple accounts** -- Seamlessly switch between Microsoft, local, and third-party authentication accounts.
- **Automatic renderer selection** -- When set to Auto, the launcher selects the best rendering backend, including MobileGlues and MoltenVK.
- **Minecraft 26.X support** -- Adds experimental support for Minecraft 26.X.
- **Custom mouse pointers** -- Customize the virtual mouse pointer in settings.
- **TouchController support** -- Communicate with the TouchController mod over UDP or XCFramework for comprehensive touch controls on iOS.
- **Deep AI integration** -- In development, with the goal of letting AI manage the entire launcher, including resource downloads and instance management.
- ... and much more to explore!


> [!NOTE]
> There are currently no plans to port this remaster to Android. The Android ecosystem already has excellent launchers, such as [ZalithLauncher2](https://github.com/ZalithLauncher/ZalithLauncher2) and [Fold Craft Launcher](https://github.com/FCL-Team/FoldCraftLauncher). For the official Android version, visit [Amethyst-Android](https://github.com/AngelAuraMC/Amethyst-Android).
> (What happened to my ShardLauncher halfway through...?)

## Getting Started

For full documentation, see the [official Amethyst Wiki](https://wiki.angelauramc.dev/wiki/getting_started/INSTALL.html#ios) or the [Bilibili tutorial video](https://b23.tv/KyxZr12). The following is a quick guide.

### Device Requirements

| Tier | iOS Version | Supported Devices |
|------|----------|----------|
| **Minimum** | iOS 14.0+ | iPhone 6s+, iPad (5th generation)+, iPad Air 2+, iPad mini 4+, all iPad Pro models, iPod touch (7th generation) |
| **Recommended** | iOS 14.5+ | iPhone XS+ (excluding XR/SE 2nd generation), iPad (10th generation)+, iPad Air 4+, iPad mini 6+, iPad Pro (excluding 9.7-inch model) |

> [!CAUTION]
> iOS 14.0–14.4.2 has known serious compatibility issues. **Upgrading to iOS 14.5 or later is strongly recommended.** iOS 17.x and 18.x are supported, but setting up JIT for the first time requires a computer (see the [official JIT guide](https://wiki.angelauramc.dev/wiki/faq/ios/JIT.html#what-are-the-methods-to-enable-jit)). iOS 26.x can install and run the app, but has not been specifically adapted and may have unpredictable issues.

### Sideloading Preparation

Prefer a tool that supports "permanent signing + automatic JIT":

1. **TrollStore** *(recommended)* -- Permanently signs apps, enables JIT automatically, and raises the memory limit. Compatible with some iOS versions. [Download from the official repository](https://github.com/opa334/TrollStore).
2. **AltStore / SideStore** *(alternatives)* -- Requires periodic re-signing; initial setup requires a computer and Wi-Fi. Compatible only with **development certificates** (the `com.apple.security.get-task-allow` entitlement is required for JIT). Distribution-certificate signing services are not supported.

> [!WARNING]
> Download sideloading tools and IPA files only from official or trusted sources. The authors are not responsible for device issues caused by unofficial software. Jailbroken devices support permanent signing, but jailbreaking a daily-use device is not recommended.

### Installation Steps

<details>
<summary><b>Stable release (TrollStore)</b></summary>

1. Go to [Releases](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/releases) and download the `.tipa` package.
2. Open it with TrollStore from the system share sheet to install it.
</details>

<details>
<summary><b>Stable release (AltStore / SideStore)</b></summary>

1. Go to [Releases](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/releases) and download the `.ipa` package.
2. Import the IPA using the standard process for your sideloading tool.
</details>

<details>
<summary><b>Nightly test build (daily build)</b></summary>

> [!CAUTION]
> Test builds may have serious issues, including crashes or failure to launch. For development and testing only.

1. Go to [GitHub Actions](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/actions) and download the latest IPA artifact.
2. Import the IPA using a sideloading tool such as AltStore or SideStore.
</details>

### Enable JIT

JIT (just-in-time compilation) is essential for smooth gameplay. Choose the method that suits your setup:

| Tool | External device required | Wi-Fi required | Automatic | Notes |
|------|:---:|:---:|:---:|-------|
| TrollStore | No | No | Yes | Preferred option; no extra steps |
| AltStore | Yes | Yes | Yes | AltServer must run on the local network |
| SideStore | First setup only | First setup only | No | No device/network needed after setup |
| StikDebug | First setup only | First setup only | Yes | No device/network needed after setup |
| Jitterbug | Yes (without VPN) | Yes | No | Must be triggered manually |
| Jailbroken device | No | No | Yes | Supported automatically at the system level |

## Contributors

- [@yitenchen123](https://github.com/yitenchen123) -- Project maintainer
- [EternityQwQ](https://github.com/EternityQwQ) -- Added Metal Universal Mod support, enabling the launcher to render Minecraft with Metal
- [@LanRhyme](https://github.com/LanRhyme) -- iOS 26 compatibility and logging improvements
- [@WeiErLiTeo](https://github.com/WeiErLiTeo) -- Integrated mod downloads, improved TouchController, and added double-finger long-press to open the keyboard
- [@Li2548](https://github.com/Li2548) -- Upstream synchronization and maintenance
- [@Gsjsjzhznsz](https://github.com/Gsjsjzhznsz) -- SDL3 presentation-chain adaptation, Minecraft 26.3 black-screen (FBO0 self-healing blit) and resolution recovery fixes, MobileGlues deadlock fix, and Zink OpenGL bridging

## Third-Party Components

| Component | Purpose | License | Source |
|------|------|--------|------|
| Caciocavallo | AWT runtime framework | GPL-2.0 | [GitHub](https://github.com/PojavLauncherTeam/caciocavallo) |
| jsr305 | Code annotation support | BSD-3 | [Google Code](https://code.google.com/p/jsr-305) |
| Boardwalk | Core functionality adapter | Apache-2.0 | [GitHub](https://github.com/zhuowei/Boardwalk) |
| GL4ES | OpenGL to GLES translation | MIT | [GitHub](https://github.com/ptitSeb/gl4es) |
| Mesa 3D | 3D graphics library | MIT | [GitLab](https://gitlab.freedesktop.org/mesa/mesa) |
| MetalANGLE | Metal to OpenGL ES translation | BSD-2 | [GitHub](https://github.com/khanhduytran0/metalangle) |
| MoltenVK | Vulkan to Metal translation | Apache-2.0 | [GitHub](https://github.com/KhronosGroup/MoltenVK) |
| openal-soft | Cross-platform 3D audio | LGPL-2.0 | [GitHub](https://github.com/kcat/openal-soft) |
| Azul Zulu JDK | Java runtime (8/17/21/25) | GPL-2.0 | [Website](https://www.azul.com/downloads/?package=jdk) |
| LWJGL3 | Java game development library | BSD-3 | [GitHub](https://github.com/PojavLauncherTeam/lwjgl3) |
| LWJGLX | LWJGL2 compatibility layer | -- | [GitHub](https://github.com/PojavLauncherTeam/lwjglx) |
| DBNumberedSlider | UI slider control | Apache-2.0 | [GitHub](https://github.com/khanhduytran0/DBNumberedSlider) |
| fishhook | Dynamic library rebinding | BSD-3 | [GitHub](https://github.com/khanhduytran0/fishhook) |
| shaderc | Vulkan shader compiler | Apache-2.0 | [GitHub](https://github.com/khanhduytran0/shaderc) |
| NRFileManager | File management utility | MPL-2.0 | [GitHub](https://github.com/mozilla-mobile/firefox-ios) |
| AltKit | AltStore integration | -- | [GitHub](https://github.com/rileytestut/AltKit) |
| UnzipKit | ZIP extraction | BSD-2 | [GitHub](https://github.com/abbeycode/UnzipKit) |
| DyldDeNeuralyzer | Library validation bypass | -- | [GitHub](https://github.com/xpn/DyldDeNeuralyzer) |
| MobileGlues | Third-party renderer | LGPL-2.1 | [GitHub](https://github.com/MobileGL-Dev/MobileGlues) |
| LTW | OpenGL Core to ES wrapper | LGPL-3.0 | [GitHub](https://github.com/MojoLauncher/LTW) |
| authlib-injector | Third-party authentication support | AGPL-3.0 | [GitHub](https://github.com/yushijinhun/authlib-injector) |

Special thanks to [MCHeads](https://mc-heads.net) for Minecraft avatar services, [Modrinth](https://modrinth.com) for resource distribution, and [BMCLAPI](https://bmclapidoc.bangbang93.com) for Minecraft download mirrors.

## Donations

If you find this project useful, you can support it through [Ko-Fi](https://ko-fi.com/herbrine8403), [Afdian](https://afdian.com/a/herbrine8403), or the [WeChat donation code](donate.png).

## Star History

<a href="https://star-history.com/#herbrine8403/Amethyst-iOS-MyRemastered&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=herbrine8403/Amethyst-iOS-MyRemastered&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=herbrine8403/Amethyst-iOS-MyRemastered&type=Date" />
   <img alt="Star history" src="https://api.star-history.com/svg?repos=herbrine8403/Amethyst-iOS-MyRemastered&type=Date" />
 </picture>
</a>
