SHELL := /bin/bash
.SHELLFLAGS = -ec
# Use `make VERBOSE=1` to print commands.
$(VERBOSE).SILENT:

# Prerequisite variables
SOURCEDIR   := $(shell printf "%q\n" "$(shell pwd)")
OUTPUTDIR   := $(SOURCEDIR)/artifacts
WORKINGDIR  := $(SOURCEDIR)/Natives/build
DETECTPLAT  := $(shell uname -s)
DETECTARCH  := $(shell uname -m)
VERSION     := 1.2.0
BRANCH      := $(shell git branch --show-current)
COMMIT      := $(shell git log --oneline | sed '2,10000000d' | cut -b 1-7)
PLATFORM    ?= 2

# Release vs Debug
RELEASE ?= 0

# Check if running on github runner
RUNNER ?= 0

# Check if slimmed should be built
SLIMMED ?= 0

# Check if slimmed should be built, and additionally skip normal build
SLIMMED_ONLY ?= 0

# If not in a GitHub repository, default to these
# so that compiling doesn't fail
BRANCH ?= "unknown"
COMMIT ?= "unknown"

# Team IDs and provisioning profile for the codesign function
# Default to -1 for check
# Currently requires a paid Apple Developer account, will fix later
SIGNING_TEAMID ?= -1
TEAMID ?= -1
PROVISIONING ?= -1

ifeq (1,$(RELEASE))
CMAKE_BUILD_TYPE := Release
else
CMAKE_BUILD_TYPE := Debug
endif

# ★ [RENDERER-GAP] Additional renderers (VGPU / GL4ESZL2 / NG-GL4ES / VirGL).
# Default 0: VGPU is not built, and GL4ESZL2 / VirGL are not in the payload dependency graph
#            (these are optional/experimental; by default the IPA and existing renderer behavior are unchanged).
# Set to 1: native receives -DAME_RENDERER_GAP_VGPU=ON (builds libvgpu.dylib),
#           and the payload adds the dep_gl4eszl2 and dep_virgl targets.
# Usage: make RENDERER_GAP_EXTRAS=1 payload
#
# ⚠ NG-GL4ES ("Krypton Wrapper") is **not** controlled by this switch: it is a user-visible first-class renderer
#   (the unconditional payload dependency from f907a3f180); dep_nggl4es is attached directly to payload,
#   and CI's `gmake dsym package` builds libnggl4es.dylib every time.
RENDERER_GAP_EXTRAS ?= 0
# ★ [RENDERER-GAP] Derived from the switch above: empty by default → payload dependency graph remains unchanged.
ifeq (1,$(RENDERER_GAP_EXTRAS))
RENDERER_GAP_PAYLOAD_DEPS := dep_gl4eszl2 dep_virgl
else
RENDERER_GAP_PAYLOAD_DEPS :=
endif


# Distinguish iOS from macOS, and *OS from others
ifeq ($(DETECTPLAT),Darwin)
OSVER       := $(shell sw_vers -productVersion | cut -b 1-2)
ifeq ($(shell sw_vers -productName),macOS)
IOS         := 0
SDKPATH     ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
BOOTJDK     ?= $(shell /usr/libexec/java_home -v 1.8 2>/dev/null || /usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home -v 11 2>/dev/null || /usr/libexec/java_home 2>/dev/null)/bin
$(warning Building on macOS.)
else
IOS         := 1
SDKPATH     ?= /usr/share/SDKs/iPhoneOS.sdk
BOOTJDK     ?= /usr/lib/jvm/java-8-openjdk/bin
ifeq ($(shell test "$(OSVER)" -gt 14; echo $$?),0)
# ★ [ROOTHIDE] Installation prefix when building locally on iOS.
#   · Standard rootless: fixed /var/jb/ (unchanged from the previous behavior).
#   · RootHide (Dopamine-roothide/palera1n-roothide): the jailbreak root is randomized to
#     /var/containers/Bundle/Application/.jbroot-<16hex>/, with no /var/jb.
#     ⇒ The old default would install the app to an empty path. Detect a randomized jbroot automatically (preferred)
#     and add a trailing slash (deploy concatenates $(PREFIX)Applications/...). Explicit PREFIX=... still overrides (?=).
#   Note: .ipa/.tipa packaging (the package target) does not use PREFIX and is unaffected.
PREFIX      ?= $(shell d=$$(ls -d /var/containers/Bundle/Application/.jbroot-*/ 2>/dev/null | head -1); if [ -n "$$d" ]; then printf '%s' "$$d"; else echo "/var/jb/"; fi)
else
PREFIX      ?= /
endif
$(warning Building on iOS. Note that all targets may not compile or require external components.)
endif
else ifeq ($(DETECTPLAT),Linux)
IOS         := 0
# SDKPATH presence is checked later
BOOTJDK     ?= /usr/bin
$(warning Building on Linux. Note that all targets may not compile or require external components.)
else
$(error This platform is not currently supported for building Angel Aura Amethyst.)
endif

# ============================================================================
# ★ [SWIFT-BAR] Build variables for the SwiftUI bottom tab bar (Natives/AmeTabBar.swift)
# ----------------------------------------------------------------------------
#  As on the C side, select the target by platform: device arm64-apple-ios14.0,
#  simulator <arch>-apple-ios14.0-simulator (based on whether SDKPATH points to iPhoneSimulator).
#  swiftc produces $(WORKINGDIR)/AmeTabBar.o, then passes its path to CMake via -DAME_TABBAR_OBJ=...;
#  CMakeLists.txt retains the same swiftc rule as a fallback when invoking cmake directly.
# ============================================================================
SWIFTC        ?= $(shell xcrun -f swiftc 2>/dev/null || command -v swiftc 2>/dev/null || echo swiftc)
SWIFT_SRC     ?= $(SOURCEDIR)/Natives/AmeTabBar.swift
SWIFT_OBJ     ?= $(WORKINGDIR)/AmeTabBar.o
SWIFT_ARCH    ?= arm64
SWIFT_MIN_IOS ?= 14.0
ifeq ($(findstring Simulator,$(SDKPATH)),Simulator)
SWIFT_TARGET  ?= $(SWIFT_ARCH)-apple-ios$(SWIFT_MIN_IOS)-simulator
else
SWIFT_TARGET  ?= $(SWIFT_ARCH)-apple-ios$(SWIFT_MIN_IOS)
endif

# ★ [SWIFT-BAR] Compile the SwiftUI bottom tab bar (must happen before native CMake linking)
swift:
	echo '[Amethyst v$(VERSION)] swift - start'
	mkdir -p $(WORKINGDIR)
	$(SWIFTC) -parse-as-library -emit-object \
		-target $(SWIFT_TARGET) \
		-sdk "$(SDKPATH)" \
		$(if $(filter 1,$(RELEASE)),-O,) \
		-o $(SWIFT_OBJ) $(SWIFT_SRC)
	echo '[Amethyst v$(VERSION)] swift - end'

# Define PLATFORM_NAME from PLATFORM
ifeq ($(PLATFORM),2)
PLATFORM_NAME := ios
$(warning Set PLATFORM to 2, which is equal to iOS.)
else ifeq ($(PLATFORM),3)
PLATFORM_NAME := tvos
$(warning Set PLATFORM to 3, which is equal to tvOS.)
else ifeq ($(PLATFORM),6)
PLATFORM_NAME := maccatalyst
$(warning Set PLATFORM to 6, which is equal to Mac Catalyst.)
else ifeq ($(PLATFORM),7)
PLATFORM_NAME := iossimulator
$(warning Set PLATFORM to 7, which is equal to iOS Simulator.)
else ifeq ($(PLATFORM),8)
PLATFORM_NAME := tvossimulator
$(warning Set PLATFORM to 8, which is equal to tvOS Simulator.)
else ifeq ($(PLATFORM),11)
PLATFORM_NAME := xros
$(warning Set PLATFORM to 11, which is equal to visionOS.)
else ifeq ($(PLATFORM),12)
PLATFORM_NAME := xrsimulator
$(warning Set PLATFORM to 12, which is equal to visionOS Simulator.)
else
$(error PLATFORM is not valid.)
endif

POJAV_BUNDLE_DIR      ?= $(OUTPUTDIR)/AngelAuraAmethyst.app
POJAV_JRE8_DIR        ?= $(SOURCEDIR)/depends/java-8-openjdk
POJAV_JRE17_DIR       ?= $(SOURCEDIR)/depends/java-17-openjdk
POJAV_JRE21_DIR       ?= $(SOURCEDIR)/depends/java-21-openjdk
POJAV_JRE25_DIR       ?= $(SOURCEDIR)/depends/java-25-openjdk
MOLTENVK_LIBRARY      ?= $(SOURCEDIR)/Natives/resources/Frameworks/libMoltenVK.dylib
MOBILEGL_SOURCE_DIR   ?= $(SOURCEDIR)/Natives/external/MobileGL
# MobileGL source is vendored under Natives/external/MobileGL (a regular source directory like
# MobileGlues, no longer a gitlink), so it can be edited and built for iOS directly.
# Upstream does not publish prebuilt iOS artifacts. The first successful build was on 2026-08-31 (commit 55256e33);
# both backend dylibs are committed under Natives/resources/Frameworks/ and used in normal builds,
# avoiding a rebuild (building glslang + SPIRV-Cross takes about 30 minutes; macOS Actions minutes cost 10x).
# Set BUILD_MOBILEGL=1 only when modifying the source.
# To update source, use git to sync the dev branch of MobileGL-Dev/MobileGL (submodules use their default
# branches) into Natives/external/MobileGL, preserving existing exclusions (SPIRV-Cross/test,
# glslang/Test, Vulkan-Headers/tests, DiligentCore/Samples|Tutorials, trace_replay/fixtures,
# android-plugin). No workflow is required.
BUILD_MOBILEGL        ?= 0
MOBILEGL_DYLIB        ?= $(SOURCEDIR)/Natives/resources/Frameworks/libMobileGL.dylib
MOBILEGL_GLES_DYLIB   ?= $(SOURCEDIR)/Natives/resources/Frameworks/libMobileGL-gles.dylib
MITHRIL_PREBUILT_DIR  ?= $(SOURCEDIR)/prebuilt

# Function to use later for checking dependencies
METHOD_DEPCHECK   = $(shell $(1) >/dev/null 2>&1 && echo 1)

# Function to modify Info.plist files
METHOD_INFOPLIST  =  \
	if [ '$(4)' = '0' ]; then \
		plutil -replace $(1) -string $(2) $(3); \
	else \
		plutil -value $(2) -key $(1) $(3); \
	fi

