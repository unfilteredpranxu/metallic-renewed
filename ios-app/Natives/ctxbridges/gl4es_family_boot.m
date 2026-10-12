//
//  gl4es_family_boot.m
//  AngelAuraAmethyst
//
//  ★ [RENDERER-GAP] Runtime bootstrap implementation for additional renderers.
//  Source: Gsjsjzhznsz/Air-Minecraft-iOS-Launcher (a later fork in the same project family):
//    - ame204_gl4esProcResolver in egl_bridge.m (Task204 backend symbol resolver binding).
//    - ame211_gl4eszl2_boot (Task211 ZL2 classic gl4es, mirrored implementation).
//    - ame208_nggl4es_boot (Task206 NG-GL4ES / "Krypton Wrapper", mirrored implementation).
//    - ame_virgl_start_server in ctxbridges/virgl_server.m (Task215 VirGL).
//  These paths have no side effects on existing renderers:
//    - Each entry first checks AMETHYST_RENDERER and returns immediately if it does not match.
//    - Each has an idempotency guard, making repeated calls effectively free.
//
//  ⚠ Not verified with a local build (no Xcode / iOS toolchain; see report ⑦). All symbols are resolved dynamically
//    with dlopen/dlsym; no renderer dylib is statically linked, so the host build does not fail if they are absent.
//
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

#include "utils.h"
#include "ctxbridges/gl4es_family_boot.h"
#include "ctxbridges/virgl_server.h"

// ---------------------------------------------------------------------------
// Task204 backend symbol resolver: resolve egl*/gl* symbols from the ANGLE frameworks and bind them to the gl4es family's
// proc_address. In the source fork this is named ame204_* in egl_bridge.m; it is consolidated here as static.
// ---------------------------------------------------------------------------
static void *ame_gap_gl4esGles2 = NULL;   // Handle for bundled libGLESv2.framework.
static void *ame_gap_gl4esEgl   = NULL;   // Handle for bundled libEGL.framework.
static void *(*ame_gap_gl4esEgpa)(const char *) = NULL;  // bundled eglGetProcAddress

static void *ame_gap_gl4esProcResolver(const char *name) {
    if (name == NULL) return NULL;
    if (strncmp(name, "gl", 2) == 0) {
        if (ame_gap_gl4esEgpa != NULL) {
            void *p = ame_gap_gl4esEgpa(name);
            if (p != NULL) return p;
        }
        if (ame_gap_gl4esGles2 != NULL) {
            void *p = dlsym(ame_gap_gl4esGles2, name);
            if (p != NULL) return p;
        }
    }
    if (strncmp(name, "egl", 3) == 0 && ame_gap_gl4esEgl != NULL) {
        void *p = dlsym(ame_gap_gl4esEgl, name);
        if (p != NULL) return p;
    }
    return NULL;
}

static void ame_gap_load_bundled_angle_egl(void) {
    if (ame_gap_gl4esEgpa != NULL) return;
    ame_gap_gl4esGles2 = dlopen("@executable_path/Frameworks/libGLESv2.framework/libGLESv2",
                                RTLD_NOW | RTLD_LOCAL);
    ame_gap_gl4esEgl = dlopen("@executable_path/Frameworks/libEGL.framework/libEGL",
                              RTLD_NOW | RTLD_LOCAL);
    ame_gap_gl4esEgpa = ame_gap_gl4esEgl
        ? (void *(*)(const char *))dlsym(ame_gap_gl4esEgl, "eglGetProcAddress")
        : NULL;
}

// Post-MakeCurrent initialization for GL4ESZL2 / NG-GL4ES (consolidates teammate ame211 / ame208).
// Both vendored trees are built with NO_INIT_CONSTRUCTOR and explicit initialize_gl4es,
// so they share this implementation and differ only in the dylib name.
static void ame_gap_gl4es_family_init(const char *dylib) {
    void *h = dlopen(dylib, RTLD_NOW | RTLD_NOLOAD | RTLD_GLOBAL);
    if (h == NULL) {
        NSLog(@"[RENDERER-GAP] %s image not loaded (RTLD_NOLOAD) -- initialize_gl4es NOT called", dylib);
        return;
    }
    ame_gap_load_bundled_angle_egl();
    int resolver = 0;
    if (ame_gap_gl4esEgpa != NULL) {
        void (*sgpa)(void *(*)(const char *)) =
            (void (*)(void *(*)(const char *)))dlsym(h, "set_getprocaddress");
        if (sgpa != NULL) {
            sgpa(ame_gap_gl4esProcResolver);
            resolver = 1;
        }
    }
    // Guard: confirm that a context is current on this thread (queried through bundled ANGLE EGL).
    if (ame_gap_gl4esEgl != NULL) {
        void *(*getCurCtx)(void) = (void *(*)(void))dlsym(ame_gap_gl4esEgl, "eglGetCurrentContext");
        if (getCurCtx != NULL && getCurCtx() == NULL) {
            NSLog(@"[RENDERER-GAP] %s boot deferred -- no current EGL context on this thread", dylib);
            return;
        }
    }
    void (*init)(void) = (void (*)(void))dlsym(h, "initialize_gl4es");
    if (init == NULL) {
        NSLog(@"[RENDERER-GAP] %s: initialize_gl4es symbol missing -- cannot init", dylib);
        return;
    }
    init();
    NSLog(@"[RENDERER-GAP] %s initialize_gl4es() called post-MakeCurrent (resolver=%@, handle=%p)",
          dylib, resolver ? @"YES" : @"NO(egpa-missing)", h);
}

bool ame_gap_renderer_selected(void) {
    const char *r = getenv("AMETHYST_RENDERER");
    return isRendererGapExtra(r);
}

void ame_gap_gl4es_family_boot(void) {
    static volatile int s_done = 0;
    if (s_done) return;
    const char *r = getenv("AMETHYST_RENDERER");
    if (r == NULL) return;

    if (strcmp(r, RENDERER_NAME_GL4ESZL2) == 0) {
        // GL4ESZL2: pure C string-rewrite shader conversion; no glslang dependency.
        ame_gap_gl4es_family_init(RENDERER_NAME_GL4ESZL2);
        s_done = 1;
    } else if (strcmp(r, RENDERER_NAME_NGGL4ES) == 0) {
        // NG-GL4ES ("Krypton Wrapper", Task206): glslang + SPIRV-Cross shader pipeline.
        // It uses the same NO_INIT_CONSTRUCTOR contract: explicitly call initialize_gl4es() here,
        // after the real context is current, or hardware probing will hit the system GLESv2 stub → SIGSEGV.
        ame_gap_gl4es_family_init(RENDERER_NAME_NGGL4ES);
        s_done = 1;
    } else if (strcmp(r, RENDERER_NAME_VGPU) == 0) {
        // VGPU has its own lazy loader (pack/load_all) and constructor; the host does not need to call initialize explicitly.
        NSLog(@"[RENDERER-GAP] VGPU selected: lazy loader handles GL init (no host initialize_gl4es)");
        s_done = 1;
    }
    // Other renderers: leave s_done unset for zero-cost re-entry (one getenv comparison).
}

int ame_gap_virgl_boot(void) {
    const char *r = getenv("AMETHYST_RENDERER");
    if (r == NULL || strcmp(r, RENDERER_NAME_VIRGL) != 0) return 0;
    int rc = ame_virgl_start_server();
    if (rc != 0) {
        NSLog(@"[RENDERER-GAP] VirGL vtest server bootstrap failed rc=%d -- osm bridge continues; "
              @"error will surface at guest connect", rc);
    }
    return rc;
}
