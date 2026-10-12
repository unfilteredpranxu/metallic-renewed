#pragma once

#include <Foundation/Foundation.h>
#include "jni.h"

typedef jint JLI_Launch_func(int argc, const char ** argv, /* main argc, argc */
        int jargc, const char** jargv,          /* java args */
        int appclassc, const char** appclassv,  /* app classpath */
        const char* fullversion,                /* full version defined */
        const char* dotversion,                 /* dot version defined */
        const char* pname,                      /* program name */
        const char* lname,                      /* launcher name */
        jboolean javaargs,                      /* JAVA_ARGS */
        jboolean cpwildcard,                    /* classpath wildcard*/
        jboolean javaw,                         /* windows-only javaw */
        jint ergo                               /* ergonomics class policy */
);
JLI_Launch_func *pJLI_Launch;

int launchJVM(NSString *accountId, id launchTarget, int width, int height, int minVersion);

// Task98: Extract the major Minecraft version (using the year-based version scheme) from any version ID format
// (release "26.3" / snapshot "26w14a" / Fabric "fabric-loader-0.19.5-26.3-e4ecd7db" / Forge "1.20.1-forge-47.3.0").
// Return 1 for the 1.x lineage and 0 if parsing fails.
// Shared by ResolveLwjglVersion (LWJGL 333/341 selection) and SurfaceViewController's
// LTW × 26.x preflight check (ame87_mcVersionRequiresTextureBuffer) to keep both checks consistent
// (see the implementation header comment in JavaLauncher.m).
NSInteger ame98_mcMajorFromVersionId(NSString *versionId);

// Headless JVM: start a JVM in the current process with minimal arguments (no caciocavallo/LWJGL/rendering)
// and run the specified main class. Used by Forge/NeoForge direct installation to run install_profile processors.
// Returns the JLI_Launch result (0 = success); negative values are launcher-side errors:
//   -1 JIT is not enabled / legacy JIT script requires an app restart
//   -2 JLI_Launch symbol is missing
//   -3 No usable JRE runtime
//   -4 Failed to dlopen libjli
//   -5 A JVM has already been created in this process (restart the app)
int launchHeadlessJVM(NSString *mainClass, NSArray<NSString *> *args, int minJavaVersion);

// Whether a JVM has already been created in the current process (for a game or headless run).
// Only one JVM can be created per process; another JLI_Launch would crash. Callers use this to prompt the user to restart the app.
BOOL JVMUsedInProcess(void);

// Task 144: flag to suppress exit during headless JVM execution (defined in main_hook.m).
// Forge/NeoForge direct-install processors run in the launcher process. When the installer JVM finishes,
// an internal libjli thread calls exit(0), terminating the entire app (seen by users as "Forge installation crashes").
// The launchHeadlessJVM caller (ForgeProcessorExecutor) sets/clears this flag;
// when hooked_exit sees it, it calls pthread_exit to terminate only the JVM thread and keep the process alive.
#include <stdatomic.h>
extern atomic_int g_ame_suppressJvmExit;

// Task 146: headless JVM termination signal (defined in main_hook.m).
// Device logs confirmed (2026-09-22 23:38 session, build a82c14f4) that libjli's termination design
// is to have the "dummyTimer thread call exit(0) to terminate the entire process" — it never returns
// to the JLI_Launch caller. After suppressing exit with pthread_exit, launchHeadlessJVM would hang
// inside JLI with pthread_join waiting forever (on-device behavior: endless "0.85 (4/4)" updates).
// This flag is set on both termination paths:
//   1) hooked_exit suppression branch (exit(0) intercepted = JVM finished normally);
//   2) ame146 thread function when launchHeadlessJVM actually returns (JLI launch-failure semantics).
// ForgeProcessorExecutor now waits for this flag instead of pthread_join.
extern atomic_int g_ame_headlessJvmFinished;
