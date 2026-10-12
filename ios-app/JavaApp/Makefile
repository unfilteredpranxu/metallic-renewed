# Prerequisite variables
SOURCEDIR := src
OUTPUTDIR := build

SOURCES := $(shell find $(SOURCEDIR) -type f -name '*.java')
CLASSES := $(SOURCES:$(SOURCEDIR)/%.java=$(OUTPUTDIR)/%.class)

TARGETS := $(shell find $(SOURCEDIR) -mindepth 1 -maxdepth 1 -type d)
TARGETS := $(TARGETS:$(SOURCEDIR)/%=$(OUTPUTDIR)/%.jar)

# Add all jars to classpath and allow compiling with private API
# Compile-time classpath ordering: `$(wildcard libs/*/*.jar)` expands in lexicographic order.
# `libs/lwjgl < libs/lwjgl-333 < libs/lwjgl-341`, so the older precompiled Amethyst JAR
# (containing extension API members such as `GLFW.mGLFWWindowWidth`) comes before the versioned sets.
# The reference repository lists each directory explicitly to fix this order; wildcard sorting is equivalent here.
# At runtime, only `lwjgl-333.jar` / `lwjgl-341.jar` are used; `libs/lwjgl` is not a dependency.
JCFLAGS := -cp "$(subst $() $(),:,$(wildcard $(SOURCEDIR)/*/):$(wildcard libs/*/*.jar))" -XDignore.symbol.file

all: $(TARGETS) $(OUTPUTDIR)/mojang-stubs.jar

