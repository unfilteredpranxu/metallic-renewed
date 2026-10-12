//
//  virgl_server.m
//  Amethyst-iOS-MyRemastered
//
//  Task 111: VirGLRenderer (≤26.2) server bootstrap bridge (ported from ZalithLauncher2).
//
//  Architecture (matching the in-process model in ZL2 virgl_bridge.c, with our ANGLE/Metal as the host GL):
//
//    MC(LWJGL) --gl*--> libOSMesaVirgl.dylib (Mesa 25.0.7 virgl driver, GALLIUM_DRIVER=virgl)
//        --vtest protocol (unix socket, VTEST_SOCKET_NAME)--> libvtestserver.dylib
//        (virglrenderer 1.3.0 + libepoxy) --epoxy(EGL/GLES)--> ANGLE framework --> Metal
//
//    Presentation: reuse the zink path in osm_bridge (OSMesaMakeCurrent + authoritative glReadPixels readback
//    during swap + display through CGImage). The guest's glReadPixels retrieves pixels from the server through
//    vtest transfer, so the result is correct by design.
//
//  This file does only three things:
//    1. Determine the socket path and set VTEST_SOCKET_NAME / GALLIUM_DRIVER=virgl.
//    2. Create an offscreen (1x1 pbuffer) ES3 host context using the ANGLE framework bundled with the app.
//    3. Start a thread that calls libvtestserver.dylib's vtest_main after MakeCurrent with
//       "--no-loop-or-fork" "--use-gles" "--socket-path" <path>.
//       (vrend uses epoxy to create its own GLES context on the same EGL display as needed.)
//
//  Note: internal vtest_server error paths call exit(1) (upstream behavior, also present in ZL2).
//  The socket uses unlink+bind, making a second startup safe; --no-loop-or-fork serves one client
//  and returns when the guest disconnects.
//

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <dlfcn.h>

#include "virgl_server.h"

// ---------------------------------------------------------------------------
// Raw ANGLE EGL function pointers (resolved from the libEGL.framework bundled with the app;
// uses the same raw ANGLE approach as gl_bridge.m and keeps this file self-contained).
// ---------------------------------------------------------------------------
typedef unsigned int EGLBoolean;
typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef intptr_t EGLNativeDisplayType;
typedef intptr_t EGLint;