# Function to check directories
METHOD_DIRCHECK   = \
	if [ ! -d '$(1)' ]; then \
		mkdir -p $(1); \
	else \
		rm -rf $(1)/*; \
	fi
	
# Function to change the platform on Mach-O files.
# iOS = 2, tvOS = 3, iOS Simulator = 7, tvOS Simulator = 8, visionOS = 11, visionOS Simulator = 12
# https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
# TODO: Change Info.plist for visionOS 1.0
METHOD_CHANGE_PLAT = \
	if [ '$(1)' != '11' ] && [ '$(1)' != '12' ]; then \
		vtool -arch arm64 -set-build-version $(1) 14.0 26.2 -replace -output $(2) $(2); \
		ldid -S -M $(2); \
	else \
		vtool -arch arm64 -set-build-version $(1) 1.0 1.0 -replace -output $(2) $(2); \
	fi \
	
# Function to package the application
# Fix: use the unified amethystremastered naming format.
METHOD_PACKAGE = \
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		IPA_SUFFIX="-trollstore.tipa"; \
	else \
		IPA_SUFFIX=".ipa"; \
	fi; \
	rm -f $(OUTPUTDIR)/com.tokyxkai.metallic-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX; \
	rm -f $(OUTPUTDIR)/com.tokyxkai.metallic.slimmed-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX; \
	if [ '$(SLIMMED_ONLY)' = '0' ]; then \
		zip --symlinks -r $(OUTPUTDIR)/com.tokyxkai.metallic-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX Payload; \
	fi; \
	if [ '$(SLIMMED)' = '1' ] || [ '$(SLIMMED_ONLY)' = '1' ]; then \
		zip --symlinks -r $(OUTPUTDIR)/com.tokyxkai.metallic.slimmed-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX Payload --exclude='Payload/AngelAuraAmethyst.app/java_runtimes/*'; \
	fi

# Function to download and unpack Java runtimes.
# ★ [JRE-NEST] The original condition joined "release missing" and "archive missing" with &&, so extraction
#   happened only when both were true: if depends/ contained jreN-*.tar.xz but java-N-openjdk/ was missing,
#   the entire block was skipped and the JRE was unavailable at runtime.
#   Now: extract if release is missing; download only if the archive is absent; detect and fix an extra
#   directory level after extraction; validate that the output is nonempty and runnable.
#   Note: this variable is a single logical line in the Makefile; never add a `#` comment (it would consume
#   the rest of the line), so all messages must use echo.
METHOD_JAVA_UNPACK = \
	cd $(SOURCEDIR)/depends; \
	if [ ! -f "java-$(1)-openjdk/release" ]; then \
		_arc=$$(ls jre$(1)-*.tar.xz 2>/dev/null | head -n1); \
		if [ -z "$$_arc" ]; then \
			if [ "$(RUNNER)" != "1" ]; then \
				wget '$(2)' -q --show-progress; \
				unzip jre*-ios-aarch64.zip && rm jre*-ios-aarch64.zip; \
			fi; \
			_arc=$$(ls jre$(1)-*.tar.xz 2>/dev/null | head -n1); \
		fi; \
		if [ -n "$$_arc" ]; then \
			rm -rf "java-$(1)-openjdk"; mkdir -p "java-$(1)-openjdk"; \
			tar xf "$$_arc" -C "java-$(1)-openjdk"; \
			if [ ! -f "java-$(1)-openjdk/release" ]; then \
				for d in java-$(1)-openjdk/*/; do \
					if [ -f "$$d/release" ] && [ -f "$$d/lib/server/libjvm.dylib" ]; then \
						echo "★ [JRE-NEST] Detected an extra directory level; flattening: $$d"; mv "$$d"/* "java-$(1)-openjdk/"; rmdir "$$d"; break; \
					fi; \
				done; \
			fi; \
			if [ ! -f "java-$(1)-openjdk/release" ] || [ ! -f "java-$(1)-openjdk/lib/server/libjvm.dylib" ]; then \
				echo "★ [JRE-NEST] ERROR: java-$(1)-openjdk is missing release / lib/server/libjvm.dylib after extraction"; ls -la "java-$(1)-openjdk"; exit 1; \
			fi; \
			echo "★ [JRE-NEST] java-$(1)-openjdk OK (release + lib/server/libjvm.dylib)"; \
		else \
			echo "★ [JRE-NEST] ERROR: java-$(1)-openjdk is missing and no archive is available to download: $(2)"; exit 1; \
		fi; \
	fi

# Function to codesign binaries.
METHOD_CODESIGN = \
	codesign --remove-signature $(2); \
	codesign -f -s $(1) --generate-entitlement-der --entitlements entitlements.codesign.xml $(2); \
	printf 'File: '; printf $(2); printf ', Codesigned with team: '; printf $(1); printf '\n'

# Function to run code when finding Mach-O files.
METHOD_MACHO = \
	for file in $$(find $(1)); do \
		if [[ "$$(file $$file)" == *"Mach-O"* ]]; then \
			$(2); \
		fi; \
	done

# Make sure everything is already available for use. Error if they require something
ifneq ($(call METHOD_DEPCHECK,cmake --version),1)
$(error You need to install cmake)
endif

ifneq ($(call METHOD_DEPCHECK,$(BOOTJDK)/javac -version),1)
$(error You need to install JDK 8)
endif

ifeq ($(IOS),0)
_JAVAVER := $(shell $(BOOTJDK)/javac -version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1)
ifeq ($(filter 1 8 11 17 18 19 20 21 22 23 24,$(_JAVAVER)),)
$(error You need to install JDK 8 or later (found: $(_JAVAVER)))
else
$(warning Using Java $(_JAVAVER) — JDK 8 is recommended but 11+ is supported)
endif
endif

ifneq ($(call METHOD_DEPCHECK,ldid),1)
$(error You need to install ldid)
endif

ifneq ($(call METHOD_DEPCHECK,wget --version),1)
$(error You need to install wget)
endif

ifeq ($(DETECTPLAT),Linux)
ifneq ($(call METHOD_DEPCHECK,lld),1)
$(error You need to install lld)
endif
endif

ifneq ($(filter sysctl,$(shell sysctl -n hw.logicalcpu)),)
ifneq ($(call METHOD_DEPCHECK,nproc --version),1)
ifneq ($(call METHOD_DEPCHECK,gnproc --version),1)
$(warning Unable to determine number of threads, defaulting to 2.)
JOBS   ?= 2
else
JOBS   ?= $(shell gnproc)
endif
else
JOBS   ?= $(shell nproc)
endif
else
JOBS   ?= $(shell sysctl -n hw.logicalcpu)
endif

ifndef SDKPATH
$(error You need to specify SDKPATH to the path of iPhoneOS.sdk. The SDK version should be 14.0 or newer.)
endif

all: clean native java jre assets payload package dsym

help:
	echo 'Makefile to compile Angel Aura Amethyst'
	echo ''
	echo 'Usage:'
	echo '    make                                Makes everything under all'
	echo '    make help                           Displays this message'
	echo '    make all                            Builds the entire app'
	echo '    make native                         Builds the native app'
	echo '    make swift                          Builds the SwiftUI tab bar (Natives/AmeTabBar.swift)'
	echo '    make java                           Builds the Java app'
	echo '    make jre                            Downloads/unpacks the iOS JREs'
	echo '    make assets                         Compiles Assets.xcassets'
	echo '    make payload                        Makes Payload/AngelAuraAmethyst.app'
	echo '    make package                        Builds ipa of Angel Aura Amethyst'
	echo '    make deploy                         Copies files to local iDevice'
	echo '    make dsym                           Generate debug symbol files'
	echo '    make clean                          Cleans build directories'
	echo '    make check                          Dump all variables for checking'
	echo '    make iris-bridge-on                 ★ 26.2 Iris<->Metal bridge on (default; see Natives/shader_iris_bridge.sh)'
	echo '    make iris-bridge-off                ★ 26.2 Iris<->Metal bridge off (revert to the old classes262/ class set)'
	echo '    make shader-glslang-pack            ★ package the missing glslang native for shaders (including the classes added for classes262iris)'
	echo '    make shader-glslang-check           ★ check whether the glslang native is included in the package'
	echo '    make verify-iris-integrate          ★ [IRIS-INTEGRATE] verify the 91-symbol native wiring and ensure the class set has not regressed from r10'
	echo '    make shader-iris-integrate          ★ [IRIS-INTEGRATE] wire 26.2-iris to the 91-symbol libmetallum_iris.dylib'

# ★ [SHADER-FAST] 26.2 Iris↔Metal bridge switch (only changes the marker resource inside the agent JAR metallum_iris.mode).
#   Can also be overridden at runtime (takes precedence over the marker): -Dmetallum.iris.bridge=0|1 / AMETHYST_METALLUM_IRIS=0|1
#   Class sets classes262iris/ + natives/ir1/ remain in the JAR; turning this off only prevents them from being selected by routing, with no side effects.
#   ★ One-command rollback: `make iris-bridge-off`; full-package rollback: cp D:/CTF/_510src/_bak_/shaderfast_*/metallum_agent.jar.orig
iris-bridge-on:
	sh Natives/shader_iris_bridge.sh on

iris-bridge-off:
	sh Natives/shader_iris_bridge.sh off

iris-bridge-status:
	sh Natives/shader_iris_bridge.sh status

# ★ [SHADER-GLSLANG] Package the final native piece for shader rendering (idempotent).
#   ★ [SHADER-SIGBUS] This target now means **glslang is loaded only from Frameworks and must not be in the JAR**:
#   · Place libglslang.dylib (with 17 glslang C API symbols) only in
#       Natives/resources/Frameworks/libglslang.dylib (+ byte-identical .16 / .16.4.0 aliases),
#     loaded via System.loadLibrary("glslang") in GlslangBridge.createIOSGlslangLookup()
#     (java.library.path = <app>/Frameworks; payload automatically bundles it through cp -R Natives/resources/*).
#     The copy is ad-hoc signed with the app ⇒ dyld can use a file-backed RX mapping ⇒ no SIGBUS.
#   · Do **not** put natives/ios|ir1/libglslang.dylib in the agent JAR / MetalUniversal JAR;
#     remove any existing entries during packaging. MetalNativeBridge.configureBundledGlslangLibrary()
#     extracts the JAR resource to <home>/libglslang_metallum.dylib and calls System.load.
#     This copy is **not signed with the app**, so dyld bypass can only use its fallback path
#     ("anonymous mapping + PrepareRegion + image memcpy"), causing SIGBUS on first execution
#     (on-device evidence: SIGBUS at [libglslang_metallum.dylib+0xccbc4] _GLOBAL__sub_I_Scan.cpp,
#      and the adjacent PrepareRegion log has len==2392064==that dylib's __TEXT.vmsize;
#      the historical VERSION_HISTORY.md v378 `noglslanginjar.ipa` reached the same conclusion).
#   · Add the complete com/mojang/blaze3d group to both class-set prefixes classes262iris/ + classes262/ (gap B).
#     ★ [BLAZE3D-ROOT-SHADOW] Do **not** mirror it to the JAR root: the "-javaagent" JAR is on the app/system
#       classpath, and a root copy shadows the game's own classes in the app loader (on-device 26.4:
#       RenderSystem$AutoStorageIndexBuffer$IndexGenerator was loaded by the app ⇒ same-named package, different
#       runtime package ⇒ IllegalAccessError ⇒ Could not initialize class RenderSystem).
#     ★ [SHADER-BLAZE3D-GROUP] The group is no longer "three fixed names": it is Natives/shader_glslang/blaze3d/**
#       (manifest blaze3d_group.txt), computed by Natives/extract_blaze3d_group.py from client-26.2.jar
#       as the link-surface closure of com/metallum/client/** actually defined by the agent + 3 interfaces
#       (superclasses/interfaces/field and method descriptors/generic Signatures/throws). The previous round
#       added only three fixed names; on-device latestlog-40 immediately failed at the next level:
#           NoClassDefFoundError: com/mojang/blaze3d/systems/GpuSurface$PresentMode  ← inner class ($)
#       The root com/metallum/** copies (byte-identical to classes262/) implement/reference those classes,
#       but the root has no com/mojang/blaze3d/ ⇒ a loader that sees only the JAR root immediately throws NoClassDefFoundError.
#       ★ The group **excludes** mixin target classes themselves (opengl/GlStateManager, systems/RenderSystem):
#         the agent's raw defineClass would define them into Knot and bypass Fabric/Iris mixins.
#   ★ Recompute the group only on a machine with client-26.2.jar (do **not** run on the Mac packaging line):
#       python Natives/extract_blaze3d_group.py --check      # verify manifest/source directory/closure only
#       python Natives/extract_blaze3d_group.py              # recompute and write source directory + manifest
#   The on-device gap is in latestlog-38.txt: Symbol not found: glslang_initialize_process
shader-glslang-pack:
	python3 Natives/pack_shader_glslang.py

shader-glslang-check:
	python3 Natives/pack_shader_glslang.py --check
	python3 Natives/verify_iris_integrate.py          # ★ [IRIS-INTEGRATE]
	python3 Natives/check_spvc_provenance.py          # ★ [26.4-SPVC]

# ★ [26.4-SPVC] Verify spvc native-library provenance (prevent omissions when moving the build).
#   On-device, the first 26.4 UI pipeline minecraft:pipeline/gui fails with
#   "SPIRV-Cross error at spvc_context_parse_spirv: -1" (-1 = INVALID_SPIRV).
#   ★ Key fact: the libspvc that actually performs SPIR-V→MSL on the device is not the one in Frameworks.
#   metallum's MetalNativeBridge.configureBundledSpvcLibrary() extracts
#   natives/ios/libspvc.dylib from the JAR to $POJAV_HOME, calls System.load, and sets
#   Configuration.SPVC_LIBRARY_NAME ⇒ LWJGL's Spvc loads the JAR copy,
#   completely bypassing our spvc serialization shim (the on-device 26.4 log has no [spvc-shim] lines,
#   only main_hook's "[spvc] dlsym intercepted").
#   ⇒ If the JAR native is not carried over correctly when moving/changing the base (mlrepo buildIOSSpvc
#   also silently skips with "libspvc.dylib already exists, skipping build", and vendor/SPIRV-Cross
#   is an uninitialized submodule), the build still succeeds while the entire SPIR-V→MSL backend is replaced.
#   This target makes the JAR's natives/ios|ir1/libspvc.dylib byte-identical to the canonical copy in the tree.
#   SPVC_PROVENANCE=warn downgrades mismatches to warnings.
check-spvc-provenance:
	python3 Natives/check_spvc_provenance.py

# ★ [SHADER-BLAZE3D-GROUP] Self-check the complete blaze3d group (manifest vs source directory vs closure) —
#   run only on a machine with D:\CTF\client-26.2.jar (not required on the Mac packaging line).
blaze3d-group-check:
	python3 Natives/extract_blaze3d_group.py --check

# ★ [IRIS-INTEGRATE] Make 26.2-iris use the 91-symbol libmetallum_iris.dylib, while 26.3/26.1 continue using
#   Frameworks/libmetallum.dylib (75 symbols, including getError/getStatus/get_last_error) — two routes in one package.
#   Method: change only the two MetalNativeBridge routes from System.loadLibrary("metallum") to "metallum_iris"
#         (resolve the §6.7 "shared filename" tradeoff through **renamed routing**, without overwriting or rebuilding native code).
#   ★ Why **not** copy in the r10 class set: this repository's agent classes262iris is **newer** than r10 —
#     per-class javap comparison: 21 classes differ (9 differ only in debug info); all remaining 12 are larger/more complete on the agent side
#     (SHADER-CAP GL_EXTENSIONS / shadowColorFormatsFrom / sodium(...GpuFormat[]) /
#       MetalNativeBridge extraction path /natives/ir1 vs r10 /natives/ios). Replacing it would regress functionality.
#     See the header comments in Natives/pack_iris_integrate.py and Natives/verify_iris_integrate.py.
#   ★ Idempotent; verify with make verify-iris-integrate (the same assertions are also called by shader-glslang-check).
shader-iris-integrate:
	python3 Natives/pack_iris_integrate.py

verify-iris-integrate:
	python3 Natives/verify_iris_integrate.py

check:
	$(foreach v, \
		$(shell echo "$(filter-out METHOD_% .% MAKEFILE_LIST MAKEFLAGS CURDIR,$(.VARIABLES))" | tr ' ' '\n' | sort), \
		$(if $(filter file,$(origin $(v))), \
		$(info $(shell printf "%-20s" "$(v)") = $(value $(v)))) \
	)