# Sometimes the CI produces empty class file resulting in broken jar, so we check and abort here
# Improvement: when an empty class file is found, copy it again from the `classes/` directory
# (fixes an occasional race between `cp` and `javac` that left secondary class files such as
# `NarratorDummy.class` empty); report an error only if the file is still empty after retrying.
check_empty_classes:
	@set -e
	@echo "Checking for empty class files"
	@for f in $$(find $(OUTPUTDIR) -not -path '$(OUTPUTDIR)/classes/*' -name '*.class' -size 0 2>/dev/null); do \
		rel=$${f#$(OUTPUTDIR)/}; \
		module=$$(echo "$$rel" | cut -d/ -f1); \
		classpath=$${rel#$$module/}; \
		src="$(OUTPUTDIR)/classes/$$classpath"; \
		if [ -f "$$src" ] && [ -s "$$src" ]; then \
			echo "Warning: re-copying empty $$classpath from classes/"; \
			cp -f "$$src" "$$f"; \
		fi; \
	done
	@EMPTY_CLASSES=$$(find $(OUTPUTDIR) -not -path '$(OUTPUTDIR)/classes/*' -name '*.class' -size 0 2>/dev/null); \
	if [ -n "$$EMPTY_CLASSES" ]; then \
		echo "Error: found empty class files in $@: $$EMPTY_CLASSES"; \
		exit 1; \
	fi

# Rules for building java class
$(CLASSES): $(OUTPUTDIR)/%.class: $(SOURCEDIR)/%.java
	@set -e
	$(eval TARGET=$(word 2, $(subst /, ,$@)))
	@mkdir -p $(OUTPUTDIR)/classes
	@mkdir -p $(dir $@)
	@echo "Compiling $<"
	@$(BOOTJDK)/javac $(JCFLAGS) -d $(OUTPUTDIR)/classes $<
	@cp $(@:$(OUTPUTDIR)/$(TARGET)/%.class=$(OUTPUTDIR)/classes/%*.class) $(dir $@)/
	@# Defensive check: CI occasionally creates empty class files (a race between cp and javac/parallel tasks).
	@# If the primary class is still 0 bytes after copying, retry once to avoid a false positive from check_empty_classes interrupting the build.
	@if [ -e "$@" ] && [ ! -s "$@" ]; then \
		echo "Warning: $@ is empty after cp, retrying copy"; \
		cp -f $(@:$(OUTPUTDIR)/$(TARGET)/%.class=$(OUTPUTDIR)/classes/%*.class) $(dir $@)/; \
	fi

$(OUTPUTDIR)/launcher.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@cp -r $(SOURCEDIR)/launcher/META-INF $(basename $@)/ 2>/dev/null || true
	@$(BOOTJDK)/jar -cf $@ -C $(basename $@) .
	@# Forge/BootstrapLauncher module resolution only considers which module exports a package:
	@# if both launcher.jar and mojang-stubs.jar contain com/mojang/text2speech, it raises
	@#   java.lang.module.ResolutionException:
	@#     Modules launcher and mojang.stubs export package com.mojang.text2speech to module logging
	@# and terminate the process. Task158 requires mojang-stubs.jar to provide these stubs (it is modularized
	@# into the MC-BOOTSTRAP layer), so remove the package from launcher.jar to leave a single provider.
	@# Note: remove entries only from the packaged JAR; do not touch the class directory in $(basename $@) —
	@# mojang-stubs.jar reads classes from that directory and is unaffected.
	@# Use "extract -> delete -> repackage" rather than `jar -d` (some JDK versions do not support `-d`;
	@# `|| true` would silently ignore the failure, leaving the package in launcher.jar in the CI artifact
	@# and causing Forge to keep throwing a module ResolutionException).
	@rm -rf $(OUTPUTDIR)/launcher_strip && mkdir -p $(OUTPUTDIR)/launcher_strip
	@(cd $(OUTPUTDIR)/launcher_strip && $(BOOTJDK)/jar -xf $(abspath $@))
	@rm -rf $(OUTPUTDIR)/launcher_strip/com/mojang/text2speech
	@# [fix/forge-split] MC itself provides com/mojang/blaze3d/**; including another copy in launcher.jar makes Forge report
	@#   ResolutionException: Module minecraft contains package com.mojang.blaze3d.platform,
	@#     module launcher exports package com.mojang.blaze3d.platform to minecraft
	@rm -rf $(OUTPUTDIR)/launcher_strip/com/mojang/blaze3d
	@cd $(OUTPUTDIR)/launcher_strip && $(BOOTJDK)/jar -cf $(abspath $@) .
	@rm -rf $(OUTPUTDIR)/launcher_strip
	@$(BOOTJDK)/jar -tf $@ | grep -qE '^com/mojang/(text2speech|blaze3d)' && { echo "ERROR: text2speech still present in $@ (Forge split-package guard failed)"; exit 1; } || true

# Produce a merged JAR for each LWJGL version (3.3.3 and 3.4.1).
#
# Extraction order determines overwrite priority (later entries overwrite earlier ones):
#   1) Repository-root lwjgl.jar — the iOS-specific LWJGL patch layer, also providing LWJGL2 compatibility classes
#      (org/lwjgl/opengl/Display, org/lwjgl/input/Keyboard, LWJGLException, etc.),
#      Older MC versions (Java 8 / 1.12.2 and earlier) depend on these classes, so keep them as the base.
#   2) libs/lwjgl-<ver>/*.jar — versioned LWJGL3. The 341 set contains the actual
#      lwjgl-sdl.jar (loads the real libSDL3), required for SDL3 input injection.
#      Extract it after the base so versioned LWJGL3 core classes (GLFW / MemoryUtil / SDL, etc.)
#      overwrite same-named older classes from the root JAR.
#   3) build/lwjgl/ — Amethyst overlay (rewritten classes such as GLFW.java with the iOS bridge),
#      which must be applied last.
$(OUTPUTDIR)/lwjgl-%.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib_$*
	@cd $(OUTPUTDIR)/lwjgl_lib_$* && $(BOOTJDK)/jar -xf "../../../lwjgl.jar" && rm -rf META-INF
	# The repository-root lwjgl.jar includes 3 classes compiled with JDK 25 (major version 69):
	#   org/lwjgl/openal/SOFTSystemEvent{,s,ProcI}.class
	# This is a custom build where "3.3.3 provides 3.4.1 API compatibility"; these 3 classes were copied from 3.4.1.
	# 3.4.1 includes Java 8 versions of them, which will overwrite these when extracted next. But 3.3.3 lacks
	# these classes, so keeping the JDK 25 versions would cause older MC versions on Java 8 to throw
	# UnsupportedClassVersionError when they load them. Remove them before overlaying the versioned JARs.
	@cd $(OUTPUTDIR)/lwjgl_lib_$* && find org/lwjgl/openal -maxdepth 1 -name 'SOFTSystemEvent*.class' -delete 2>/dev/null || true
	@cd $(OUTPUTDIR)/lwjgl_lib_$* && find ../../libs/lwjgl-$* -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl_lib_$*/
	@# Forge / NeoForge's bootstraplauncher passes the entire classpath to JPMS for resolution; each classpath JAR
	@# becomes an automatic module. Any package present in both launcher.jar and lwjgl-<ver>.jar causes split-package
	@# resolution to fail (ResolutionException: Modules launcher and lwjgl export package …).
	@# launcher.jar already includes these classes and SPI, so remove the duplicate packages from lwjgl JARs here (without an intermediate list file).
	@rm -rf $(OUTPUTDIR)/lwjgl_lib_$*/com/apple/ios/audio
	@rm -rf $(OUTPUTDIR)/lwjgl_lib_$*/com/mojang
	@rm -f  $(OUTPUTDIR)/lwjgl_lib_$*/META-INF/services/javax.sound.sampled.spi.MixerProvider
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl_lib_$* .

# lwjgl.jar is only a placeholder: the all target lists it because src/lwjgl is a source directory,
# but runtime uses lwjgl-333.jar / lwjgl-341.jar. build/lwjgl.jar must not be placed in the app's libs directory,
# or it will load alongside libs/* and the versioned JARs on the classpath, causing same-name class conflicts.
$(OUTPUTDIR)/lwjgl.jar: $(OUTPUTDIR)/lwjgl-333.jar $(OUTPUTDIR)/lwjgl-341.jar
	@echo "Skipping $@ (lwjgl-333.jar / lwjgl-341.jar are used instead)"

$(OUTPUTDIR)/patchjna_agent.jar: $(CLASSES)
	@set -e
	@mv $(basename $@)/com/sun/jna/Platform.class $(basename $@)/com/sun/jna/Platform.class.patch
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cfm $@ $(SOURCEDIR)/patchjna_agent.txt -C $(basename $@) .

$(OUTPUTDIR)/patchsvc.jar: $(CLASSES)
	@set -e
	@mv $(basename $@)/de/maxhenkel/lame4j/Mp3Decoder.class $(basename $@)/de/maxhenkel/lame4j/Mp3Decoder.class.patch
	@mv $(basename $@)/de/maxhenkel/lame4j/Mp3Encoder.class $(basename $@)/de/maxhenkel/lame4j/Mp3Encoder.class.patch
	@mv $(basename $@)/de/maxhenkel/opus4j/OpusDecoder.class $(basename $@)/de/maxhenkel/opus4j/OpusDecoder.class.patch
	@mv $(basename $@)/de/maxhenkel/opus4j/OpusEncoder.class $(basename $@)/de/maxhenkel/opus4j/OpusEncoder.class.patch
	@mv $(basename $@)/de/maxhenkel/rnnoise4j/Denoiser.class $(basename $@)/de/maxhenkel/rnnoise4j/Denoiser.class.patch
	@mv $(basename $@)/de/maxhenkel/speex4j/AutomaticGainControl.class $(basename $@)/de/maxhenkel/speex4j/AutomaticGainControl.class.patch
	@rm -rf $(basename $@)/de/maxhenkel/*/*.class
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cfm $@ $(SOURCEDIR)/patchsvc.txt -C $(basename $@) .

# Task 158 (Forge module-layer Mojang stubs): Forge's MC-BOOTSTRAP/GAME module layers
# cannot see the system class loader (securejarhandler ModuleClassLoader's parent chain is
# the boot/platform layer), while launcher.jar is excluded from the module layer by -DignoreList
# (Task154's split-package fix). The com.mojang.text2speech stubs required by GameNarrator inside
# the module layer must therefore be provided by a JAR that BootstrapLauncher will modularize.
# This JAR contains only com/mojang/text2speech stubs (same source and bytecode as launcher.jar;
# getNarrator() always returns NarratorDummy, with no narrator side effects on iOS). It is bundled in
# app/libs/ → always on -cp → always in java.class.path → automatically becomes an automatic module
# in MC-BOOTSTRAP (its filename has no ignoreList prefix). The real text2speech library remains
# _skipped by Java-side preProcessLibraries (adding it to the classpath would split the package with the stubs).
# Device validation: Forge 1.20.1 passes GameNarrator (NoClassDefFoundError: Narrator no longer occurs).
$(OUTPUTDIR)/mojang-stubs.jar: $(OUTPUTDIR)/launcher.jar
	@set -e
	@rm -rf $(OUTPUTDIR)/mojang-stubs
	@mkdir -p $(OUTPUTDIR)/mojang-stubs/com/mojang
	@if [ ! -d "$(OUTPUTDIR)/launcher/com/mojang/text2speech" ]; then \
		echo "ERROR: launcher classes missing com/mojang/text2speech (Task158 mojang-stubs)"; \
		exit 1; \
	fi
	@cp -R $(OUTPUTDIR)/launcher/com/mojang/text2speech $(OUTPUTDIR)/mojang-stubs/com/mojang/
	@cd $(OUTPUTDIR)/mojang-stubs && $(BOOTJDK)/jar -cf ../mojang-stubs.jar com
	@echo "Created $(OUTPUTDIR)/mojang-stubs.jar (Forge module-layer com.mojang.text2speech stubs, Task158)"


clean:
	rm -rf $(OUTPUTDIR)

.SUFFIXES: .java
.PHONY: all clean