static EGLDisplay (*ame_vs_eglGetDisplay)(EGLNativeDisplayType);   // ★ [SHADER-GLSLANG] Build unblock: EGL eglGetDisplay returns EGLDisplay (void*); the old typedef incorrectly used EGLBoolean, causing a native -Wint-conversion error that blocked the full build.
static EGLBoolean (*ame_vs_eglInitialize)(EGLDisplay, EGLint *, EGLint *);
static EGLBoolean (*ame_vs_eglBindAPI)(unsigned int);
static EGLBoolean (*ame_vs_eglChooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);
static EGLSurface (*ame_vs_eglCreatePbufferSurface)(EGLDisplay, EGLConfig, const EGLint *);
static EGLContext (*ame_vs_eglCreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
static EGLBoolean (*ame_vs_eglMakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);

static EGLDisplay ame_vs_display;
static EGLSurface ame_vs_pbuffer;
static EGLContext ame_vs_context;
static char ame_vs_socket_path[512];
static int ame_vs_started = 0;

// vtest server entry point (exported by libvtestserver.dylib; upstream vtest_server.c:135).
static int (*ame_vs_vtest_main)(int argc, char **argv);

// EGL constants (avoid an EGL header dependency).
#define AME_VS_EGL_DEFAULT_DISPLAY   ((EGLNativeDisplayType)0)
#define AME_VS_EGL_OPENGL_ES_API     0x30A0
#define AME_VS_EGL_SURFACE_TYPE      0x3033
#define AME_VS_EGL_PBUFFER_BIT       0x0001
#define AME_VS_EGL_RENDERABLE_TYPE   0x3040
#define AME_VS_EGL_OPENGL_ES2_BIT    0x0004
#define AME_VS_EGL_RED_SIZE          0x3024
#define AME_VS_EGL_GREEN_SIZE        0x3023
#define AME_VS_EGL_BLUE_SIZE         0x3022
#define AME_VS_EGL_ALPHA_SIZE        0x3021
#define AME_VS_EGL_WIDTH             0x3057
#define AME_VS_EGL_HEIGHT            0x3056
#define AME_VS_EGL_CONTEXT_CLIENT_VERSION 0x3098
#define AME_VS_EGL_NONE              0x3038

static void *ame_vs_server_thread(void *arg __unused)
{
    // Same order as ZL2: MakeCurrent first (vrend detects the current context/display through epoxy),
    // then enter the vtest main loop.
    if (ame_vs_eglMakeCurrent(ame_vs_display, ame_vs_pbuffer, ame_vs_pbuffer, ame_vs_context) != 1) {
        NSLog(@"[VirGL] Task111 host eglMakeCurrent failed -- server thread aborting");
        return NULL;
    }

    void *handle = dlopen("@rpath/" AME_VIRGL_VTEST_SERVER_LIB, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        NSLog(@"[VirGL] Task111 dlopen %s failed: %s", AME_VIRGL_VTEST_SERVER_LIB, dlerror() ?: "unknown");
        return NULL;
    }
    ame_vs_vtest_main = (int (*)(int, char **))dlsym(handle, "vtest_main");
    if (!ame_vs_vtest_main) {
        NSLog(@"[VirGL] Task111 vtest_main not found in %s", AME_VIRGL_VTEST_SERVER_LIB);
        return NULL;
    }

    NSLog(@"[VirGL] Task111 starting vtest server (no-loop-or-fork, use-gles, socket=%s)", ame_vs_socket_path);
    // getopt_long requires argv[argc] == NULL; arguments match ZL2 exactly, with an explicit socket path added.
    char arg0[] = "vtest";
    char arg1[] = "--no-loop-or-fork";
    char arg2[] = "--use-gles";
    char arg3[] = "--socket-path";
    char *argv[] = { arg0, arg1, arg2, arg3, ame_vs_socket_path, NULL };
    int rc = ame_vs_vtest_main(5, argv);
    NSLog(@"[VirGL] Task111 vtest server finished with rc=%d (guest disconnected?)", rc);
    return NULL;
}

int ame_virgl_start_server(void)
{
    if (ame_vs_started) {
        return 0; // Idempotent.
    }

    // ---- 1. Socket path + guest environment variables (must be set before osm_bridge dlopens the guest). ----
    const char *pojavHome = getenv("POJAV_HOME");
    if (!pojavHome || !*pojavHome) {
        pojavHome = getenv("HOME");
    }
    snprintf(ame_vs_socket_path, sizeof(ame_vs_socket_path), "%s/.virgl_test",
             (pojavHome && *pojavHome) ? pojavHome : "/tmp");
    setenv("VTEST_SOCKET_NAME", ame_vs_socket_path, 1);
    setenv("GALLIUM_DRIVER", "virgl", 1);

    // ---- 2. Raw ANGLE EGL: offscreen host context. ----
    void *egl = dlopen("@rpath/libEGL.framework/libEGL", RTLD_NOW | RTLD_LOCAL);
    if (!egl) {
        NSLog(@"[VirGL] Task111 dlopen ANGLE libEGL failed: %s", dlerror() ?: "unknown");
        return -1;
    }
    ame_vs_eglGetDisplay = (void *)dlsym(egl, "eglGetDisplay");
    ame_vs_eglInitialize = (void *)dlsym(egl, "eglInitialize");
    ame_vs_eglBindAPI = (void *)dlsym(egl, "eglBindAPI");
    ame_vs_eglChooseConfig = (void *)dlsym(egl, "eglChooseConfig");
    ame_vs_eglCreatePbufferSurface = (void *)dlsym(egl, "eglCreatePbufferSurface");
    ame_vs_eglCreateContext = (void *)dlsym(egl, "eglCreateContext");
    ame_vs_eglMakeCurrent = (void *)dlsym(egl, "eglMakeCurrent");
    if (!ame_vs_eglGetDisplay || !ame_vs_eglInitialize || !ame_vs_eglChooseConfig ||
        !ame_vs_eglCreatePbufferSurface || !ame_vs_eglCreateContext || !ame_vs_eglMakeCurrent ||
        !ame_vs_eglBindAPI) {
        NSLog(@"[VirGL] Task111 ANGLE EGL symbol resolution incomplete");
        return -1;
    }

    ame_vs_display = ame_vs_eglGetDisplay(AME_VS_EGL_DEFAULT_DISPLAY);
    if (!ame_vs_display) {
        NSLog(@"[VirGL] Task111 eglGetDisplay failed");
        return -1;
    }
    if (ame_vs_eglInitialize(ame_vs_display, NULL, NULL) != 1) {
        NSLog(@"[VirGL] Task111 eglInitialize failed");
        return -1;
    }
    ame_vs_eglBindAPI(AME_VS_EGL_OPENGL_ES_API);

    const EGLint config_attribs[] = {
        AME_VS_EGL_SURFACE_TYPE, AME_VS_EGL_PBUFFER_BIT,
        AME_VS_EGL_RENDERABLE_TYPE, AME_VS_EGL_OPENGL_ES2_BIT,
        AME_VS_EGL_RED_SIZE, 8,
        AME_VS_EGL_GREEN_SIZE, 8,
        AME_VS_EGL_BLUE_SIZE, 8,
        AME_VS_EGL_ALPHA_SIZE, 8,
        AME_VS_EGL_NONE
    };
    EGLConfig config = NULL;
    EGLint num_configs = 0;
    if (ame_vs_eglChooseConfig(ame_vs_display, config_attribs, &config, 1, &num_configs) != 1 ||
        !config || num_configs < 1) {
        NSLog(@"[VirGL] Task111 eglChooseConfig found no pbuffer ES config");
        return -1;
    }

    const EGLint pbuffer_attribs[] = {
        AME_VS_EGL_WIDTH, 1,
        AME_VS_EGL_HEIGHT, 1,
        AME_VS_EGL_NONE
    };
    ame_vs_pbuffer = ame_vs_eglCreatePbufferSurface(ame_vs_display, config, pbuffer_attribs);
    if (!ame_vs_pbuffer) {
        NSLog(@"[VirGL] Task111 eglCreatePbufferSurface failed");
        return -1;
    }

    const EGLint ctx_attribs[] = {
        AME_VS_EGL_CONTEXT_CLIENT_VERSION, 3,
        AME_VS_EGL_NONE
    };
    ame_vs_context = ame_vs_eglCreateContext(ame_vs_display, config, NULL /* no share */, ctx_attribs);
    if (!ame_vs_context) {
        NSLog(@"[VirGL] Task111 eglCreateContext(ES3) failed");
        return -1;
    }

    // ---- 3. Service thread. ----
    pthread_t thread;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    // vrend shader compilation can recurse deeply on the server; provide a large stack (based on the 32 MB main_hook value).
    pthread_attr_setstacksize(&attr, 16 * 1024 * 1024);
    int rc = pthread_create(&thread, &attr, ame_vs_server_thread, NULL);
    pthread_attr_destroy(&attr);
    if (rc != 0) {
        NSLog(@"[VirGL] Task111 pthread_create failed: %d", rc);
        return -1;
    }

    // Same as ZL2: allow the server 100 ms to finish bind+listen and enter accept (the backlog also handles
    // earlier connections; this is an additional safeguard).
    usleep(100 * 1000);

    ame_vs_started = 1;
    NSLog(@"[VirGL] Task111 server bootstrap complete (socket=%s, ES3 host ctx=%p)",
          ame_vs_socket_path, ame_vs_context);
    return 0;
}