native: dep_mg swift
	echo '[Amethyst v$(VERSION)] native - start'
	mkdir -p $(WORKINGDIR)
	cd $(WORKINGDIR) && cmake \
		-DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DAME_TABBAR_OBJ="$(SWIFT_OBJ)" \
		-DCONFIG_BRANCH="$(BRANCH)" \
		-DCONFIG_COMMIT="$(COMMIT)" \
		-DCONFIG_RELEASE=$(RELEASE) \
		-DAME_RENDERER_GAP_VGPU=$(RENDERER_GAP_EXTRAS) \
		..

	cmake --build $(WORKINGDIR) --config $(CMAKE_BUILD_TYPE) -j$(JOBS)
	#	--target awt_headless awt_xawt libOSMesaOverride.dylib tinygl4angle AngelAuraAmethyst
	rm $(WORKINGDIR)/libawt_headless.dylib
	echo '[Amethyst v$(VERSION)] native - end'

java:
	echo '[Amethyst v$(VERSION)] java - start'
	# Build LWJGL JARs from lwjgl-lib/ source (3.3.3 and 3.4.1).
	# Skipped by default: prebuilt JARs are already in git, so normal builds and CI do not need Ant / JDK 8 /
	# network access. Build from source only when BUILD_LWJGL=1 (for local LWJGL changes):
	#     BUILD_LWJGL=1 make java
	if [ "$(BUILD_LWJGL)" = "1" ]; then bash "$(SOURCEDIR)/scripts/build_lwjgl.sh"; else echo '[Amethyst v$(VERSION)] java - using prebuilt LWJGL jars'; fi
	$(MAKE) -C JavaApp -j$(JOBS) BOOTJDK=$(BOOTJDK)
	echo '[Amethyst v$(VERSION)] java - end'

jre: native
	echo '[Amethyst v$(VERSION)] jre - start'
	mkdir -p $(SOURCEDIR)/depends
	cd $(SOURCEDIR)/depends; \
	$(call METHOD_JAVA_UNPACK,8,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre8-ios-aarch64.zip'); \
	$(call METHOD_JAVA_UNPACK,17,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre17-ios-aarch64.zip'); \
	$(call METHOD_JAVA_UNPACK,21,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre21-ios-aarch64.zip'); \
	$(call METHOD_JAVA_UNPACK,25,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre25-ios-aarch64.zip'); \
	if [ -f "$(ls jre*.tar.xz)" ]; then rm $(SOURCEDIR)/depends/jre*.tar.xz; fi; \
	cd $(SOURCEDIR); \
	rm -rf $(SOURCEDIR)/depends/java-{8,17,21,25}-openjdk/{ASSEMBLY_EXCEPTION,bin,include,jre,legal,LICENSE,man,THIRD_PARTY_README,lib/{ct.sym,jspawnhelper,libjsig.dylib,src.zip,tools.jar}}; \
	$(call METHOD_DIRCHECK,$(OUTPUTDIR)/java_runtimes); \
	cp -R $(POJAV_JRE8_DIR) $(OUTPUTDIR)/java_runtimes; \
	cp -R $(POJAV_JRE17_DIR) $(OUTPUTDIR)/java_runtimes; \
	cp -R $(POJAV_JRE21_DIR) $(OUTPUTDIR)/java_runtimes; \
	cp -R $(POJAV_JRE25_DIR) $(OUTPUTDIR)/java_runtimes; \
	for _v in 8 17 21 25; do \
		if [ ! -f "$(OUTPUTDIR)/java_runtimes/java-$$_v-openjdk/lib/server/libjvm.dylib" ]; then \
			echo "★ [JRE-NEST] ERROR: The output java_runtimes/java-$$_v-openjdk is missing lib/server/libjvm.dylib (incorrect directory hierarchy or copy failure)"; ls -la "$(OUTPUTDIR)/java_runtimes/java-$$_v-openjdk" 2>/dev/null | head -20; exit 1; \
		fi; \
		echo "★ [JRE-NEST] java_runtimes/java-$$_v-openjdk OK"; \
	done; \
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-8-openjdk/lib; \
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-17-openjdk/lib;
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-21-openjdk/lib
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-25-openjdk/lib
	echo '[Amethyst v$(VERSION)] jre - end'

dep_mg:
	echo '[Amethyst v$(VERSION)] dep_mg - start'
	# ---------------------------------------------------------------------------
	# 3rd-party version alignment — match the .gitmodules pin in the reference Air repository.
	#
	# Original warning in Air's Makefile:
	#   "The shader conversion pipeline (desktop GLSL -> ESSL) is only validated
	#    against the submodule commits pinned in .gitmodules. A 3rdparty/ tree
	#    populated from arbitrary master snapshots produced ESSL that ANGLE-Metal
	#    rejects as empty (ERROR 1:1 syntax error on every shader, MC 26.x black
	#    screen). Force the pinned versions before configuring cmake, and fail
	#    loudly if they are still missing afterwards."
	#
	# This repository vendors this directory rather than using a submodule. Per-file blob SHA comparisons show that it differs from the pinned
	# revision: SPIRV-Cross's spirv_cross.cpp / spirv_cross.hpp /
	# spirv_glsl.cpp / spirv_glsl.hpp / spirv_cfg.cpp all differ; glslang's
	# CHANGES.md / localintermediate.h / Versions.cpp / InfoSink.h /
	# CMakeLists.txt also differs; xxhash already matches, so it is skipped. This is the root cause of the MG + 26.3 black screen and silent
	# crash (ANGLE-Metal rejects the generated ESSL).
	#
	# Equivalent to Air's git submodule update --init: during the build, replace both directories entirely with
	# pinned snapshots (extract the tar directly to the target directory to avoid BSD cp -R directory-overwrite pitfalls). The sentinel
	# file .air_pin_<sha> prevents repeat downloads; back up the two .patch files in the glslang directory before replacement,
	# then restore them so the following patch block can apply them (the pinned revision itself does not include the guard patches).
	# Escape hatch: AMETHYST_MG_PIN_ALIGN=0 skips alignment (for offline debugging; output is unverified).
	# ---------------------------------------------------------------------------
	@mg3=$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty; \
	if [ "$${AMETHYST_MG_PIN_ALIGN:-1}" = "0" ]; then \
		echo '[dep_mg] WARNING: 3rdparty pin alignment skipped (AMETHYST_MG_PIN_ALIGN=0) -- MG build NOT validated'; \
	else \
		mkdir -p /tmp/mgpin_patches; \
		cp "$$mg3"/*.patch /tmp/mgpin_patches/ 2>/dev/null || true; \
		align3rd() { \
			mg_name=$$1; mg_url=$$2; mg_sha=$$3; \
			if [ -f "$$mg3/$$mg_name/.air_pin_$$mg_sha" ]; then \
				echo "[dep_mg] $$mg_name already pinned to $$mg_sha"; return 0; \
			fi; \
			echo "[dep_mg] $$mg_name: replacing vendored tree with pinned snapshot $$mg_sha"; \
			rm -rf "$$mg3/$$mg_name"; \
			mkdir -p "$$mg3/$$mg_name" || return 1; \
			curl -fsSL -o "/tmp/mgpin_$$mg_name.tgz" "$$mg_url" || { echo "ERROR: [dep_mg] $$mg_name pinned tarball download failed"; return 1; }; \
			tar -xzf "/tmp/mgpin_$$mg_name.tgz" -C "$$mg3/$$mg_name" --strip-components=1 || return 1; \
			touch "$$mg3/$$mg_name/.air_pin_$$mg_sha"; \
			echo "[dep_mg] $$mg_name pinned OK"; \
		}; \
		align3rd SPIRV-Cross https://codeload.github.com/KhronosGroup/SPIRV-Cross/tar.gz/a0fba56c34a6700f1724bf9b751da5b488a3775c a0fba56 || { echo 'ERROR: [dep_mg] 3rdparty pin alignment failed - cannot build a validated MobileGlues'; exit 1; }; \
		align3rd glslang https://codeload.github.com/KhronosGroup/glslang/tar.gz/f5f664dee8146676b04a332a7233959fc3ce9681 f5f664d || { echo 'ERROR: [dep_mg] 3rdparty pin alignment failed - cannot build a validated MobileGlues'; exit 1; }; \
		cp /tmp/mgpin_patches/*.patch "$$mg3/" 2>/dev/null || true; \
		echo '[dep_mg] 3rdparty pinned: SPIRV-Cross=a0fba56 glslang=f5f664d (xxhash already matches c2866db)'; \
	fi
	mkdir -p $(WORKINGDIR)/mobileglues
	# MG includes 3rdparty/glslang (built from source via add_subdirectory in CMakeLists). Before cmake
	# configuration, the reference repository applies two guard patches to this glslang copy (this repository vendors
	# the directory rather than using a submodule, so --directory is used to locate it):
	#   * glslang-lvalue-nullguard.patch — TParseContext::lValueErrorCheck does not check for null before
	#     aggregating swizzle selectors; on iOS/arm64, this path SIGSEGVs while parsing the MC 26.x position_color
	#     vertex shader, killing the process during startup/resource reload (no .ips or hs_err; appears as a silent crash).
	#   * glslang-pool-zero-and-size-guards.patch — adds a constArray size check to GlslangToSpv::convertSwizzle;
	#     it must be applied after nullguard.
	# Task 170 — patches must target the actual src/main/cpp path, not MobileGlues-cpp.
	# MobileGlues-cpp is a symlink -> src/main/cpp (this repository's vendored layout; in the Air reference repository this
	# is a real directory). git apply refuses to follow symlinks:
	#   error: affected file '.../MobileGlues-cpp/3rdparty/glslang/...' is beyond a symbolic link
	# As a result, both forward and reverse --check fail, and the two MC 26.x position_color SIGSEGV guard patches
	# are silently skipped — the build log's
	#   "[dep_mg] WARNING: ... neither applies nor is applied -- MG glslang left UNPATCHED"
	# is exactly what that warning describes. Pin alignment then replaces the guarded vendored tree with upstream f5f664d (without guards),
	# so libmobileglues had long been built with "zero guards": it SIGSEGVs while parsing the position_color vertex shader
	# during a 26.3 resource reload, with no hs_err or .ips and a silent crash;
	# 26.2 does not use this path and is unaffected. The patches apply correctly in the Air reference repository because it has a real directory,
	# so its MG + 26.3 build is playable throughout.
	# Order matters: nullguard must precede pool-zero/size-guard (the latter depends on the former).
	# Any failure now exits with status 1 — never silently produce an unguarded MG build again.
	@mg_3prel=Natives/external/MobileGlues/src/main/cpp/3rdparty; \
	mg_glrel=$$mg_3prel/glslang; \
	mg_pdir=$(SOURCEDIR)/$$mg_3prel; \
	mg_guard_src=$(SOURCEDIR)/$$mg_glrel/glslang/MachineIndependent/ParseHelper.cpp; \
	if grep -q "Defensive null guards" "$$mg_guard_src" 2>/dev/null; then \
		echo "[dep_mg] glslang guards already baked into the tree -- skip patches"; \
	else \
	for p in glslang-lvalue-nullguard.patch glslang-pool-zero-and-size-guards.patch; do \
		if [ ! -f "$$mg_pdir/$$p" ]; then echo "[dep_mg] ERROR: glslang patch $$p MISSING under $$mg_3prel -- MG would be built WITHOUT the MC 26.x position_color SIGSEGV guards"; exit 1; fi; \
		if git -C $(SOURCEDIR) apply --check -p1 --directory=$$mg_glrel "$$mg_pdir/$$p" >/dev/null 2>&1; then \
			git -C $(SOURCEDIR) apply -p1 --directory=$$mg_glrel "$$mg_pdir/$$p" && echo "[dep_mg] glslang patch $$p APPLIED" || { echo "[dep_mg] ERROR: $$p apply failed after a successful --check"; exit 1; }; \
		elif git -C $(SOURCEDIR) apply --check -R -p1 --directory=$$mg_glrel "$$mg_pdir/$$p" >/dev/null 2>&1; then \
			echo "[dep_mg] glslang patch $$p already applied"; \
		else \
			echo "[dep_mg] ERROR: glslang patch $$p neither applies nor is applied -- MG glslang would be left UNPATCHED (MC 26.x position_color SIGSEGV guards missing)"; exit 1; \
		fi; \
	done; \
	fi
	# CMAKE_BUILD_TYPE must be specified explicitly: --config is ineffective for single-configuration generators.
	# If omitted, CMake does not add -O2/-DNDEBUG, the entire library is built with -O0, and all glslang/SPIRV-Cross/MG assert() calls are enabled —
	# a triggered assert calls __assert_rtn->abort(), immediately showing a launcher error screen with no .ips/hs_err.
	cd $(WORKINGDIR)/mobileglues && cmake \
		-DMACOS="1" \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/

	# Also explicitly build the SPIRV / glslang-default-resource-limits static libraries:
	# dep_shader_shims needs them when linking libshaderc_impl.dylib from source,
	# while mobileglues itself links only glslang::glslang and does not build these targets.
	cmake --build $(WORKINGDIR)/mobileglues --config RelWithDebInfo -j$(JOBS) --target mobileglues SPIRV glslang-default-resource-limits
	@mg_bindir=$(WORKINGDIR)/mobileglues/3rdparty/glslang; \
	mg_spirv_a=$$mg_bindir/SPIRV/libSPIRV.a; \
	[ -f "$$mg_spirv_a" ] || mg_spirv_a=$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/libraries/ios/libSPIRV.a; \
	mg_glslang_a=$$mg_bindir/glslang/libglslang.a; \
	[ -f "$$mg_glslang_a" ] || mg_glslang_a=$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/libraries/ios/libglslang.a; \
	mg_rl_a=$$mg_bindir/glslang/libglslang-default-resource-limits.a; \
	[ -f "$$mg_rl_a" ] || mg_rl_a=$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/libraries/ios/libglslang-default-resource-limits.a; \
	if [ -z "$$mg_spirv_a" ] || [ ! -f "$$mg_spirv_a" ] || [ -z "$$mg_glslang_a" ] || [ ! -f "$$mg_glslang_a" ] || [ -z "$$mg_rl_a" ] || [ ! -f "$$mg_rl_a" ]; then \
		echo "ERROR: glslang static libs unresolved (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a)"; \
		find $(WORKINGDIR)/mobileglues -type f -name "lib*.a" 2>/dev/null | head -20; \
		exit 1; \
	fi; \
	echo "[shaderc-impl] glslang static libs OK (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a)"
	cp $(WORKINGDIR)/mobileglues/libmobileglues*.dylib $(WORKINGDIR)/
	echo '[Amethyst v$(VERSION)] dep_mg - end'
# ---------------------------------------------------------------------------
# shaderc / spirv-cross serialization shim (aligned with Air Tasks 39/42/47/54)
#
# MG + MC 26.3 crash family: during resource reload, multiple JVM threads with 32 MB stacks compile shaders with glslang
# concurrently, while compiler_release races with in-flight compilation. When the old RenderPearl pipeline is released,
# it tears down the global symbol table and frees the glslang pool; subsequent string allocations reuse AST memory still
# in use by compilation. ASCII bytes land in the SWIZZLE node's constArray pointer field (offset +0xd8), eventually
# causing a SIGSEGV at glslang::TParseContext::lValueErrorCheck+0x204 and bringing down the entire process.
#
# Fix: emit the real library as *_impl.dylib, then use this shim under the original name with -reexport_library
# to forward all symbols. Protect the compile entry points and compiler/options lifecycle entry points with one process-wide
# recursive mutex. During compilation, intercept SIGSEGV/SIGBUS and retry once (a crash net), downgrading
# "process death" to "one shader compilation failure + diagnostic logs."
#
# This repository has pre-committed binaries under Natives/resources/Frameworks, so copy them to impl-named files in
# WORKINGDIR and rewrite LC_ID (the re-export records the impl install name; otherwise the build-time absolute path
# would be baked into the output).
# ---------------------------------------------------------------------------
# --- Select the source for libshaderc_impl.dylib (for A/B testing) -----------
# SHADERC_IMPL_FROM_SOURCE=1 : Air Task 45 path — Natives/shaderc_impl_glue.c
#                              overlays the glslang static libraries just built by dep_mg, patched with nullguard +
#                              pool-zero/size-guard.
# SHADERC_IMPL_FROM_SOURCE=0 : Original behavior when the shim was introduced (3bed818be0) — use the pre-committed
#                              binaries under Natives/resources/Frameworks/ directly.
#                              Default 1: two hs_err reports (pid11633 / pid23353) show that both paths crash with the
#                              same issue — see the symbol-fencing comment below. The fence can only apply to the impl
#                              we link ourselves; the prebuilt binary cannot be changed, so from-source is the default.
#                              The variable can still be set to 0 for whole-package A/B testing.
SHADERC_IMPL_FROM_SOURCE ?= 1

ifeq ($(SHADERC_IMPL_FROM_SOURCE),1)
dep_shaderc_impl: dep_mg
	echo '[shaderc-impl] mode=from-source (Air Task 45) - start'
	# Build libshaderc_impl.dylib from source: Natives/shaderc_impl_glue.c calls the
	# glslang C interface and links the static libraries just built by dep_mg (patched with nullguard +
	# pool-zero/size-guard). The prebuilt libshaderc.dylib contains unpatched glslang; its
	# TParseContext::lValueErrorCheck / convertSwizzle dereferences a swizzle selector constArray (+0xd8)
	# corrupted by reclaimed heap bytes, causing SIGSEGV — the cause of the MC 26.3 crash family.
	mg_bindir=$(WORKINGDIR)/mobileglues/3rdparty/glslang; \
	mg_spirv_a=$$mg_bindir/SPIRV/libSPIRV.a; \
	[ -f "$$mg_spirv_a" ] || mg_spirv_a=$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/libraries/ios/libSPIRV.a; \
	mg_glslang_a=$$mg_bindir/glslang/libglslang.a; \
	[ -f "$$mg_glslang_a" ] || mg_glslang_a=$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/libraries/ios/libglslang.a; \
	mg_rl_a=$$mg_bindir/glslang/libglslang-default-resource-limits.a; \
	[ -f "$$mg_rl_a" ] || mg_rl_a=$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/libraries/ios/libglslang-default-resource-limits.a; \
	if [ -z "$$mg_spirv_a" ] || [ ! -f "$$mg_spirv_a" ] || [ -z "$$mg_glslang_a" ] || [ ! -f "$$mg_glslang_a" ] || [ -z "$$mg_rl_a" ] || [ ! -f "$$mg_rl_a" ]; then \
		echo "ERROR: glslang static libs unresolved - from-source shaderc impl cannot link"; \
		exit 1; \
	fi; \
	extra_glslang_libs=""; \
	for l in libOGLCompiler.a libOSDependent.a; do \
		if [ -f "$$mg_bindir/glslang/$$l" ]; then \
			extra_glslang_libs="$$extra_glslang_libs $$mg_bindir/glslang/$$l"; \
		fi; \
	done; \
	echo "[shaderc-impl] linking from-source impl (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a extra libs:$$extra_glslang_libs)"; \
	printf '_shaderc_*\n' > $(WORKINGDIR)/shaderc_impl.exports; \
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libshaderc_impl.dylib \
		$(FENCE_IMPL) \
		-I$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang \
		-o $(WORKINGDIR)/libshaderc_impl.dylib \
		$(SOURCEDIR)/Natives/shaderc_impl_glue.c \
		"$$mg_spirv_a" \
		"$$mg_glslang_a" \
		"$$mg_rl_a" \
		$$extra_glslang_libs \
		-lc++ || exit 1
	install_name_tool -id @rpath/libshaderc_impl.dylib $(WORKINGDIR)/libshaderc_impl.dylib || exit 1
	echo '[shaderc-impl] mode=from-source - end'
else
dep_shaderc_impl:
	echo '[shaderc-impl] mode=prebuilt (Natives/resources/Frameworks/libshaderc.dylib) - start'
	# $(WORKINGDIR) is created by the cmake step in dep_mg; this branch no longer depends on dep_mg,
	# so create the directory explicitly (same handling as dep_openal_shim), with no side effects.
	mkdir -p $(WORKINGDIR)
	cp $(SOURCEDIR)/Natives/resources/Frameworks/libshaderc.dylib $(WORKINGDIR)/libshaderc_impl.dylib || exit 1
	install_name_tool -id @rpath/libshaderc_impl.dylib $(WORKINGDIR)/libshaderc_impl.dylib || exit 1
	echo '[shaderc-impl] mode=prebuilt - end'
endif

# --- Export-symbol fence (root cause of 26.3 + MobileGL/MobileGlues SIGSEGV) ---
# Both on-device hs_err crash stacks cross two images:
#   pid11633  C [libshaderc.dylib+0x3adafc]      spvtools::opt::Module::ForEachInst
#             C [libMobileGL-gles.dylib+0xfd3014] spvtools::Optimizer::Run
#   pid23353  C [libMobileGL-gles.dylib+0xaaff64] TGlslangToSpvTraverser::visitAggregate
#             C [libshaderc_impl.dylib+0x75230]   glslang::TIntermAggregate::traverse
# The renderer image embeds one copy of glslang / SPIRV-Tools, and the shaderc shim embeds another. Both contain
# weak symbols generated by inline C++ header definitions, which dyld merges under the flat namespace:
# MobileGL builds nodes with its own AST, but jumps into traverse/ForEachInst in the shaderc image to traverse them.
# The layouts and vtables do not match, causing an immediate SIGSEGV.
# This is independent of whether the impl is prebuilt or built from source (the two reports cover both paths); it depends only on
# whether these symbols are exported into the global namespace.
# shaderc_impl_glue.c exposes only shaderc_* (everything else is static), and spvc_shim.c exposes only
# spvc_*; glslang / spvtools / spirv-cross symbols leak only as a side effect of the static libraries.
# An -exported_symbols_list allowlist therefore completely prevents symbol collisions without affecting shim functionality.
SHADER_SHIM_SYMBOL_FENCE ?= 1

ifeq ($(SHADER_SHIM_SYMBOL_FENCE),1)
FENCE_IMPL    := -Wl,-exported_symbols_list,$(WORKINGDIR)/shaderc_impl.exports
FENCE_SHADERC := -Wl,-exported_symbols_list,$(WORKINGDIR)/shaderc.exports
FENCE_SPVC    := -Wl,-exported_symbols_list,$(WORKINGDIR)/spvc.exports
else
FENCE_IMPL    :=
FENCE_SHADERC :=
FENCE_SPVC    :=
endif

# --- Overall shim switch ----------------------------------------------------
# SHADER_SHIMS=0 : disable dep_shader_shims entirely; package the original pre-committed binaries from
#                  Natives/resources/Frameworks/ directly — the state before the shims were introduced by
#                  3bed818be0 (black screen with 26.3 + MG, but no crash).
#                  The payload's "cp -R Natives/resources/*" copies them into the app;
#                  this target produces no dylibs with matching names, so nothing is overwritten.
SHADER_SHIMS ?= 1

ifeq ($(SHADER_SHIMS),1)
dep_shader_shims: dep_shaderc_impl dep_mg
	echo '[Amethyst v$(VERSION)] dep_shader_shims - start'
	cp $(SOURCEDIR)/Natives/resources/Frameworks/libspirv-cross-c-shared.0.dylib $(WORKINGDIR)/libspirv-cross-c-shared.0.impl.dylib || exit 1
	install_name_tool -id @rpath/libspirv-cross-c-shared.0.impl.dylib $(WORKINGDIR)/libspirv-cross-c-shared.0.impl.dylib || exit 1
	printf '_shaderc_*\n_ame_*\n' > $(WORKINGDIR)/shaderc.exports; \
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libshaderc.dylib \
		$(FENCE_SHADERC) \
		-Wl,-reexport_library,$(WORKINGDIR)/libshaderc_impl.dylib \
		-o $(WORKINGDIR)/libshaderc.dylib \
		$(SOURCEDIR)/Natives/shaderc_shim.c \
		$(SOURCEDIR)/Natives/shaderc_include.c \
		$(SOURCEDIR)/Natives/shaderc_sandbox.m || exit 1
	printf '_spvc_*\n_ame_*\n' > $(WORKINGDIR)/spvc.exports; \
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libspirv-cross-c-shared.0.dylib \
		$(FENCE_SPVC) \
		-Wl,-reexport_library,$(WORKINGDIR)/libspirv-cross-c-shared.0.impl.dylib \
		-o $(WORKINGDIR)/libspirv-cross-c-shared.0.dylib \
		$(SOURCEDIR)/Natives/spvc_shim.c || exit 1
	# -------------------------------------------------------------------
	# Decouple MobileGlues' SPIRV-Cross from the LWJGL spvc shim above.
	#
	# MG links the prebuilt libspirv-cross-c-shared.dylib under libraries/ios/ in CMakeLists,
	# whose LC_ID_DYLIB matches the spvc shim produced above. At runtime, dyld therefore routes every MG
	# spvc_* call through the shim — i.e. onto 32 MB stack worker threads plus the process-wide compile lock
	# (the log message "[spvc-shim] ... MG serialization ON" confirms this). MC 26.3 converts far more shaders than
	# 26.2, saturating this shared path and stalling the process: silent crash, no hs_err, no crash report.
	# 26.2 processes fewer shaders and is unaffected. (MG can complete the conversion itself — before the shim,
	# 26.3 + MG produced audio but only a black screen.)
	#
	# The reference Air repository uses add_subdirectory(3rdparty/SPIRV-Cross) for MG and statically links
	# spirv-cross-c, so this shared library does not exist there and it is unaffected. This repository does not include
	# the SPIRV-Cross submodule, so the MG link method is unchanged; before packaging, redirect libmobileglues'
	# spirv-cross dependency to a separately named real library. The LWJGL side continues loading the shim under its
	# original name, preserving the 32 MB stack and serialization lock exactly as before.
	#
	# Probe the dependency name with otool rather than hard-coding it; search for the source library in either of two candidate paths.
	# If any step is missing, print a WARN and skip without failing the build.
	# -------------------------------------------------------------------
	for mg in $(WORKINGDIR)/libmobileglues*.dylib; do \
		[ -f "$$mg" ] || continue; \
		mg_dep=$$(otool -L "$$mg" | awk '/spirv-cross/ { print $$1; exit }'); \
		if [ -z "$$mg_dep" ]; then \
			echo "[dep_shader_shims] $$(basename "$$mg"): no spirv-cross dylib dependency (statically linked) -- skip"; \
			continue; \
		fi; \
		if [ ! -f "$(WORKINGDIR)/libspirv-cross-mg.dylib" ]; then \
			mg_src="$(SOURCEDIR)/Natives/external/MobileGlues/src/main/cpp/libraries/ios/libspirv-cross-c-shared.dylib"; \
			[ -f "$$mg_src" ] || mg_src="$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/libraries/ios/libspirv-cross-c-shared.dylib"; \
			if [ ! -f "$$mg_src" ]; then \
				echo "[dep_shader_shims] WARN: MG spirv-cross prebuilt not found -- skip decoupling"; \
				continue; \
			fi; \
			cp "$$mg_src" "$(WORKINGDIR)/libspirv-cross-mg.dylib" || exit 1; \
			install_name_tool -id @rpath/libspirv-cross-mg.dylib "$(WORKINGDIR)/libspirv-cross-mg.dylib" || exit 1; \
		fi; \
		install_name_tool -change "$$mg_dep" @rpath/libspirv-cross-mg.dylib "$$mg" || exit 1; \
		echo "[dep_shader_shims] MG spvc decoupled: $$mg_dep -> @rpath/libspirv-cross-mg.dylib"; \
	done
	echo '[Amethyst v$(VERSION)] dep_shader_shims - end'
else
dep_shader_shims:
	echo '[Amethyst v$(VERSION)] dep_shader_shims - DISABLED (SHADER_SHIMS=0): shipping prebuilt libshaderc.dylib + libspirv-cross-c-shared.0.dylib verbatim (pre-3bed818be0 state)'
endif



dep_openal_shim:
	# Task 129: OpenAL ALC_SOFT_system_events compatibility shim (fix for a crash in 26.1.2 modpacks).
	# - The real library was moved with git mv to libopenal_impl.dylib (openal-soft 1.20.1 iOS build, without
	#   the ALC_SOFT_system_events extension); this target builds a same-named libopenal.dylib shim:
	#   re-export all impl symbols + override alcGetString/alcIsExtensionPresent to advertise the extension
	#   + provide stubs for alcEventIsSupportedSOFT/alcEventControlSOFT/alcEventCallbackSOFT.
	# - Root cause: MC 26.1.2 CallbackDeviceTracker.isSupported has no extension guard and directly calls
	#   the LWJGL binding -> ICD slot 0 -> NPE crash (26.3 survives because it has a guard).
	#   The stubs return ALC_FALSE so MC cleanly falls back to PollingDeviceTracker.
	# - Same pattern as dep_shader_shims: re-export must point to the impl name (fix LC_ID first),
	#   otherwise loading recurses; local function definitions take precedence over re-exported symbols (as with shaderc).
	echo '[Amethyst v$(VERSION)] dep_openal_shim - start'
	# Task 170: dep_openal_shim and dep_mg are both payload prerequisites and run in parallel (gmake -j),
	# while $(WORKINGDIR) is created by the cmake step inside dep_mg. If this target runs first, the directory does not yet exist,
	# so cp fails immediately (CI: "cp: directory .../Natives/build does not exist").
	# dep_shader_shims is unaffected because it depends on dep_mg; explicitly creating the directory here is sufficient and has no side effects.
	mkdir -p $(WORKINGDIR)
	cp $(SOURCEDIR)/Natives/resources/Frameworks/libopenal_impl.dylib $(WORKINGDIR)/ || exit 1
	install_name_tool -id @rpath/libopenal_impl.dylib $(WORKINGDIR)/libopenal_impl.dylib || exit 1
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libopenal.dylib \
		-Wl,-reexport_library,$(WORKINGDIR)/libopenal_impl.dylib \
		-o $(WORKINGDIR)/libopenal.dylib \
		$(SOURCEDIR)/Natives/openal_shim.c || exit 1
	echo '[Amethyst v$(VERSION)] dep_openal_shim - end'

dep_angle_freeze:
	echo '[Amethyst v$(VERSION)] dep_angle_freeze - start'
	# Task 57 (root-cause fix for split-screen rendering): 8-byte machine-code patch -- ANGLE Metal
	# WindowSurfaceMtl::checkIfLayerResized: expected size source switched from
	# bounds*contentsScale (poisoned by windowed-mode background-thread portrait
	# geometry, CALayer cross-thread split-brain) to the surface's own latched
	# mWidth/mHeight ([x19,#0x430/0x438]) -- surface size frozen at creation
	# geometry (creation reads always clean); transposition becomes physically
	# impossible; on drawableSize drift the enforcement branch re-writes the
	# frozen value back onto the layer. Idempotent; loud failure on byte
	# mismatch (ANGLE version drift guard); full root-cause chain in script
	# header comments (scripts/patch_angle_surface_freeze.py).
	# The patch changes the source file and invalidates its signature hash; packaging recursively re-signs the entire app with ldid -S.
	if [ -f "$(SOURCEDIR)/scripts/patch_angle_surface_freeze.py" ]; then \
		python3 "$(SOURCEDIR)/scripts/patch_angle_surface_freeze.py" \
			"$(SOURCEDIR)/Natives/resources/Frameworks/libGLESv2.framework/libGLESv2" || exit 1; \
	else \
		echo '[Amethyst] WARNING: ANGLE surface freeze patch skipped; patch script is missing'; \
	fi
	echo '[Amethyst v$(VERSION)] dep_angle_freeze - end'

dep_sdl3_guard:
	echo '[Amethyst v$(VERSION)] dep_sdl3_guard - start'
	# Task 135 (root-cause fix for the controlify/JNA closure SIGBUS): machine-code guard at the libSDL3.dylib
	# entry points — null out or reject every non-null callback pointer passed to SDL_SetEventFilter / SDL_AddEventWatch.
	# controlify falls back to the iOS SDL3 in this Frameworks directory via JNA, then registers a JNA/libffi closure
	# (an RW, non-executable trampoline page) as an SDL event filter; SDL calls then trigger SIGBUS. The dlsym-layer
	# guard works for LWJGL/FFM resolution paths, but JNA can bypass it; this patch puts the guard directly in the SDL
	# binary, completely independent of symbol resolution.
	# Neither the launcher nor MC/LWJGL uses SDL event filters (verified by repository-wide grep), so there are no side effects;
	# packaging re-signs the entire app with ldid -S, replacing the signature (same process as dep_angle_freeze).
	# Idempotent; fail loudly if bytes do not match (SDL3 version drift).
	if [ -f "$(SOURCEDIR)/scripts/patch_sdl3_eventfilter_guard.py" ]; then \
		python3 "$(SOURCEDIR)/scripts/patch_sdl3_eventfilter_guard.py" \
			"$(SOURCEDIR)/Natives/resources/Frameworks/libSDL3.dylib" || exit 1; \
	else \
		echo '[Amethyst] WARNING: SDL3 event-callback guard skipped; patch script is missing'; \
	fi
	echo '[Amethyst v$(VERSION)] dep_sdl3_guard - end'

# ---------------------------------------------------------------------------
# dep_sfpew — SimpleFPEWrapper (MobileGL-Dev, LGPL-3.0)
#
# Integrates SFPEW like Android's AngelAuraMC/Amethyst-Android @ feat/sfpew_angle: SFPEW sits above
# the renderer, emulates the fixed-function pipeline (GL 1.x), and forwards GL calls to the actual backend.
# Android uses a Tools.useSFPEW toggle, points SFPEW_EGL at the backend EGL, and replaces the library
# actually loaded by LWJGL with libSimpleFPEWrapper.so. On iOS, the renderer list gains a libSimpleFPEWrapper.dylib
# option, and JavaLauncher sets SFPEW_EGL to the wrapped real backend (default: libmobileglues.dylib).
#
# Depends on dep_mg: glslang / SPIRV-Cross / glm directly reuse MobileGlues' vendored
# 3rdparty tree. dep_mg aligns its pins and applies two guard patches to that same tree; serialization
# ensures SFPEW is built from the same source.
# ---------------------------------------------------------------------------
dep_sfpew: dep_mg
	echo '[Amethyst v$(VERSION)] dep_sfpew - start'
	# iOS compatibility patch (two issues exposed only with AppleClang 15 + deployment target 14.0;
	# Linux/GCC and the Android NDK do not trigger them, so upstream does not handle them):
	#   1. fpe/types.h: glstate_t's default constructor is implicitly deleted (an anonymous union contains
	#      an anonymous struct with NSDMI), breaking no_context_state / make_unique in fpe.cpp.
	#   2. fpe/fpe_shadergen.cpp: std::format depends on std::to_chars(float); that overload is marked as
	#      introduced in iOS 16.3 in the SDK, so it is "unavailable" with deployment target 14.0.
	# Both layers of the fix are required:
	#        a) Compile time — step 3 of the patch replaces std::format throughout the tree with the custom
	#           fpefmt::format (in fpe/fpe_format_compat.h; pure ostringstream, no <format> / to_chars).
	#           Replace all of std::format, not just the floating-point specifier:
	#           template expansion for std::format unconditionally includes formatter_floating_point.h;
	#           testing confirmed fpe_shadergen.cpp's std::format<unsigned,string,string> still errors.
	#           CI confirmed -Wno-unguarded-availability{,-new} cannot suppress it
	#           (those flags handle warnings only; this is an error), but they are retained as a precaution.
	#        b) Runtime — the patch replaces the only {:.1f} with snprintf. Keeping deployment
	#           target 14.0 makes the to_chars reference **weak**, so older systems resolve it as NULL;
	#           the NULL is never dereferenced unless this path is reached. (Raising the target to 16.3
	#           would create a strong reference, and dyld on physical iOS 14–16.2 devices would fail
	#           to find the symbol and crash at launch.)
	# Like patch_mobilegl_ios.py, this is idempotent and validates anchors; a mismatch exits with status 1,
	# never silently misapplies a patch and produces a broken library. Must run before cmake (which compiles source from the tree).
	python3 $(SOURCEDIR)/Natives/patch_sfpew_ios.py $(SOURCEDIR)/Natives/external/SimpleFPEWrapper || exit 1
	mkdir -p $(WORKINGDIR)/sfpew
	cd $(WORKINGDIR)/sfpew && cmake \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DCMAKE_CXX_FLAGS="-arch arm64" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DSFPEW_MG_3RDPARTY="$(SOURCEDIR)/Natives/external/MobileGlues/src/main/cpp/3rdparty" \
		$(SOURCEDIR)/Natives/external/SimpleFPEWrapper/ > $(WORKINGDIR)/sfpew_build.log 2>&1 \
		|| { echo '[dep_sfpew] cmake configure FAILED -- tail:'; tail -n 120 $(WORKINGDIR)/sfpew_build.log; exit 1; }
	cmake --build $(WORKINGDIR)/sfpew --config RelWithDebInfo -j$(JOBS) --target SimpleFPEWrapper >> $(WORKINGDIR)/sfpew_build.log 2>&1 \
		|| { echo '[dep_sfpew] build FAILED -- tail:'; tail -n 200 $(WORKINGDIR)/sfpew_build.log; exit 1; }
	cp $(WORKINGDIR)/sfpew/libSimpleFPEWrapper.dylib $(WORKINGDIR)/ || exit 1
	echo '[Amethyst v$(VERSION)] dep_sfpew - end'

dep_mobilegl:
	@{ echo '== MobileGL build diagnostics =='; \
	  echo "  BUILD_MOBILEGL      = $(BUILD_MOBILEGL)"; \
	  echo "  MOBILEGL_SOURCE_DIR = $(MOBILEGL_SOURCE_DIR)"; \
	  echo "  source exists       = `test -d '$(MOBILEGL_SOURCE_DIR)' && echo yes || echo no`"; \
	  echo "  cmake               = `cmake --version 2>&1 | head -1`"; \
	  echo "  moltenvk            = `test -f '$(MOLTENVK_LIBRARY)' && echo yes || echo no` ($(MOLTENVK_LIBRARY))"; \
	  echo "  glslang dir         = `test -d '$(MOBILEGL_SOURCE_DIR)'/3rdparty/glslang && echo yes || echo no`"; \
	  echo "  spirv-tools dir     = `test -d '$(MOBILEGL_SOURCE_DIR)'/3rdparty/DiligentCore/ThirdParty/SPIRV-Tools && echo yes || echo no`"; \
	} 2>&1 | tee $(SOURCEDIR)/mobilegl-build.log
	@if [ '$(BUILD_MOBILEGL)' != '1' ]; then \
		if [ -f "$(MOBILEGL_DYLIB)" ] && [ -f "$(MOBILEGL_GLES_DYLIB)" ]; then \
			echo '[Amethyst v$(VERSION)] dep_mobilegl - using prebuilt dylibs in Natives/resources/Frameworks/'; \
			echo '[Amethyst v$(VERSION)] dep_mobilegl - (set BUILD_MOBILEGL=1 to rebuild from vendored source)'; \
		else \
			echo '[Amethyst v$(VERSION)] dep_mobilegl - skipped (set BUILD_MOBILEGL=1 to build from vendored source)'; \
		fi; \
	elif [ ! -d "$(MOBILEGL_SOURCE_DIR)" ]; then \
		echo '[Amethyst v$(VERSION)] dep_mobilegl - skipped (source not found: $(MOBILEGL_SOURCE_DIR))'; \
	else \
		echo '[Amethyst v$(VERSION)] dep_mobilegl - start'; \
		rm -f $(SOURCEDIR)/mobilegl-build.status; \
		{ echo '== build output =='; \
		} 2>&1 | tee -a $(SOURCEDIR)/mobilegl-build.log; \
		{ { $(MAKE) -f $(abspath $(lastword $(MAKEFILE_LIST))) dep_mobilegl_build; \
		    echo $$? > $(SOURCEDIR)/mobilegl-build.status; \
		  } 2>&1 | tee -a $(SOURCEDIR)/mobilegl-build.log; \
		}; \
		echo "== exit status = `cat $(SOURCEDIR)/mobilegl-build.status 2>/dev/null` ==" | tee -a $(SOURCEDIR)/mobilegl-build.log; \
		echo '[Amethyst v$(VERSION)] dep_mobilegl - end (log: $(SOURCEDIR)/mobilegl-build.log)'; \
	fi

# MobileGL (MobileGL-Dev, LGPL-3.0):
# First successful build on 2026-08-31 (libMobileGL.dylib / libMobileGL-gles.dylib);
# output committed to the repository (55256e33) and BUILD_MOBILEGL disabled; re-enable it only when changing the source.
# MobileGL is a desktop OpenGL implementation with one binary per backend:
#   libMobileGL.dylib      -> DirectVulkan (GL -> Vulkan -> MoltenVK -> Metal)
#   libMobileGL-gles.dylib -> DirectGLES   (GL -> OpenGL ES)
# The backend is selected at runtime by the MOBILEGL_BACKEND_TYPE environment variable (see Natives/JavaLauncher.m).
#
# Reference implementation: Swung0x48/Amethyst-iOS commit dc57bfd3d2 "feat: add MobileGL renderer support".
# All perl patches below use grep -q idempotency guards: if upstream has already fixed an issue, skip the patch entirely,
# avoiding duplicate insertions or errors when the source changes.
dep_mobilegl_build:
	# asio is a header-only dependency of MobileGL, but vendoring it would add 636 files
	# (about 5 MB), and it is used only by MG_Util/Async/ShaderCompilePool.cpp. Since asio
	# is a very stable library, fetch it by tag during the build rather than adding it to the repository.
	# Use a tag (asio-1-38-2) instead of a branch: tags cannot be force-pushed, avoiding build interruptions
	# caused by upstream changes. Check for post.hpp (not the directory) so an incomplete directory can be repaired.
	if [ ! -f "$(MOBILEGL_SOURCE_DIR)/3rdparty/asio/include/asio/post.hpp" ]; then \
		echo '[Amethyst v$(VERSION)] dep_mobilegl - fetching asio (asio-1-38-2)'; \
		rm -rf $(MOBILEGL_SOURCE_DIR)/3rdparty/asio; \
		git clone --depth 1 --branch asio-1-38-2 https://github.com/chriskohlhoff/asio.git \
			$(MOBILEGL_SOURCE_DIR)/3rdparty/asio || \
			echo '[Amethyst v$(VERSION)] dep_mobilegl - WARNING: asio fetch failed, build will likely fail'; \
	fi
	mkdir -p $(MOBILEGL_SOURCE_DIR)/3rdparty/glslang/External
	ln -sfn $(MOBILEGL_SOURCE_DIR)/3rdparty/DiligentCore/ThirdParty/SPIRV-Tools $(MOBILEGL_SOURCE_DIR)/3rdparty/glslang/External/spirv-tools
	ln -sfn $(MOBILEGL_SOURCE_DIR)/3rdparty/DiligentCore/ThirdParty/SPIRV-Headers $(MOBILEGL_SOURCE_DIR)/3rdparty/glslang/External/spirv-headers
	mkdir -p $(MOBILEGL_SOURCE_DIR)/3rdparty/DiligentCore/ThirdParty/SPIRV-Tools/external
	ln -sfn $(MOBILEGL_SOURCE_DIR)/3rdparty/DiligentCore/ThirdParty/SPIRV-Headers $(MOBILEGL_SOURCE_DIR)/3rdparty/DiligentCore/ThirdParty/SPIRV-Tools/external/spirv-headers
	grep -q 'Range1D() = default' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_Util/Types.h || perl -i -pe 'if (/struct Range1D {/) { $$_ .= "        Range1D() = default; Range1D(SizeT s, SizeT e) : start(s), end(e) {}\n" }' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_Util/Types.h
	grep -q '#include <type_traits>' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_Util/Types.h || perl -i -pe 'if (index($$_, "#include <Includes.h>") == 0) { $$_ .= "#include <type_traits>\n" }' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_Util/Types.h
	grep -q 'std::is_aggregate_v<T>' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_Util/Types.h || perl -i -pe 's/        return std::make_unique\x3CT\x3E\(std::forward\x3CArgs\x3E\(args\)\.\.\.\);/        if constexpr (std::is_aggregate_v<T>) {\n            return std::unique_ptr<T>(new T{std::forward<Args>(args)...});\n        } else {\n            return std::make_unique<T>(std::forward<Args>(args)...);\n        }/' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_Util/Types.h
	grep -q 'BufferChange() = default' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_State/GLState/BufferState/BufferObject.h || perl -i -pe 'if (/struct BufferChange {/) { $$_ .= "        BufferChange() = default; BufferChange(Flags<BufferChangeBits> bits) : Bits(bits) {}\n" }' $(MOBILEGL_SOURCE_DIR)/MobileGL/MG_State/GLState/BufferState/BufferObject.h
	# AppleClang 15 (Xcode 15.4) has incomplete support for P0960 (C++20 parenthesized aggregate initialization).
	# Initializing aggregates (DefaultFramebufferInfo/Error/Range1D/BufferChange) with std::make_unique parentheses
	# / new T(args) fails; but brace-initializing non-aggregates (e.g. spirvtools Instruction has a uint32_t constructor
	# and the caller passes int) with new T{args} causes int->uint32_t narrowing. These requirements conflict.
	# Solution: dispatch with if constexpr + std::is_aggregate_v<T> —
	#   Aggregate     -> brace-init new T{args} (safe for DefaultFramebufferInfo/Error; no narrowing)
	#   Non-aggregate -> make_unique parentheses (calls the constructor; ordinary implicit int->uint32_t conversion is not narrowing)
	# After adding explicit-constructor patches, Range1D/BufferChange are no longer aggregates (is_aggregate_v=false),
	# so make_unique parentheses call Range1D(SizeT,SizeT) (ordinary int->size_t conversion).
	# Keep the Range1D/BufferChange constructor patches: GL_Buffer.cpp and others still use Range1D(x,y) parentheses
	# to directly construct temporary objects (not through MakeUnique); without the constructors, C++17 parenthesized aggregate initialization is unavailable.
	# DirectGLES backend startup crash on iOS:
	# ProbeTexture unconditionally calls glTexStorage*Multisample,
	# but a non-null function pointer does not mean the context supports it
	# (GLES 3.1+/3.2+); this can segfault under ANGLE/Metal.
	# The script is idempotent and validates its anchors, reporting source drift rather than misapplying a patch.
	python3 $(SOURCEDIR)/Natives/patch_mobilegl_ios.py $(MOBILEGL_SOURCE_DIR)
	python3 $(SOURCEDIR)/Natives/patch_mobilegl_glslang.py $(MOBILEGL_SOURCE_DIR)
	mkdir -p $(WORKINGDIR)/mobilegl
	cd $(WORKINGDIR)/mobilegl && cmake \
		-DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DCMAKE_CXX_FLAGS="-arch arm64" \
		-DMOBILEGL_IOS=ON \
		-DMOBILEGL_BUILD_TEST=OFF \
		-DMOBILEGL_BUILD_BENCHMARK=OFF \
		-DMOBILEGL_BUILD_TRACE_REPLAY=OFF \
		-DMOBILEGL_VULKAN_LIBRARY="$(MOLTENVK_LIBRARY)" \
		$(MOBILEGL_SOURCE_DIR)
	cmake --build $(WORKINGDIR)/mobilegl --config $(CMAKE_BUILD_TYPE) -j$(JOBS) --target MobileGL
	# MoltenVK 1.4.2 already uses the install name @rpath/libMoltenVK.dylib, exactly matching the name recorded at link time;
	# no rewrite is needed. Only older versions (1.2.x, with install name
	# @rpath/MoltenVK.framework/MoltenVK) require -change.
	# Detect before changing: install_name_tool -change stops the build if the target is not found, so do not run it unconditionally.
	if otool -l $(WORKINGDIR)/mobilegl/libMobileGL.dylib | grep -q 'MoltenVK.framework/MoltenVK'; then \
		install_name_tool -change @rpath/MoltenVK.framework/MoltenVK @rpath/libMoltenVK.dylib $(WORKINGDIR)/mobilegl/libMobileGL.dylib; \
		echo '[Amethyst v$(VERSION)] dep_mobilegl - rewrote MoltenVK install name (legacy layout)'; \
	else \
		echo '[Amethyst v$(VERSION)] dep_mobilegl - MoltenVK install name already @rpath/libMoltenVK.dylib, no rewrite needed'; \
	fi
	if otool -l $(WORKINGDIR)/mobilegl/libMobileGL.dylib | grep -q 'path $(SOURCEDIR)/Natives/resources/Frameworks '; then \
		install_name_tool -delete_rpath $(SOURCEDIR)/Natives/resources/Frameworks $(WORKINGDIR)/mobilegl/libMobileGL.dylib; \
	fi
	if otool -l $(WORKINGDIR)/mobilegl/libMobileGL.dylib | grep -q 'path @loader_path '; then \
		install_name_tool -delete_rpath @loader_path $(WORKINGDIR)/mobilegl/libMobileGL.dylib; \
	fi
	install_name_tool -add_rpath @loader_path $(WORKINGDIR)/mobilegl/libMobileGL.dylib
	cp $(WORKINGDIR)/mobilegl/libMobileGL.dylib $(WORKINGDIR)/libMobileGL.dylib
	# The GLES variant is a copy of the same binary; change its install_name so both dylibs can be loaded simultaneously.
	cp $(WORKINGDIR)/mobilegl/libMobileGL.dylib $(WORKINGDIR)/libMobileGL-gles.dylib
	install_name_tool -id @rpath/libMobileGL-gles.dylib $(WORKINGDIR)/libMobileGL-gles.dylib
	echo '[Amethyst v$(VERSION)] dep_mobilegl - end'

# Mithril (Uniaball/Mithril-Wrapper): OpenGL 3.3 Core -> Vulkan -> MoltenVK -> Metal.
# Unlike MobileGL, Mithril only publishes prebuilt dylibs; this repository does not build it from source.
# libmithril.dylib is committed under Natives/resources/Frameworks/, and the payload's
# `cp -R Natives/resources/*` automatically packages it in the app's Frameworks directory.
# This target only checks for its presence and prints a message; when missing, it warns but does not fail — Mithril is optional,
# and LauncherPreferences.m checks for the dylib before showing the option.
dep_mithril:
	if [ -f "$(MITHRIL_PREBUILT_DIR)/libmithril.dylib" ]; then \
		cp "$(MITHRIL_PREBUILT_DIR)/libmithril.dylib" $(SOURCEDIR)/Natives/resources/Frameworks/libmithril.dylib; \
		echo '[Amethyst v$(VERSION)] dep_mithril - installed from prebuilt/'; \
	elif [ -f "$(SOURCEDIR)/Natives/resources/Frameworks/libmithril.dylib" ]; then \
		echo '[Amethyst v$(VERSION)] dep_mithril - using existing Natives/resources/Frameworks/libmithril.dylib'; \
	else \
		echo '[Amethyst v$(VERSION)] dep_mithril - libmithril.dylib not found, Mithril renderer will be hidden'; \
		echo '[Amethyst v$(VERSION)] dep_mithril - run scripts/fetch_mithril.sh to download it'; \
	fi

assets:
	echo '[Amethyst v$(VERSION)] assets - start'
	if [ '$(IOS)' = '0' ] && [ '$(DETECTPLAT)' = 'Darwin' ]; then \
		mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/Base.lproj; \
		xcrun actool $(SOURCEDIR)/Natives/Assets.xcassets \
			--compile $(SOURCEDIR)/Natives/resources \
			--platform iphoneos \
			--minimum-deployment-target 14.0 \
			--app-icon AppIcon-Light \
			--output-partial-info-plist /dev/null || exit 1; \
	else \
		echo 'Due to the required tools not being available, you cannot compile the extras for Angel Aura Amethyst with an iOS device.'; \
	fi
	echo '[Amethyst v$(VERSION)] assets - end'

payload: native dep_mg dep_shader_shims dep_openal_shim dep_angle_freeze dep_sdl3_guard dep_nggl4es java jre assets shader-glslang-pack $(RENDERER_GAP_PAYLOAD_DEPS)
	echo '[Amethyst v$(VERSION)] payload - start'
	# ★ [26.4-SPVC] Before packaging, compare libspvc.dylib in the JAR's natives/ios|ir1 with the in-tree
	#   canonical copy (the JAR copy is actually used on-device; see check_spvc_provenance.py).
	#   Intentionally **do not block** the main build (packaging-chain changes are risky); only write differences to the build log.
	#   For a hard gate, use make check-spvc-provenance / make shader-glslang-check.
	-python3 Natives/check_spvc_provenance.py || echo '[26.4-SPVC] WARNING: spvc native provenance mismatch -- see above (make check-spvc-provenance for the hard gate)'
	# Mithril / MobileGL are optional renderers: the - prefix here prevents failures from blocking the main build.
	# If a library is missing, its renderer is automatically hidden in settings (see the existence check in LauncherPreferences.m).
	-$(MAKE) dep_mithril
	-$(MAKE) dep_mobilegl
	# SimpleFPEWrapper: no longer use the - prefix to suppress failures. The previous "optional" switch silently
	# treated compile errors as success, producing a green build even though the IPA contained no
	# libSimpleFPEWrapper.dylib (a false green). The iOS compatibility patch and compiler flags are now in place;
	# build failures must be reported loudly, following the same convention as dep_mg.
	# dep_sfpew saves cmake/compiler output and prints its tail on failure to aid diagnosis.
	$(MAKE) dep_sfpew
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/AngelAuraAmethyst.app/libs)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo17)
	cp -R $(SOURCEDIR)/Natives/resources/en.lproj/LaunchScreen.storyboardc $(WORKINGDIR)/AngelAuraAmethyst.app/Base.lproj/ || exit 1
	cp -R $(SOURCEDIR)/Natives/resources/* $(WORKINGDIR)/AngelAuraAmethyst.app/ || exit 1
	cp $(WORKINGDIR)/*.dylib $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/ || exit 1
	# spirv-cross symlink (defensive fallback): if the MobileGlues build produces libspirv-cross-c-shared.0.dylib,
	# create a libspirv-cross.dylib symlink for native code that loads the default macOS name.
	if [ -f "$(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/libspirv-cross-c-shared.0.dylib" ] && [ ! -f "$(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/libspirv-cross.dylib" ]; then \
		ln -sf libspirv-cross-c-shared.0.dylib $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/libspirv-cross.dylib; \
	fi

	# [fix/shim-overwrite-v2] Final step: the "real" libraries in resources must be copied over the shims again.
	# Reason: WORKINGDIR/*.dylib contains same-named shims (libshaderc.dylib 111 KB / libspirv-cross-c-shared.0.dylib 52 KB),
	# which overwrite the real libraries copied earlier, causing SPIRV-Cross to reject the MSL backend ("Invalid backend", create_compiler backend=3 rc=-4).
	# Also assert that these files are at least 1 MB after restoration, failing immediately to avoid silently shipping them incorrectly again.
	# Note: restore only the two spirv-cross libraries. libshaderc.dylib must remain the shim produced in WORKINGDIR —
	# it exports ame_master_compile_lock, which spvc_shim/shaderc_shim retrieve with dlopen+dlsym as a cross-library compile lock;
	# replacing it with the real library would remove the lock -> MG/shaderc would call glslang concurrently -> SIGSEGV (glslang::TParseContext::lValueErrorCheck).
	# The real implementation is in libshaderc_impl.dylib (the shim resolves it via @loader_path), so it is unaffected.
	for f in libspirv-cross-c-shared.0.dylib libspirv-cross.dylib; do 		if [ -f "$(SOURCEDIR)/Natives/resources/Frameworks/$$f" ]; then 			cp -f "$(SOURCEDIR)/Natives/resources/Frameworks/$$f" "$(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/$$f" || exit 1; 		fi; 		sz=$$(stat -f%z "$(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/$$f" 2>/dev/null || echo 0); 		if [ "$$sz" -lt 1048576 ]; then echo "ERROR: $$f is only $$sz bytes after restore"; exit 1; fi; 	done
		cp -R $(SOURCEDIR)/JavaApp/libs/others/* $(WORKINGDIR)/AngelAuraAmethyst.app/libs/ || exit 1
	cp $(SOURCEDIR)/JavaApp/build/launcher.jar $(SOURCEDIR)/JavaApp/build/patchjna_agent.jar $(SOURCEDIR)/JavaApp/build/patchsvc.jar $(SOURCEDIR)/JavaApp/build/mojang-stubs.jar $(WORKINGDIR)/AngelAuraAmethyst.app/libs/ || exit 1
	# LWJGL ships two JAR versions, and the launcher selects one at runtime based on the MC version.
	# They must be placed in their respective libs/lwjgl-<ver>/ subdirectories: if flattened into libs/, they are both
	# loaded by libs/* on the classpath, causing duplicate classes from 3.3.3 and 3.4.1 to conflict.
	mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-333 $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-341; \
	cp $(SOURCEDIR)/JavaApp/build/lwjgl-333.jar $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-333/lwjgl.jar || exit 1
	cp $(SOURCEDIR)/JavaApp/build/lwjgl-341.jar $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-341/lwjgl.jar || exit 1
	cp -R $(SOURCEDIR)/JavaApp/libs/caciocavallo/* $(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo || exit 1
	cp -R $(SOURCEDIR)/JavaApp/libs/caciocavallo17/* $(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo17 || exit 1
	# Copy TouchController static library if available
	if [ -f "$(SOURCEDIR)/TouchController/libproxy_server_ios.a" ]; then \
		mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks; \
		cp $(SOURCEDIR)/TouchController/libproxy_server_ios.a $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/ || exit 1; \
		echo '[Amethyst v$(VERSION)] Copied TouchController device library'; \
	elif [ -f "$(SOURCEDIR)/TouchController/libproxy_server_ios_simulator.a" ]; then \
		mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks; \
		cp $(SOURCEDIR)/TouchController/libproxy_server_ios_simulator.a $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/ || exit 1; \
		echo '[Amethyst v$(VERSION)] Copied TouchController simulator library'; \
	else \
		echo '[Amethyst v$(VERSION)] TouchController library not found, skipping'; \
	fi
	$(call METHOD_DIRCHECK,$(OUTPUTDIR)/Payload)
	cp -R $(WORKINGDIR)/AngelAuraAmethyst.app $(OUTPUTDIR)/Payload
	if [ '$(SLIMMED_ONLY)' != '1' ]; then \
		cp -R $(OUTPUTDIR)/java_runtimes $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app; \
	fi
	if [ -d "$(SOURCEDIR)/bundled_libraries" ]; then \
		cp -R "$(SOURCEDIR)/bundled_libraries" $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/; \
	fi
	if [ -d "$(SOURCEDIR)/bundled_versions" ]; then \
		cp -R "$(SOURCEDIR)/bundled_versions" $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/; \
	fi
	if [ -d "$(SOURCEDIR)/bundled_assets" ]; then \
		cp -R "$(SOURCEDIR)/bundled_assets" $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/; \
	fi
	ldid -S $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app; \
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		ldid -S$(SOURCEDIR)/entitlements.trollstore.xml $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	elif [ '$(PLATFORM)' == '6' ]; then \
		ldid -S$(SOURCEDIR)/entitlements.codesign.xml $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	else \
		ldid -S$(SOURCEDIR)/entitlements.sideload.xml $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	fi
	chmod -R 755 $(OUTPUTDIR)/Payload
	# Always run platform re-tagging (aligned with the Ynnyny repository). It is idempotent for Mach-O files already
	# tagged for iOS, and catches new dylibs pulled directly from Maven (e.g. 3.3.5 lwjgl-stb), which ship with
	# platform=macos and are silently rejected by iOS dyld, causing LWJGL to throw UnsatisfiedLinkError.
	# The previous [ PLATFORM != 2 ] guard assumed all committed dylibs were already tagged for iOS;
	# that assumption was broken when syncing top-level dylibs from Ynnyny.
	$(call METHOD_MACHO,$(OUTPUTDIR)/Payload/AngelAuraAmethyst.app,$(call METHOD_CHANGE_PLAT,$(PLATFORM),$$file)); \
	$(call METHOD_MACHO,$(OUTPUTDIR)/java_runtimes,$(call METHOD_CHANGE_PLAT,$(PLATFORM),$$file));
	echo '[Amethyst v$(VERSION)] payload - end'

deploy:
	echo '[Amethyst v$(VERSION)] deploy - start'
	cd $(OUTPUTDIR); \
	if [ '$(IOS)' = '1' ]; then \
		ldid -S $(WORKINGDIR)/AngelAuraAmethyst.app || exit 1; \
		ldid -S$(SOURCEDIR)/entitlements.trollstore.xml $(WORKINGDIR)/AngelAuraAmethyst.app/AngelAuraAmethyst || exit 1; \
		sudo mv $(WORKINGDIR)/*.dylib $(PREFIX)Applications/AngelAuraAmethyst.app/Frameworks/ || exit 1; \
		sudo mv $(WORKINGDIR)/AngelAuraAmethyst.app/AngelAuraAmethyst $(PREFIX)Applications/AngelAuraAmethyst.app/AngelAuraAmethyst || exit 1; \
		sudo mv $(SOURCEDIR)/JavaApp/build/launcher.jar $(SOURCEDIR)/JavaApp/build/patchjna_agent.jar $(SOURCEDIR)/JavaApp/build/patchsvc.jar $(PREFIX)Applications/AngelAuraAmethyst.app/libs/ || exit 1; \
		sudo mkdir -p $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-333 $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-341 || exit 1; \
		sudo mv $(SOURCEDIR)/JavaApp/build/lwjgl-333.jar $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-333/lwjgl.jar || exit 1; \
		sudo mv $(SOURCEDIR)/JavaApp/build/lwjgl-341.jar $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-341/lwjgl.jar || exit 1; \
		cd $(PREFIX)Applications/AngelAuraAmethyst.app/Frameworks || exit 1; \
		sudo chown -R 501:501 $(PREFIX)Applications/AngelAuraAmethyst.app/* || exit 1; \
	elif [ '$(IOS)' = '0' ] && [ '$(DETECTPLAT)' = 'Darwin' ]; then \
		if [ '$(PLATFORM)' != '2' ] || [ '$(TEAMID)' = '-1' ] || [ '$(SIGNING_TEAMID)' = '-1' ] || [ '$(PROVISIONING)' = '-1' ]; then \
			echo 'Configuration not supported for deploy recipe.'; \
		else \
			$(call METHOD_PACKAGE); \
			if [ '$(SLIMMED_ONLY)' = '0' ]; then \
				open $(OUTPUTDIR)/com.tokyxkai.metallic-$(VERSION)-$(PLATFORM_NAME).ipa; \
			else \
				open $(OUTPUTDIR)/com.tokyxkai.metallic.slimmed-$(VERSION)-$(PLATFORM_NAME).ipa; \
			fi; \
		fi; \
	else \
		echo 'Device not supported for deploy recipe.'; \
	fi
	echo '[Amethyst v$(VERSION)] deploy - end'

package: payload
	echo '[Amethyst v$(VERSION)] package - start'
	if [ '$(TEAMID)' != '-1' ] && [ '$(SIGNING_TEAMID)' != '-1' ] && [ -f '$(PROVISIONING)' ] && [ '$(DETECTPLAT)' = 'Darwin' ]; then \
		printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n	<key>application-identifier</key>\n	<string>$(TEAMID).com.tokyxkai.metallic</string>\n	<key>com.apple.developer.team-identifier</key>\n	<string>$(TEAMID)</string>\n	<key>get-task-allow</key>\n	<true/>\n	<key>keychain-access-groups</key>\n	<array>\n	<string>$(TEAMID).*</string>\n	<string>com.apple.token</string>\n	</array>\n	<key>com.apple.developer.kernel.extended-virtual-addressing</key>\n	<true/>\n	<key>com.apple.developer.kernel.increased-memory-limit</key>\n	<true/>\n</dict>\n</plist>' > entitlements.codesign.xml; \
		$(MAKE) codesign; \
		rm -rf entitlements.codesign.xml; \
	else \
		echo 'Skipped codesigning. If not intentional, check your variables.'; \
	fi
	cd $(OUTPUTDIR); \
	$(call METHOD_PACKAGE); \
	zip --symlinks -r $(OUTPUTDIR)/java_runtimes.zip java_runtimes; \
	echo '[Amethyst v$(VERSION)] package - end'

dsym: payload
	echo '[Amethyst v$(VERSION)] dsym - start'
	dsymutil --arch arm64 $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	rm -rf $(OUTPUTDIR)/AngelAuraAmethyst.dSYM; \
	mv $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst.dSYM $(OUTPUTDIR)/AngelAuraAmethyst.dSYM
	echo '[Amethyst v$(VERSION)] dsym - end'
	
codesign:
	echo '[Amethyst v$(VERSION)] codesign - start'
	cp '$(PROVISIONING)' $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/embedded.mobileprovision
	$(call METHOD_MACHO,$(OUTPUTDIR)/Payload/AngelAuraAmethyst.app,$(call METHOD_CODESIGN,$(SIGNING_TEAMID),$$file))
	$(call METHOD_MACHO,$(OUTPUTDIR)/java_runtimes,$(call METHOD_CODESIGN,$(SIGNING_TEAMID),$$file))
	echo '[Amethyst v$(VERSION)] codesign - end'

clean:
	echo '[Amethyst v$(VERSION)] clean - start'
	rm -rf $(WORKINGDIR)
	rm -rf JavaApp/build
	rm -rf $(OUTPUTDIR)
	echo '[Amethyst v$(VERSION)] clean - end'

.PHONY: all clean check native java jre package dsym deploy help swift shader-glslang-pack shader-glslang-check shader-iris-integrate verify-iris-integrate check-spvc-provenance


# ============================================================================
# ★ [RENDERER-GAP] Additional renderer build targets (from Gsjsjzhznsz/Air-Minecraft-iOS-Launcher).
#   dep_gl4eszl2 / dep_virgl are excluded from the `all`/`payload` dependency graph by default; they are added to payload only
#   when RENDERER_GAP_EXTRAS=1 (see RENDERER_GAP_PAYLOAD_DEPS at the top of this file).
#   dep_nggl4es ("Krypton Wrapper") is an exception: always included in payload and built every time.
#   These targets can also be invoked separately:
#     make dep_nggl4es
#     make RENDERER_GAP_EXTRAS=1 dep_gl4eszl2 dep_virgl
#   The resulting *.dylib files are placed in $(WORKINGDIR)/ and automatically copied into the app's Frameworks
#   by payload's "cp $(WORKINGDIR)/*.dylib"; LauncherPreferences then shows the options based on library presence.
# ============================================================================

# --- dep_nggl4es: NG-GL4ES ("Krypton Wrapper", BZLZHH/NG-GL4ES, MIT) -----------
# ZalithLauncher 2's gl4es branch: supports more advanced shaders and runs on nearly all MC versions.
# Source is in the pinned ThirdParty/NG-GL4ES submodule; see patches/ for iOS compatibility changes.
# Built as a separate cmake tree, linked against the glslang static libraries from dep_mg (pinned f5f664d 15.0.0 +
# lvalue-nullguard + pool-zero/size-guards crash-family fixes, carrying forward the crash fixes; NG's bundled
# 15.4 headers have been removed to prevent header/library drift) and the prebuilt SPIRV-Cross C API impl dylib.
# Produces libnggl4es.dylib, which payload's "cp $(WORKINGDIR)/*.dylib" packages with the app.
# Depends on dep_mg: the glslang static libraries must be ready first (order is otherwise unspecified under -j; use a target-level prerequisite).
# ★ Always included in payload (a first-class, user-visible renderer, not controlled by RENDERER_GAP_EXTRAS).
dep_nggl4es: dep_mg
	echo '[Amethyst v$(VERSION)] dep_nggl4es - start'
	if ! git -C $(SOURCEDIR)/ThirdParty/NG-GL4ES apply --unidiff-zero --reverse --check $(SOURCEDIR)/patches/ng-gl4es-ios-integration.patch >/dev/null 2>&1; then \
		git -C $(SOURCEDIR)/ThirdParty/NG-GL4ES apply --unidiff-zero $(SOURCEDIR)/patches/ng-gl4es-ios-integration.patch || exit 1; \
	fi
	mg_bindir=$(WORKINGDIR)/mobileglues/3rdparty/glslang; \
	mg_spirv_a=$$mg_bindir/SPIRV/libSPIRV.a; \
	[ -f "$$mg_spirv_a" ] || mg_spirv_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libSPIRV.a -print -quit 2>/dev/null); \
	mg_glslang_a=$$mg_bindir/glslang/libglslang.a; \
	[ -f "$$mg_glslang_a" ] || mg_glslang_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang.a -print -quit 2>/dev/null); \
	mg_rl_a=$$mg_bindir/glslang/libglslang-default-resource-limits.a; \
	[ -f "$$mg_rl_a" ] || mg_rl_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang-default-resource-limits.a -print -quit 2>/dev/null); \
	if [ -z "$$mg_spirv_a" ] || [ ! -f "$$mg_spirv_a" ] || [ -z "$$mg_glslang_a" ] || [ ! -f "$$mg_glslang_a" ] || [ -z "$$mg_rl_a" ] || [ ! -f "$$mg_rl_a" ]; then \
		echo "ERROR: [nggl4es] glslang static libs unresolved (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a) - dep_mg must run first"; \
		exit 1; \
	fi; \
	extra_glslang_libs=""; \
	for l in libOGLCompiler.a libOSDependent.a; do \
		if [ -f "$$mg_bindir/glslang/$$l" ]; then \
			extra_glslang_libs="$$extra_glslang_libs;$$mg_bindir/glslang/$$l"; \
		fi; \
	done; \
	ngg_libs="$$mg_spirv_a;$$mg_glslang_a;$$mg_rl_a$$extra_glslang_libs"; \
	echo "[nggl4es] linking against glslang statics: $$ngg_libs"; \
	mkdir -p $(WORKINGDIR)/nggl4es; \
	cd $(WORKINGDIR)/nggl4es && cmake \
		-DMACOS="1" \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DCMAKE_SHARED_LINKER_FLAGS="-F$(SOURCEDIR)/Natives/resources/Frameworks" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DNGGL4ES_GLSLANG_INCLUDE="$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty;$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang" \
		-DNGGL4ES_GLSLANG_LIBS="$$ngg_libs" \
		-DNGGL4ES_SPVC_IMPL="$(SOURCEDIR)/Natives/resources/Frameworks/libspirv-cross-c-shared.0.impl.dylib" \
		-DNGGL4ES_FRAMEWORK_DIR="$(SOURCEDIR)/Natives/resources/Frameworks" \
		$(SOURCEDIR)/ThirdParty/NG-GL4ES/ || exit 1
	cmake --build $(WORKINGDIR)/nggl4es --config RelWithDebInfo -j$(JOBS) --target ng_gl4es || exit 1
	cp $(WORKINGDIR)/nggl4es/libnggl4es.dylib $(WORKINGDIR)/ || exit 1
	echo '[Amethyst v$(VERSION)] dep_nggl4es - end'

dep_gl4eszl2:
	@echo '[Amethyst v$(VERSION)] [RENDERER-GAP] dep_gl4eszl2 - start'
	# GL4ESZL2 (PojavLauncherTeam/gl4es_extra_extra) — the classic ZL2 "gl4es" version.
	# Pure C string-rewriting GLSL→ESSL (shaderconv.c), with no glslang/SPIRV-Cross dependencies,
	# so it is an independent target (does not depend on dep_mg or compete with the glslang static libraries).
	mkdir -p $(WORKINGDIR)/gl4eszl2; \
	cd $(WORKINGDIR)/gl4eszl2 && cmake \
	-DMACOS="1" \
	-DCMAKE_CROSSCOMPILING=true \
	-DCMAKE_SYSTEM_NAME=Darwin \
	-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
	-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
	-DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
	-DCMAKE_C_FLAGS="-arch arm64" \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DGL4ESZL2_FRAMEWORK_DIR="$(SOURCEDIR)/Natives/resources/Frameworks" \
	$(SOURCEDIR)/ThirdParty/gl4es_extra_extra/ || exit 1
	cmake --build $(WORKINGDIR)/gl4eszl2 --config RelWithDebInfo -j$(JOBS) --target gl4eszl2 || exit 1
	cp $(WORKINGDIR)/gl4eszl2/libgl4eszl2.dylib $(WORKINGDIR)/ || exit 1
	@echo '[Amethyst v$(VERSION)] [RENDERER-GAP] dep_gl4eszl2 - end'

# VirGLRenderer (<=26.2, ZL2 port) consists of three components:
#  1. libepoxy            — vendored Natives/external/libepoxy (iOS patch: dlopen points to the ANGLE framework)
#  2. libvtestserver.dylib — vendored virglrenderer 1.3.0 (statically linked with epoxy)
#  3. libOSMesaVirgl.dylib — Mesa 25.0.7 (download tar.xz + patches/mesa-215-osmesa-virgl.patch)
# Fast path: if all three are already in Frameworks, skip the entire build chain.
VIRGL_MESA_VERSION ?= 25.0.7
dep_virgl:
	@if [ -f "$(SOURCEDIR)/Natives/resources/Frameworks/libOSMesaVirgl.dylib" ] && \
	    [ -f "$(SOURCEDIR)/Natives/resources/Frameworks/libvtestserver.dylib" ] && \
	    [ -f "$(SOURCEDIR)/Natives/resources/Frameworks/libepoxy.dylib" ]; then \
		echo '[Amethyst v$(VERSION)] [RENDERER-GAP] dep_virgl - cached (Frameworks prebuilts present)'; \
		cp $(SOURCEDIR)/Natives/resources/Frameworks/libOSMesaVirgl.dylib \
		   $(SOURCEDIR)/Natives/resources/Frameworks/libvtestserver.dylib \
		   $(SOURCEDIR)/Natives/resources/Frameworks/libepoxy.dylib $(WORKINGDIR)/; \
		exit 0; \
	fi
	@echo '[Amethyst v$(VERSION)] [RENDERER-GAP] dep_virgl - start'
	printf '%s\n' \
		'[binaries]' \
		"c = 'clang'" \
		"cpp = 'clang++'" \
		"ar = 'ar'" \
		"strip = 'strip'" \
		'[properties]' \
		"c_args = ['-arch','arm64','-miphoneos-version-min=14.0','-fno-common','-isysroot','$(SDKPATH)','-I$(SOURCEDIR)/Natives/external/mesa']" \
		"cpp_args = ['-arch','arm64','-miphoneos-version-min=14.0','-fno-common','-isysroot','$(SDKPATH)','-I$(SOURCEDIR)/Natives/external/mesa']" \
		"c_link_args = ['-arch','arm64','-miphoneos-version-min=14.0','-isysroot','$(SDKPATH)']" \
		"cpp_link_args = ['-arch','arm64','-miphoneos-version-min=14.0','-isysroot','$(SDKPATH)']" \
		'[host_machine]' \
		"system = 'darwin'" \
		"cpu_family = 'aarch64'" \
		"cpu = 'aarch64'" \
		"endian = 'little'" \
		> $(WORKINGDIR)/virgl-cross.txt
	rm -rf $(WORKINGDIR)/virgl-epoxy $(WORKINGDIR)/virgl-prefix
	meson setup $(WORKINGDIR)/virgl-epoxy $(SOURCEDIR)/Natives/external/libepoxy \
		--cross-file $(WORKINGDIR)/virgl-cross.txt \
		-Dglx=no -Degl=yes -Dx11=false -Dtests=false \
		-Ddefault_library=static --prefix=$(WORKINGDIR)/virgl-prefix || exit 1
	ninja -C $(WORKINGDIR)/virgl-epoxy install || exit 1
	test -f $(WORKINGDIR)/virgl-prefix/lib/libepoxy.a || { echo 'ERROR: libepoxy.a missing'; exit 1; }
	rm -rf $(WORKINGDIR)/virgl-renderer
	PKG_CONFIG_PATH=$(WORKINGDIR)/virgl-prefix/lib/pkgconfig \
	meson setup $(WORKINGDIR)/virgl-renderer $(SOURCEDIR)/Natives/external/virglrenderer \
		--cross-file $(WORKINGDIR)/virgl-cross.txt \
		-Dplatforms=egl -Dvenus=false -Dvulkan-dload=false -Dtests=false \
		-Ddefault_library=static || exit 1
	ninja -C $(WORKINGDIR)/virgl-renderer || exit 1
	test -f $(WORKINGDIR)/virgl-renderer/vtest/libvtest.a || { echo 'ERROR: libvtest.a missing'; exit 1; }
	test -f $(WORKINGDIR)/virgl-renderer/libvirglrenderer.a || { echo 'ERROR: libvirglrenderer.a missing'; exit 1; }
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libvtestserver.dylib \
		-o $(WORKINGDIR)/libvtestserver.dylib \
		-Wl,-force_load,$(WORKINGDIR)/virgl-renderer/vtest/libvtest.a \
		-Wl,-force_load,$(WORKINGDIR)/virgl-renderer/libvirglrenderer.a \
		$(WORKINGDIR)/virgl-prefix/lib/libepoxy.a \
		-lc++ || exit 1
	install_name_tool -id @rpath/libvtestserver.dylib $(WORKINGDIR)/libvtestserver.dylib || exit 1
	mkdir -p $(SOURCEDIR)/depends/virgl
	cd $(SOURCEDIR)/depends/virgl; \
		if [ ! -f mesa-$(VIRGL_MESA_VERSION)/src/gallium/targets/osmesa/.task215_patched ]; then \
			wget_ok=0; \
			for attempt in 1 2 3 4 5; do \
				if wget "https://archive.mesa3d.org/mesa-$(VIRGL_MESA_VERSION).tar.xz" --timeout=90 --tries=2 --retry-connrefused -O mesa-$(VIRGL_MESA_VERSION).tar.xz; then wget_ok=1; break; fi; \
				echo '[virgl] mesa download failed (attempt '$$attempt'/5), retry in 15s'; sleep 15; \
			done; \
			[ "$$wget_ok" = "1" ] || { echo '[virgl] FATAL: mesa download failed'; exit 1; }; \
			rm -rf mesa-$(VIRGL_MESA_VERSION) && tar xf mesa-$(VIRGL_MESA_VERSION).tar.xz; \
			( cd mesa-$(VIRGL_MESA_VERSION) && patch -p1 < $(SOURCEDIR)/patches/mesa-215-osmesa-virgl.patch \
			  && touch src/gallium/targets/osmesa/.task215_patched ) || exit 1; \
		fi
	test -f $(SOURCEDIR)/depends/virgl/mesa-$(VIRGL_MESA_VERSION)/src/gallium/targets/osmesa/.task215_patched || { echo 'ERROR: mesa patch not applied'; exit 1; }
	rm -rf $(WORKINGDIR)/virgl-mesa
	cd $(SOURCEDIR)/depends/virgl/mesa-$(VIRGL_MESA_VERSION) && meson setup $(WORKINGDIR)/virgl-mesa \
		--cross-file $(WORKINGDIR)/virgl-cross.txt \
		-Dgallium-drivers=virgl,softpipe -Dvulkan-drivers=[] \
		-Dosmesa=true -Dllvm=disabled -Dglx=disabled -Degl=disabled -Dgbm=disabled \
		-Dplatforms=[] -Dshared-glapi=disabled -Dvideo-codecs=[] \
		-Dbuild-tests=false -Dtools=[] || exit 1
	ninja -C $(WORKINGDIR)/virgl-mesa || exit 1
	test -f $(WORKINGDIR)/virgl-mesa/src/gallium/targets/osmesa/libOSMesa.8.dylib || { echo 'ERROR: libOSMesa.8.dylib (virgl guest) missing'; exit 1; }
	cp $(WORKINGDIR)/virgl-mesa/src/gallium/targets/osmesa/libOSMesa.8.dylib $(WORKINGDIR)/libOSMesaVirgl.dylib
	install_name_tool -id @rpath/libOSMesaVirgl.dylib $(WORKINGDIR)/libOSMesaVirgl.dylib || exit 1
	@echo '[Amethyst v$(VERSION)] [RENDERER-GAP] dep_virgl - end'
