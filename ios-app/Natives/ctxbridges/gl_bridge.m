#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "SurfaceViewController.h"
#import "LauncherPreferences.h"

#include <dlfcn.h>
#include <string.h>
#include <time.h>
#include <stdatomic.h>
#include "bridge_tbl.h"
#include "environ.h"
#include "gl_bridge.h"
#include "utils.h"

// ---------------------------------------------------------------------------
// Compatibility shim: Amethyst_SDL3SurfaceWantsPoints().
//
// Air Task 60 (664f58a3) finalized the retirement of the "1x point alignment" represented by this function (Task 50).
// It always returns NO, making the 1x branch unreachable (the function was also removed on the Air side). It was historically
// referenced here by sdl3_hook / SurfaceViewController; to avoid an undefined symbol after syncing gl_bridge with Air,
// retain this exported implementation that always returns NO. Its only call site has been removed as on Air;
// this remains solely as an ABI safeguard and does not change behavior.
// ---------------------------------------------------------------------------
BOOL Amethyst_SDL3SurfaceWantsPoints(void) {
    return NO;
}

static EGLDisplay g_EglDisplay;
static egl_library handle;

// ============================================================================
// Black-screen diagnostics (Task 32): atomic eglSwapBuffers success/failure counters.
//
// Background (device test in latestlog b199c07): the game started fully (all 390 shaders converted,
// resources/atlases/sounds loaded, SDL event loop alive, MC events queued), but the screen was black.
// The old gl_swap_buffers logged only when eglGetError()==EGL_BAD_SURFACE and stayed silent for
// other errors (EGL_BAD_NATIVE_WINDOW / EGL_CONTEXT_LOST / EGL_BAD_ALLOC, etc.). pojavSwapBuffers
// printed "First frame rendered" unconditionally, which did not prove that a frame reached the screen.
// These counters and SurfaceVC's five-second heartbeat ([RenderDiag] fps= swapOK= swapFail=) provide a definitive diagnosis:
//   - swapFail keeps increasing → presentation path is broken (layer/surface lifecycle issue).
//   - swapOK increases but the screen is black → frames are swapped to the wrong target (occlusion/size/scale issue).
//   - neither changes → render thread is stuck (render loop blocked late in startup).
// ============================================================================
static _Atomic unsigned long g_eglSwapOK = 0;
static _Atomic unsigned long g_eglSwapFail = 0;

// ============================================================================
// Task 76: track swap-interval spikes (frame-pacing diagnostics).
//
// Background (bef0f08 log comparison): MG/MobileGlues sessions fluctuated sharply from 5 to 60 fps,
// while Zink stayed stable at 40–53 fps; users felt "30 fps looked like 10 fps." Average FPS hides
// frame-time spikes: a window at 5 fps means a 200 ms frame, while 60 Hz VSync (the MG session never
// exceeded 60 even with max.fps=260 unlocked) quantizes frame arrivals to 16.7 ms intervals.
// Missing-frame cadence causes the perceived stutter. On successful gl_swap_buffers calls, record
// intervals between swaps and track the max and average over each five-second heartbeat window.
// Report them with [RenderDiag] so device logs can compare pacing before and after fixes.
// Access is render-thread-only (swap already runs there), so atomics are unnecessary.
// ============================================================================
static uint64_t ame76_last_swap_ms = 0;   // 0 = no first frame yet.
static uint32_t ame76_max_gap_ms = 0;     // Maximum frame interval in this window.
static uint64_t ame76_gap_sum_ms = 0;     // Sum of intervals in this window (millisecond precision is sufficient).
static uint32_t ame76_gap_count = 0;      // Number of interval samples in this window.

void ame_egl_swap_stats(unsigned long *ok, unsigned long *fail) {
    if (ok) *ok = atomic_load(&g_eglSwapOK);
    if (fail) *fail = atomic_load(&g_eglSwapFail);
}

// Task 76: read and reset frame-interval window statistics (called by SurfaceViewController's five-second heartbeat).
// When count==0, report 0 for both max and average. The first frame is not an interval sample (cold-start timing is meaningless).
void ame_egl_swap_framegap(uint32_t *maxGapMs, uint32_t *avgGapMs) {
    uint32_t mx = ame76_max_gap_ms;
    uint32_t avg = ame76_gap_count ? (uint32_t)(ame76_gap_sum_ms / ame76_gap_count) : 0;
    if (maxGapMs) *maxGapMs = mx;
    if (avgGapMs) *avgGapMs = avg;
    ame76_max_gap_ms = 0;
    ame76_gap_sum_ms = 0;
    ame76_gap_count = 0;
}

static void ame76_record_swap(uint64_t now_ms) {
    if (ame76_last_swap_ms != 0 && now_ms > ame76_last_swap_ms) {
        uint32_t gap = (uint32_t)(now_ms - ame76_last_swap_ms);
        if (gap > ame76_max_gap_ms) ame76_max_gap_ms = gap;
        ame76_gap_sum_ms += gap;
        ame76_gap_count++;
    }
    ame76_last_swap_ms = now_ms;
}

// ============================================================================
// Task 77: frame-phase timing (attribute time separately to present vs. build).
//
// Background (66e57f0 dual MG logs plus quantized correlation analysis): MG avgGap fluctuated
// between 17 ms and 250 ms (60↔4 fps), while a same-day Zink session on the same build stayed at 37–53 fps.
// After excluding GC/memory/shader compilation/FSR1/diagnostic probes/depth workarounds, 250 ms
// could occur only in one of two render-thread frame-loop phases:
//   build   = return from the previous eglSwapBuffers → entry into the current gl_swap_buffers
//             (MC tick + event pump + CPU cost of GL encoding through MobileGlues/ANGLE).
//   present = inside handle.eglSwapBuffers (ANGLE Metal command submission + nextDrawable wait + GPU catch-up;
//             blocks when maxDrawableCount=3 is exhausted).
// This timer separately accumulates average/max values for each phase over five-second windows and reports them in [RenderDiag].
// The next device log will distinguish the cause directly:
//   presAvg/presMax ≈ avgGap   → ANGLE Metal presentation/GPU side (switching renderer or lowering resolutionScale helps; CPU optimization does not).
//   buildAvg/buildMax ≈ avgGap → MC frame CPU side (GL translation cost; optimize per-draw MobileGlues/ANGLE overhead).
// Accumulate at microsecond precision (normal 1–2 ms presents disappear into rounding noise at millisecond precision),
// then convert to milliseconds for reporting. Access is render-thread-only; atomics are unnecessary.
// ============================================================================
static uint64_t ame77_last_swap_end_us = 0;   // Time the previous swap returned (0 = none).
static uint64_t ame77_present_sum_us = 0;     // Total present duration in this window.
static uint32_t ame77_present_max_us = 0;     // Maximum present duration in this window.
static uint32_t ame77_present_count = 0;      // Number of present samples in this window.
static uint64_t ame77_build_sum_us = 0;       // Total build duration in this window.
static uint32_t ame77_build_max_us = 0;       // Maximum build duration in this window.
static uint32_t ame77_build_count = 0;        // Number of build samples in this window.

static uint64_t ame77_now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ull + (uint64_t)ts.tv_nsec / 1000ull;
}

// Task 77: read and reset frame-phase window statistics (called by SurfaceViewController's five-second heartbeat).
// All values are converted to milliseconds (rounded down); when count==0, the corresponding avg/max is 0.
void ame_egl_swap_phase_stats(uint32_t *presentAvgMs, uint32_t *presentMaxMs,
                              uint32_t *buildAvgMs, uint32_t *buildMaxMs) {
    uint32_t pAvg = ame77_present_count ? (uint32_t)(ame77_present_sum_us / ame77_present_count / 1000ull) : 0;
    uint32_t pMax = ame77_present_count ? ame77_present_max_us / 1000u : 0;
    uint32_t bAvg = ame77_build_count ? (uint32_t)(ame77_build_sum_us / ame77_build_count / 1000ull) : 0;
    uint32_t bMax = ame77_build_count ? ame77_build_max_us / 1000u : 0;
    if (presentAvgMs) *presentAvgMs = pAvg;
    if (presentMaxMs) *presentMaxMs = pMax;
    if (buildAvgMs) *buildAvgMs = bAvg;
    if (buildMaxMs) *buildMaxMs = bMax;
    ame77_present_sum_us = 0;
    ame77_present_max_us = 0;
    ame77_present_count = 0;
    ame77_build_sum_us = 0;
    ame77_build_max_us = 0;
    ame77_build_count = 0;
}

// Task 77: record the build phase at swap entry (previous present ended → current frame enters swap).
static void ame77_record_build(uint64_t now_us) {
    if (ame77_last_swap_end_us != 0 && now_us > ame77_last_swap_end_us) {
        uint32_t dur = (uint32_t)(now_us - ame77_last_swap_end_us);
        if (dur > ame77_build_max_us) ame77_build_max_us = dur;
        ame77_build_sum_us += dur;
        ame77_build_count++;
    }
}

// Task 77: time the present phase (duration inside eglSwapBuffers), counting both success and failure
// (a slow failed present is still evidence for attribution).
static void ame77_record_present(uint64_t dur_us, uint64_t now_us) {
    if (dur_us > ame77_present_max_us) ame77_present_max_us = (uint32_t)dur_us;
    ame77_present_sum_us += dur_us;
    ame77_present_count++;
    ame77_last_swap_end_us = now_us;
}

// ============================================================================
// Task 50: cross-thread ownership flag for the GL presentation layer.
//
// currentBundle (bridge_tbl.h) is __thread and is non-NULL only on the render thread;
// the main thread (updateSavedResolution) always reads NULL. A cross-thread atomic flag is therefore needed:
// set it after the GL path successfully creates a surface in gl_init_context and clear it in gl_terminate.
// SurfaceViewController uses it to determine whether GL owns the presentation layer and align the layer
// to native-scale pixels (Task60's single source of truth for geometry; see the Task60 alignment block
// in gl_init_context. Task50's 1x mode was retired because CA's linear 2x upscaling caused blur).
// The Vulkan path creates no EGL surface, so the flag remains 0 and the main thread keeps its old 2x behavior
// (MoltenVK manages drawableSize independently).
// ============================================================================
static _Atomic int g_ame50_gl_owns_layer = 0;

bool ame_gl_surface_owns_layer(void) {
    return atomic_load(&g_ame50_gl_owns_layer) != 0;
}

// ============================================================================
// Task 41: capture GL state at swap time + self-heal presentation (diagnose black screens on the GL path).
//
// State (latestlog d638c22): swapOK=529, fps=57, all 390 shaders compiled without a crash,
// atlases/audio loaded and the splash screen removed, yet the display was black. The MC RenderPearl
// GL backend created its own 1180x820 double-buffered FBO swapchain ([MG] depth allocations #1/#2,
// both D32F 1180x820). The remaining question was whether MC's composited frame reached FBO 0
// (ANGLE's window back buffer), or was discarded by the translation layer.
//
// This block runs before each eglSwapBuffers (on the MC render thread, with the MC context current):
//   1) Probe frames #1–#5 and every 200 frames: log DRAW/READ bindings and viewport via glGetIntegerv,
//      and surface dimensions via eglQuerySurface (official Task58 constants).
//      **Task 75 retired readback probes:** log 4770b53 proved that on swap#8400 (game pause screen,
//      reduced frame rate from dynamic_fps), probe glReadPixels triggered ANGLE Metal
//      readPixelsCopyImpl → CopyBGRA8ToRGBA8 SIGBUS while reading the CAMetalLayer drawable about to be
//      presented. Intermittent iOS glReadPixels crashes are known in the community; the upstream
//      herbrine8403/Amethyst-iOS swap path from this code lineage never reads pixels back.
//      The content uniq/fbo0/corner fields were removed with that probe.
//   2) Self-healing latch (Task 75 uses geometry checks and no readback): matching geometry (viewport==surface)
//      selects mode=normal; mismatched geometry uses Task55 realign / Task49 geo-heal blit
//      (blit only, no readback, deterministic). The black-screen investigation (Tasks 41–58) is closed:
//      geometry checks plus the presentation-layer guard (Task52) cover all known cases.
//
// Resolve ES pointers through the same pinning path as MG (@executable_path/Frameworks/
// libGLESv2.framework/libGLESv2), pointing to the same ANGLE image. This also applies to renderers
// such as gl4es, whose underlying contexts are also ANGLE ES contexts.
// ============================================================================
typedef void (*ame_es_getint_t)(unsigned int, int *);
typedef void (*ame_es_bindfb_t)(unsigned int, unsigned int);
typedef unsigned int (*ame_es_geterr_t)(void);
typedef unsigned char (*ame_es_isenabled_t)(unsigned int);
typedef void (*ame_es_enable_t)(unsigned int, unsigned char);
typedef void (*ame_es_blitfb_t)(int, int, int, int, int, int, int, int, unsigned int, unsigned int);
typedef void (*ame_es_bindtex_t)(unsigned int, unsigned int);
typedef void (*ame_es_texparami_t)(unsigned int, unsigned int, int);
typedef void (*ame_es_gentex_t)(int, unsigned int *);
typedef void (*ame_es_deltex_t)(int, const unsigned int *);
typedef void (*ame_es_teximg2d_t)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *);
typedef void (*ame_es_genfb_t)(int, unsigned int *);
typedef void (*ame_es_delfb_t)(int, const unsigned int *);
typedef void (*ame_es_fbtex2d_t)(unsigned int, unsigned int, unsigned int, unsigned int, int);
typedef unsigned int (*ame_es_checkfb_t)(unsigned int);

typedef struct {
    ame_es_getint_t    getIntegerv;
    ame_es_bindfb_t    bindFramebuffer;
    ame_es_geterr_t    getError;
    ame_es_isenabled_t isEnabled;
    ame_es_enable_t    enable;
    ame_es_blitfb_t    blitFramebuffer;
    EGLBoolean (*querySurface)(EGLDisplay, EGLSurface, EGLint, EGLint *);
    ame_es_bindtex_t   bindTexture;        // Task 49 geometry self-healing.
    ame_es_texparami_t texParameteri;      // Task 49 geometry self-healing.
    ame_es_gentex_t    genTextures;        // Task 49 geometry self-healing.
    ame_es_deltex_t    deleteTextures;     // Task 49 geometry self-healing.
    ame_es_teximg2d_t  texImage2D;         // Task 49 geometry self-healing.
    ame_es_genfb_t     genFramebuffers;    // Task 49 geometry self-healing.
    ame_es_delfb_t     deleteFramebuffers; // Task 49 geometry self-healing.
    ame_es_fbtex2d_t   framebufferTexture2D; // Task 49 geometry self-healing.
    ame_es_checkfb_t   checkFramebufferStatus; // Task 49 geometry self-healing.
} ame_es_t;

static ame_es_t ame_es(void) {
    static ame_es_t s_es;
    static BOOL s_tried = NO;
    if (s_tried) return s_es;
    s_tried = YES;
    static const char *const kCandidates[] = {
        "@executable_path/Frameworks/libGLESv2.framework/libGLESv2",
        "@rpath/libGLESv2.framework/libGLESv2",
        "libGLESv2",
        NULL,
    };
    void *h = NULL;
    for (int i = 0; kCandidates[i] != NULL; ++i) {
        h = dlopen(kCandidates[i], RTLD_NOW | RTLD_LOCAL);
        if (h != NULL) {
            NSLog(@"[RenderDiag] Task41 ES probe pinned to %s", kCandidates[i]);
            break;
        }
    }
    if (h == NULL) {
        NSLog(@"[RenderDiag] Task41 ES probe unavailable (libGLESv2 not loadable)");
        return s_es;
    }
    s_es.getIntegerv     = (ame_es_getint_t)dlsym(h, "glGetIntegerv");
    s_es.bindFramebuffer = (ame_es_bindfb_t)dlsym(h, "glBindFramebuffer");
    // Task 75: glReadPixels resolution was removed (readback probes retired; no readback in the swap path).
    s_es.getError        = (ame_es_geterr_t)dlsym(h, "glGetError");
    s_es.isEnabled       = (ame_es_isenabled_t)dlsym(h, "glIsEnabled");
    s_es.enable          = (ame_es_enable_t)dlsym(h, "glEnable");
    s_es.blitFramebuffer = (ame_es_blitfb_t)dlsym(h, "glBlitFramebuffer");
    // Task 49: FBO/texture management functions required by geometry self-healing blits (same libGLESv2/ANGLE).
    s_es.bindTexture     = (ame_es_bindtex_t)dlsym(h, "glBindTexture");
    s_es.texParameteri   = (ame_es_texparami_t)dlsym(h, "glTexParameteri");
    s_es.genTextures     = (ame_es_gentex_t)dlsym(h, "glGenTextures");
    s_es.deleteTextures  = (ame_es_deltex_t)dlsym(h, "glDeleteTextures");
    s_es.texImage2D      = (ame_es_teximg2d_t)dlsym(h, "glTexImage2D");
    s_es.genFramebuffers = (ame_es_genfb_t)dlsym(h, "glGenFramebuffers");
    s_es.deleteFramebuffers = (ame_es_delfb_t)dlsym(h, "glDeleteFramebuffers");
    s_es.framebufferTexture2D = (ame_es_fbtex2d_t)dlsym(h, "glFramebufferTexture2D");
    s_es.checkFramebufferStatus = (ame_es_checkfb_t)dlsym(h, "glCheckFramebufferStatus");
    // eglQuerySurface is in libEGL (ANGLE EGL), from the same ANGLE family as libGLESv2;
    // dlopen on the already loaded image only increments its reference count. Resolve it here to avoid
    // a forward dependency on ame_raw_query_surface later in this file (its static declaration is below).
    static const char *const kEglCandidates[] = {
        "@executable_path/Frameworks/libEGL.framework/libEGL",
        "@rpath/libEGL.framework/libEGL",
        "libEGL",
        NULL,
    };
    for (int i = 0; kEglCandidates[i] != NULL; ++i) {
        void *he = dlopen(kEglCandidates[i], RTLD_NOW | RTLD_LOCAL);
        if (he != NULL) {
            s_es.querySurface = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLint, EGLint *))dlsym(he, "eglQuerySurface");
            break;
        }
    }
    return s_es;
}

// Task 75: ame_count_unique_rgba / ame_float_readback_has_content were retired with the readback probe
// (their only caller was the probe's content check; keeping them would trigger dead-code warnings).
// The entire 8x8 readback → unique-value count → "has content" check is removed.

// ============================================================================
// Task 49: geometry self-healing blit (two-pass scratch-FBO intermediate).
//
// Conclusive evidence in latestlog 53febda (d11eb66): MC's frame was in the back buffer but covered
// only the viewport (1180x820 SDL3 points), while the surface used 2x pixels (2360x1640 or 1640x2360).
// The frame occupied only the upper-left ~25% of the back buffer; the rest stayed uniformly dark
// (corner=27, nearly black). This looked like a "black screen." The old mode-2 blit read drawFb and
// drew to 0, but tests showed drawFb==0 at MC swap time (bound to the default framebuffer), turning
// the blit into an FBO0→FBO0 self-copy. Overlapping rectangles are invalid/no-op in ES, and the old
// latch condition was never met, so self-healing never started.
//
// New design (geometry-based, no readback, deterministic every frame):
//   viewport dimensions != surface dimensions → the frame cannot cover the back buffer → perform two blits:
//     Pass 1: READ = viewport region of (drawFb ? drawFb : 0) → scratch (scaled to surface dimensions).
//     Pass 2: READ = scratch → DRAW = full FBO 0 surface (1:1).
//   Neither pass has overlapping rectangles, so both are valid in ES3. The frame is scaled to fill the
//   entire back buffer and becomes full-screen, regardless of 1x/2x unit mismatch, portrait/landscape
//   transposition, creation races, or leftover rotation state.
//   Recreate scratch lazily (reallocate the same texture with glTexImage2D) when the surface size changes.
// ============================================================================
static unsigned int g_ame49_scratch_fb = 0;
static unsigned int g_ame49_scratch_tex = 0;
static int g_ame49_scratch_w = 0, g_ame49_scratch_h = 0;
static int g_ame49_heal_disabled = 0;   // Permanently disable after scratch FBO completeness failure.
// Task51: presentation layer reference (CFBridgingRetain). Declared before use because the swap diagnostic
// function (Fix F' pinning and hierarchy dump) appears earlier in this file. Its original declaration
// in the Task48 section was after the use; CI run b9634f4 reported an undeclared identifier.
static void *g_ame48_layer_cf = NULL;

// Task52: embedded SDL touch view from sdl3_hook.m (used by the visibility guard to enforce z-order).
// Returns an unretained __bridge pointer for identity comparison only; do not dereference or retain it as an ARC object.
extern void *ame_hook_getEmbeddedSDLView(void);

static void ame_task49_geo_heal_blit(ame_es_t es, int drawFb, int readFb,
                                     int vw, int vh, int sw, int sh) {
    if (g_ame49_heal_disabled) return;
    if (es.genFramebuffers == NULL || es.genTextures == NULL ||
        es.texImage2D == NULL || es.framebufferTexture2D == NULL ||
        es.checkFramebufferStatus == NULL || es.bindTexture == NULL ||
        es.texParameteri == NULL || es.blitFramebuffer == NULL) {
        g_ame49_heal_disabled = 1;   // Missing function pointers: disable healing (creation enforcement/guard pinning remain active).
        return;
    }
    // 1) Match scratch size to the surface (create lazily / reallocate when dimensions change).
    if (g_ame49_scratch_fb == 0 || g_ame49_scratch_w != sw || g_ame49_scratch_h != sh) {
        if (g_ame49_scratch_fb == 0) {
            es.genFramebuffers(1, &g_ame49_scratch_fb);
            es.genTextures(1, &g_ame49_scratch_tex);
        }
        es.bindTexture(0x0DE1 /*GL_TEXTURE_2D*/, g_ame49_scratch_tex);
        es.texImage2D(0x0DE1, 0, 0x8058 /*GL_RGBA8*/, sw, sh, 0,
                      0x1908 /*GL_RGBA*/, 0x1401 /*GL_UNSIGNED_BYTE*/, NULL);
        es.texParameteri(0x0DE1, 0x2801 /*GL_TEXTURE_MIN_FILTER*/, 0x2601 /*GL_LINEAR*/);
        es.texParameteri(0x0DE1, 0x2800 /*GL_TEXTURE_MAG_FILTER*/, 0x2601 /*GL_LINEAR*/);
        es.bindFramebuffer(0x8D40 /*GL_FRAMEBUFFER*/, g_ame49_scratch_fb);
        es.framebufferTexture2D(0x8D40, 0x8CE0 /*GL_COLOR_ATTACHMENT0*/,
                                0x0DE1, g_ame49_scratch_tex, 0);
        if (es.checkFramebufferStatus(0x8D40) != 0x8CD5 /*GL_FRAMEBUFFER_COMPLETE*/) {
            NSLog(@"[RenderDiag] Task49 scratch FBO incomplete %dx%d -- geo-heal fused off", sw, sh);
            es.bindFramebuffer(0x8D40, (unsigned)drawFb);
            while (es.getError() != 0) {}
            if (g_ame49_scratch_fb != 0) es.deleteFramebuffers(1, &g_ame49_scratch_fb);
            if (g_ame49_scratch_tex != 0) es.deleteTextures(1, &g_ame49_scratch_tex);
            g_ame49_scratch_fb = 0; g_ame49_scratch_tex = 0;
            g_ame49_scratch_w = 0; g_ame49_scratch_h = 0;
            g_ame49_heal_disabled = 1;
            return;
        }
        g_ame49_scratch_w = sw; g_ame49_scratch_h = sh;
        NSLog(@"[RenderDiag] Task49 scratch FBO ready %dx%d", sw, sh);
    }
    // 2) Save/disable scissor and perform the two blits.
    int scissorWasOn = es.isEnabled(0x0C11 /*GL_SCISSOR_TEST*/);
    if (scissorWasOn) es.enable(0x0C11, 0 /*GL_FALSE*/);
    // Pass 1: MC frame (viewport region, sourced from MC's current FBO or FBO 0) → scratch, scaled to full size.
    es.bindFramebuffer(0x8CA8 /*GL_READ_FRAMEBUFFER*/, (unsigned)(drawFb != 0 ? drawFb : 0));
    es.bindFramebuffer(0x8CA9 /*GL_DRAW_FRAMEBUFFER*/, g_ame49_scratch_fb);
    es.blitFramebuffer(0, 0, vw, vh, 0, 0, sw, sh,
                       0x4000 /*GL_COLOR_BUFFER_BIT*/, 0x2601 /*GL_LINEAR*/);
    // Pass 2: scratch → entire FBO 0 surface at 1:1.
    es.bindFramebuffer(0x8CA8, g_ame49_scratch_fb);
    es.bindFramebuffer(0x8CA9, 0);
    es.blitFramebuffer(0, 0, sw, sh, 0, 0, sw, sh,
                       0x4000, 0x2601 /*GL_LINEAR*/);
    unsigned int blitErr = es.getError();
    // 3) Restore state.
    es.bindFramebuffer(0x8CA8, (unsigned)readFb);
    es.bindFramebuffer(0x8CA9, (unsigned)drawFb);
    if (scissorWasOn) es.enable(0x0C11, 1 /*GL_TRUE*/);
    while (es.getError() != 0) {}
    static unsigned long s_blitLogs = 0;
    s_blitLogs++;
    if (s_blitLogs <= 3 || s_blitLogs % 300 == 0 || blitErr != 0) {
        NSLog(@"[RenderDiag] geo-heal blit #%lu (Task49): srcFb=%d %dx%d -> scratch %dx%d -> FBO0 %dx%d blitErr=0x%x",
              s_blitLogs, drawFb, vw, vh, sw, sh, sw, sh, blitErr);
    }
}

// ============================================================================
// Task 53: realign the EGL surface (root-cause fix for split images and input problems).
//
// Device evidence (latestlog f4ab8e3, first on-device log after Task52 fixed the black screen,
// on iPad Air M4 / iPadOS 26.6):
//   - Surface creation initially reported 1180x820 (confirmed twice with eglQuerySurface), but by the first
//     swap it had transposed to 820x1180 and remained stuck for 1,400+ frames. The transposition occurred
//     during the loading "blind window" with no swaps: window events/UIKit layout briefly switched to portrait,
//     and ANGLE captured the transposed geometry when rereading the layer. Task48 proved it did not return
//     to landscape with the layer.
//   - MC viewport remained 1180x820: the frame was clipped to the left 820 columns of the transposed buffer,
//     then Task49 geo-heal blit squeezed the whole frame into 820x1180.
//   - drawableSize oscillated between updateSavedResolution (writing landscape bounds 1180x820) and the
//     Task52 guard (writing the transposed surface size 820x1180), overwriting each other every 200 frames.
//     On landscape drawable frames, blit covered only the left 820x820, leaving 360 columns of original frame
//     on the right: the user saw a split image (squeezed left half + right-side remnant).
//   - Touch input mapped over the full 1180x820-point window (Task51's px→pt conversion was correct),
//     but the displayed image was offset/squeezed, so taps missed visible buttons ("input problems").
//
// Fix (address the root cause—the transposition—so all compensations become harmless no-ops):
//   On first detection of mismatched geometry, destroy the EGL window surface before recreating it. Task48
//   recreation always failed with EGL_BAD_ALLOC (0x3003) because it created before destroying, leaving two
//   surfaces on the same layer. Destroying first (unbind with MakeCurrent, then destroy) frees the layer:
//     1) On the main thread, dispatch_sync to pin the layer (contentsScale=1.0, drawableSize=bounds in points).
//        Task50 established that main-thread writes are the only reliable path.
//     2) Unbind via eglMakeCurrent with no surface → eglDestroySurface(old) → eglCreateWindowSurface
//        (reads the pinned landscape layer) → eglMakeCurrent(new surface). Task36 frontend routing preserves
//        MGContext tracking; the frontend passes EGL_NO_SURFACE through unchanged, which is safe.
//     3) Once successful, surface == viewport == drawable == bounds: geometry mismatch no longer triggers,
//        geo-heal exits automatically (Task50 latch recovery), the write conflict ends naturally (both writers
//        write the same value), the image is full-screen at 1:1, and touch coordinates align with the image.
//     4) Fallback on failure: three-attempt budget + two-second rate limit; any failed step permanently disables
//        retries and falls back to existing Task49/51/52 compensation paths (no worse than before, no regressions).
// ============================================================================
static int      g_ame53_attempts = 0;    // Retry budget consumed.
static uint64_t g_ame53_last_ms = 0;     // Time of the last attempt (two-second rate limit).
static int      g_ame53_disabled = 0;    // Circuit breaker: budget exhausted or a step failed.
static int      g_ame53_transposed = 0;  // Flag indicating surface/MC viewport mismatch.
// Used by updateSavedResolution to determine when to stop writing: while a mismatch remains unfixed,
// let the Task52 guard exclusively write drawableSize and end the write conflict. Refreshed every swap.

bool ame_gl_surface_transposed(void) {
    return g_ame53_transposed != 0;
}

static uint64_t ame53_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)ts.tv_nsec / 1000000ull;
}

// ---- Task 55: three helpers for progressive realignment. ----

// Synchronously wait for a number of main-queue runloop turns (force [CATransaction flush] on each turn
// to commit CA transactions immediately and give ANGLE a chance to react if it observes layer/CA notifications;
// nested dispatch_sync calls guarantee at least the requested number of main-queue cycles).
static void ame55_wait_main_turns(int turns) {
    for (int i = 0; i < turns; ++i) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            @try { [CATransaction flush]; } @catch (NSException *e) {}
        });
    }
}

// Block the render thread for ms milliseconds using a main-queue dispatch_after barrier. The main runloop
// continues normally during the wait, giving CA/ANGLE time to clean up. This is the real destroy/recreate
// gap required by Step B.
static void ame55_main_gap_ms(uint64_t ms) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)ms * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ dispatch_semaphore_signal(sem); });
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

// Healing criterion: querySurface matches the layer's expected geometry (the same authoritative source used by the swap probe).
// If outQ is non-NULL, fill it with actual queried values (for log fingerprints).
static BOOL ame55_verify_surface(ame_es_t es, EGLSurface s, CGSize expected,
                                 EGLint *outQW, EGLint *outQH) {
    if (es.querySurface == NULL || s == EGL_NO_SURFACE) return NO;
    EGLint w = 0, h = 0;
    // Task 58 root-cause fix (conclusive explanation for the split image): EGL_HEIGHT=0x3056 and
    // EGL_WIDTH=0x3057 (official definitions in egl.h, Natives/external/mesa/EGL/egl.h:90/123).
    // The old code swapped these constants (0x3056 used for width, 0x3057 for height), reversing the
    // dimensions and making the "healing check" always fail. This explains why earlier Task53/55 realign
    // attempts logged "NOT cured (recreate reads transposed geometry)": the recreated surface was actually
    // healthy landscape geometry all along.
    if (!es.querySurface(g_EglDisplay, s, EGL_WIDTH, &w) ||
        !es.querySurface(g_EglDisplay, s, EGL_HEIGHT, &h)) return NO;
    if (outQW) *outQW = w;
    if (outQH) *outQH = h;
    return (w == (EGLint)MAX(1.0, round(expected.width))) &&
           (h == (EGLint)MAX(1.0, round(expected.height)));
}

/// Task 55 progressive surface realignment (replaces Task53's single destroy/recreate attempt).
/// Caller: MC render thread (swap path, context current).
/// Returns YES when querySurface == layer bounds (actual healing; caller resets latch mode).
///
/// Interpretation of on-device log a901050 (Task 54 build, 2026-09-11 23:10; prompted this design):
///   - Initial querySurface=1180x820 was correct; during the blind window (8,500 log lines loaded, zero swaps)
///     it transposed to 820x1180. After Task53's destroy-first recreation it was **still 820x1180**,
///     despite recreating against the landscape layer (pin logged bounds 1180x820).
///   - The old check declared SUCCESS after verifying only that create returned non-NULL (a false positive),
///     then cleared transposed=0, lifted updateSavedResolution's ceasefire, restored drawableSize oscillation,
///     and caused the split image seen in this test.
///   - Existing logs cannot determine which ANGLE source provides the transposed dimensions (transform chain /
///     UIScreen fallback / swapchain cache). Progressive steps test all three hypotheses independently and log
///     fingerprints; any successful step heals the surface, and total failure leaves decisive evidence for the next log.
///
/// Progressive steps (stop after the first successful heal):
///   A. Geometry signal (no destruction): on the main thread, set drawableSize=bounds, nudge bounds
///      (write back any 1-point discrepancy in the same transaction), allow two main-runloop turns
///      with CATransaction flush, then query. Hypothesis: ANGLE listens for layer geometry events
///      (the transposition in 622166a proves that it follows such changes).
///   B. Delayed recreation (strengthened Task53 approach): destroy → wait a real 100 ms (to avoid immediate
///      handle reclamation/reuse, suspected because old and new handles were both 0x1 last time) →
///      recreate with explicit landscape attributes → MakeCurrent → two turns → query.
///   C. Reverse-transposition journey: set drawableSize to transposed dimensions → two turns → restore
///      landscape bounds → two turns → query. This reproduces the forward journey during the blind window
///      and finishes in landscape; if ANGLE follows events, the final size should win.
/// If all fail, this attempt fails (three-step budget and two-second cooldown unchanged; compensation
/// continues after the circuit breaker trips).
static BOOL ame_task53_realign_surface(void) {
    if (g_ame53_disabled) return NO;
    if (g_ame53_attempts >= 3) {
        g_ame53_disabled = 1;
        NSLog(@"[GLGeo] Task55 realign: budget exhausted after %d attempts -- fused off, compensation path continues", g_ame53_attempts);
        return NO;
    }
    uint64_t now = ame53_now_ms();
    if (g_ame53_last_ms != 0 && now - g_ame53_last_ms < 2000) return NO;
    g_ame53_last_ms = now;
    g_ame53_attempts++;

    basic_render_window_t *bundle = currentBundle;
    CALayer *layer = (__bridge CALayer *)g_ame48_layer_cf;
    if (bundle == NULL || layer == nil || ![layer isKindOfClass:CAMetalLayer.class]) {
        NSLog(@"[GLGeo] Task55 realign: prerequisites missing (bundle/layer) -- fused off");
        g_ame53_disabled = 1;
        return NO;
    }

    NSLog(@"[GLGeo] Task55 realign: attempt %d/3 (gradient A geometry-signal -> B deferred-recreate -> C transpose-roundtrip)",
          g_ame53_attempts);

    // Expected geometry: authoritative main-thread bounds × contentsScale, in pixels (Task60).
    // The surface/query/drawable pipeline now consistently uses pixels; the old 1x point-based pin
    // made verification always FAIL and caused healing to reset drawableSize to 1x.
    __block CGSize pin55 = CGSizeZero;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            CGFloat w55 = MAX(1.0, round(layer.bounds.size.width));
            CGFloat h55 = MAX(1.0, round(layer.bounds.size.height));
            CGFloat sc55 = layer.contentsScale;
            if (sc55 <= 0.0) sc55 = 1.0;
            pin55 = CGSizeMake(round(w55 * sc55), round(h55 * sc55));
        } @catch (NSException *e) {
            NSLog(@"[GLGeo] Task55 pin exception: %@", e);
        }
    });
    if (pin55.width < 1 || pin55.height < 1) {
        NSLog(@"[GLGeo] Task55 realign FAILED: layer pin unavailable -- fused off, compensation continues");
        g_ame53_disabled = 1;
        return NO;
    }

    ame_es_t es55 = ame_es();
    EGLSurface cur55 = bundle->gl.surface;
    EGLint q55w = 0, q55h = 0;

    // --- Step A: geometry signal without destruction. ---
    NSLog(@"[GLGeo] Task55 realign stepA: drawableSize=bounds + bounds nudge + 2 main turns (no destroy)");
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            CAMetalLayer *mlA = (CAMetalLayer *)layer;
            mlA.drawableSize = pin55;
            // Nudge bounds: write back a 1-point discrepancy (the original value is committed in the same
            // CA transaction, so there is no visible flicker); this forces CA/KVO to emit a layer-geometry-change notification.
            CGRect bA = layer.bounds;
            layer.bounds = CGRectMake(bA.origin.x, bA.origin.y, bA.size.width, bA.size.height + 1.0);
            layer.bounds = bA;
        } @catch (NSException *e) {
            NSLog(@"[GLGeo] Task55 stepA exception: %@", e);
        }
    });
    ame55_wait_main_turns(2);
    if (ame55_verify_surface(es55, cur55, pin55, &q55w, &q55h)) {
        NSLog(@"[GLGeo] Task55 realign CURED by stepA: query=%dx%d == bounds %.0fx%.0f (ANGLE follows layer geometry; transposed lock released)",
              q55w, q55h, pin55.width, pin55.height);
        return YES;
    }
    NSLog(@"[GLGeo] Task55 stepA verify: query=%dx%d expected=%.0fx%.0f -- NOT cured (ANGLE ignored drawableSize+bounds nudge)",
          q55w, q55h, pin55.width, pin55.height);

    // --- Step B: destroy + real 100 ms gap + recreate (avoid immediate handle reclamation/reuse). ---
    NSLog(@"[GLGeo] Task55 realign stepB: destroy -> 100ms gap -> recreate (explicit landscape attribs)");
    EGLContext ctx55 = bundle->gl.context;
    EGLSurface old55 = cur55;
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx55);
    handle.eglDestroySurface(g_EglDisplay, old55);
    while (handle.eglGetError() != EGL_SUCCESS) {}
    ame55_main_gap_ms(100);

    const BOOL mobileGL55 = isMobileGLRenderer(getenv("AMETHYST_RENDERER"));
    EGLSurface new55 = EGL_NO_SURFACE;
    for (int try55 = 0; try55 < 2 && new55 == EGL_NO_SURFACE; try55++) {
        const EGLint attribs55[] = {
            EGL_WIDTH,  (EGLint)pin55.width,
            EGL_HEIGHT, (EGLint)pin55.height,
            EGL_NONE
        };
        new55 = handle.eglCreateWindowSurface(g_EglDisplay, bundle->gl.config,
            (__bridge EGLNativeWindowType)layer,
            (mobileGL55 || try55 > 0) ? attribs55 : NULL);
        if (new55 == EGL_NO_SURFACE) {
            NSLog(@"[GLGeo] Task55 create attempt %d failed: eglError=0x%x", try55 + 1,
                  (unsigned int)(uintptr_t)handle.eglGetError());
        }
    }
    if (new55 == EGL_NO_SURFACE) {
        NSLog(@"[GLGeo] Task55 stepB FAILED: recreation refused after destroy+gap (old surface %p) -- fused off, compensation continues",
              (void *)old55);
        bundle->gl.surface = EGL_NO_SURFACE;
        g_ame53_disabled = 1;
        return NO;
    }
    if (!handle.eglMakeCurrent(g_EglDisplay, new55, new55, ctx55)) {
        NSLog(@"[GLGeo] Task55 stepB FAILED: eglMakeCurrent error 0x%x -- fused off",
              (unsigned int)(uintptr_t)handle.eglGetError());
        handle.eglDestroySurface(g_EglDisplay, new55);
        bundle->gl.surface = EGL_NO_SURFACE;
        g_ame53_disabled = 1;
        return NO;
    }
    bundle->gl.surface = new55;
    cur55 = new55;
    while (handle.eglGetError() != EGL_SUCCESS) {}
    ame55_wait_main_turns(2);
    if (ame55_verify_surface(es55, cur55, pin55, &q55w, &q55h)) {
        NSLog(@"[GLGeo] Task55 realign CURED by stepB: surface %p -> %p, query=%dx%d == bounds %.0fx%.0f",
              (void *)old55, (void *)new55, q55w, q55h, pin55.width, pin55.height);
        return YES;
    }
    NSLog(@"[GLGeo] Task55 stepB verify: query=%dx%d expected=%.0fx%.0f -- NOT cured (recreate reads transposed geometry)",
          q55w, q55h, pin55.width, pin55.height);

    // --- Step C: reverse-transposition journey. ---
    NSLog(@"[GLGeo] Task55 realign stepC: transpose roundtrip (drawableSize transposed -> turns -> landscape -> turns)");
    __block CGSize pinC = pin55;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            CAMetalLayer *mlC = (CAMetalLayer *)layer;
            mlC.drawableSize = CGSizeMake(pinC.height, pinC.width);
        } @catch (NSException *e) {
            NSLog(@"[GLGeo] Task55 stepC exception: %@", e);
        }
    });
    ame55_wait_main_turns(2);
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            CAMetalLayer *mlC = (CAMetalLayer *)layer;
            mlC.drawableSize = pinC;
        } @catch (NSException *e) {
            NSLog(@"[GLGeo] Task55 stepC exception: %@", e);
        }
    });
    ame55_wait_main_turns(2);
    if (ame55_verify_surface(es55, cur55, pin55, &q55w, &q55h)) {
        NSLog(@"[GLGeo] Task55 realign CURED by stepC: query=%dx%d == bounds %.0fx%.0f (event-follow confirmed: roundtrip landed landscape)",
              q55w, q55h, pin55.width, pin55.height);
        return YES;
    }
    NSLog(@"[GLGeo] Task55 stepC verify: query=%dx%d expected=%.0fx%.0f -- NOT cured (gradient exhausted this attempt; compensation continues, retry after cooldown)",
          q55w, q55h, pin55.width, pin55.height);
    return NO;
}

// Main probe + self-healing entry point. swapIndex starts at 1.
// 0 = undecided, 1 = normal, 2 = geo-heal blit.
static void ame_task41_swap_forensics(EGLSurface surface, unsigned long swapIndex) {
    ame_es_t es = ame_es();
    if (es.getIntegerv == NULL || es.bindFramebuffer == NULL) return;

    static int s_mode = 0;          // 0 undecided / 1 normal / 2 blit
    // Task 76: reduce diagnostic frequency — perform no GL/EGL queries before swap in healthy NORMAL mode.
    //
    // Background (confirmed by paired logs in bef0f08): since Task41, this function ran each frame on the
    // render thread and made three glGetIntegerv calls, cleared errors with while(glGetError), and made
    // two eglQuerySurface calls. The upstream Amethyst swap path (ame_geo_check_and_heal) makes no GL-state queries.
    // With MobileGlues, these queries go directly to raw ANGLE and bypass the frontend state machine:
    //   1) glGetError empties the underlying error queue. MobileGlues relies on that queue to translate errors,
    //      so clearing it swallows GL errors that should reach MC (a correctness risk).
    //   2) Five cross-layer queries per frame are pure diagnostic overhead (since Task58 geometry has stayed
    //      NORMAL; multiple device logs have shown no mismatches).
    // Frequency policy: keep full diagnostics/enforcement for the first five frames, every 200th frame,
    // and every non-NORMAL state (undecided/compensating); return immediately for stable NORMAL frames.
    // Task48's guard (surface vs. drawable drift detection) continues enforcing geometry every frame.
    // Recheck viewport vs. surface on probe frames: a mismatch from rotation/resize will encounter s_mode!=1
    // first or a probe within at most 200 frames, leaving no undetected interval.
    const BOOL probe = (swapIndex <= 5) || (swapIndex % 200 == 0) || s_mode != 1;
    if (!probe) return;

    int drawFb = 0, readFb = 0, viewport[4] = {0, 0, 0, 0};
    es.getIntegerv(0x8CA9 /*GL_DRAW_FRAMEBUFFER_BINDING*/, &drawFb);
    es.getIntegerv(0x8CAA /*GL_READ_FRAMEBUFFER_BINDING*/, &readFb);
    es.getIntegerv(0x0BA2 /*GL_VIEWPORT*/, viewport);
    // Task 76: remove the while(es.getError() != 0) error-clearing loop; it empties ANGLE's underlying
    // error queue and swallows errors MobileGlues still needs to translate. getIntegerv itself does not
    // generate GL errors, and stale errors do not affect the correctness of this probe's readings.

    int surfW = 0, surfH = 0;
    if (es.querySurface != NULL && surface != EGL_NO_SURFACE) {
        EGLint sw = 0, sh = 0;
        // Task 58 root-cause fix (conclusively explains the split image and input offset): EGL_HEIGHT=0x3056,
        // EGL_WIDTH=0x3057. Since Task41, this probe read 0x3056 into surfW and 0x3057 into surfH,
        // reversing width and height. A healthy 1180x820 surface was read as "820x1180 transposed",
        // causing a false geoMismatch every frame. Task49 geo-heal then blitted a healthy landscape frame
        // into a portrait scratch surface and back, creating both the split image and input offset.
        // The compensation chain invented the problem; six rounds of fixes (Tasks 48/49/50/51/52/53/55/56/57)
        // chased this phantom. ANGLE, the Metal layer, and drawable were healthy throughout: the 1180x820
        // macro query at creation is direct evidence, corroborated by Task57's split-brain probe showing
        // the render-thread layer remained landscape. Use the official constants to prevent recurrence.
        if (es.querySurface(g_EglDisplay, surface, EGL_WIDTH, &sw) &&
            es.querySurface(g_EglDisplay, surface, EGL_HEIGHT, &sh)) {
            surfW = sw; surfH = sh;
        }
        // Task 58 one-time fingerprint: corrected readings (verify in the next device log; expected
        // surface == viewport, latch NORMAL, and no geo-heal/blit).
        static BOOL s_task58_logged = NO;
        if (!s_task58_logged && surfW > 0 && surfH > 0) {
            s_task58_logged = YES;
            NSLog(@"[GLGeo] Task58 query constants corrected: surface=%dx%d viewport=%dx%d (EGL_WIDTH=0x3057/EGL_HEIGHT=0x3056 per egl.h; legacy probe read them swapped since Task41)",
                  surfW, surfH, viewport[2], viewport[3]);
        }
    }
    if (surfW <= 0) surfW = viewport[2];
    if (surfH <= 0) surfH = viewport[3];

    // Task 49: geometry mismatch check (every frame, no readback, deterministic).
    // viewport dimensions != surface dimensions means MC's frame cannot fill the back buffer
    // (1x/2x unit mismatch or portrait/landscape transposition—the exact case in latestlog 53febda),
    // so enable geo-heal immediately. This check takes precedence over all latch states:
    // when geometry does not match, "FBO 0 has content" does not mean it is visible.
    //
    // Task 78 (FSR integration exemption): with MobileGlues and an FSR preset enabled, the launcher
    // scales the window size reported to MC to surface/fsr_scale (updateSavedResolution). MC's viewport
    // is then always smaller than the surface in **both dimensions**, as expected for the FSR1 upscale
    // path—not a geometry fault. Compensation (Task49 geo-heal / Task55 realign / Task51/52 drawable
    // pinning) would conflict with ApplyFSR's blit. The exemption deliberately requires both viewport
    // dimensions to be strictly smaller: a transposition (one dimension larger and one smaller, e.g.
    // 820x1180 vs 1180x820) does not qualify, so real geometry faults still self-heal. With FSR disabled
    // or a non-MG renderer, viewport==surface and the exemption has no effect.
    static int s_task78_fsr_link = -1;
    if (s_task78_fsr_link < 0) {
        const char *ame78_renderer = getenv("AMETHYST_RENDERER");
        NSInteger ame78_fsr = getPrefInt(@"mobileglues.fsr1_setting");
        s_task78_fsr_link = (ame78_renderer != NULL &&
                             strcmp(ame78_renderer, RENDERER_NAME_MOBILEGLUES) == 0 &&
                             ame78_fsr > 0) ? 1 : 0;
        if (s_task78_fsr_link) {
            NSLog(@"[GLGeo] Task78 FSR linkage active: renderer=MobileGlues fsr1_setting=%ld -- viewport (render) < surface is the expected upscale geometry, compensation chain exempted", (long)ame78_fsr);
        }
    }
    const BOOL geoMismatch = (viewport[2] > 0 && viewport[3] > 0 &&
                              surfW > 0 && surfH > 0 &&
                              (viewport[2] != surfW || viewport[3] != surfH)) &&
                             !(s_task78_fsr_link &&
                               viewport[2] < surfW && viewport[3] < surfH);
    if (s_task78_fsr_link && viewport[2] > 0 && viewport[2] < surfW &&
        viewport[3] > 0 && viewport[3] < surfH) {
        static BOOL s_task78_logged = NO;
        if (!s_task78_logged) {
            s_task78_logged = YES;
            NSLog(@"[GLGeo] Task78 FSR render<surface expected: viewport=%dx%d surface=%dx%d -- geo-heal/realign exempted (MG FSR1 upscale path presents the frame)",
                  viewport[2], viewport[3], surfW, surfH);
        }
    }
    g_ame53_transposed = geoMismatch ? 1 : 0;
    if (!geoMismatch) {
        // Task53: reset the cooldown on an aligned frame so the next mismatch episode can retry immediately.
        // Otherwise, an attempt skipped during cooldown can leave mode stuck at 2 (the compensation state
        // does not re-enter this branch), permanently preventing realignment from being armed again
        // (observed in logic test scenario S3).
        g_ame53_last_ms = 0;
    }
    if (geoMismatch && s_mode != 2) {
        // Task57 (close the diagnostic loop): on first mismatch detection, read render-layer geometry once
        // from the render thread (where this function runs, the same execution environment in which ANGLE
        // reads the layer). The main-thread heartbeat (SurfaceViewController updateGameStats) always reports
        // landscape 1180x820 for the same layer object, while ANGLE computes transposed 820x1180 here.
        // Logging both side by side conclusively tests the CALayer cross-thread split-brain theory
        // (622166a heartbeat 2360x1640 vs. guard reading 1640x2360; bbe6d63's zero-drift rows show the
        // render-thread drawableSize matches the transposed surface). The sublayer count also tests whether
        // ANGLE created its own sublayer; initialize's isKindOfClass:[CAMetalLayer class] check is true,
        // so it should use the layer directly and the count should be 0.
        {
            CALayer *l57 = (__bridge CALayer *)g_ame48_layer_cf;
            if (l57 != nil) {
                BOOL m57 = [l57 isKindOfClass:CAMetalLayer.class];
                CGSize d57 = m57 ? ((CAMetalLayer *)l57).drawableSize : CGSizeZero;
                NSLog(@"[GLGeo] Task57 render-thread layer read (split-brain probe): bounds=%.0fx%.0f drawable=%.0fx%.0f scale=%.2f sublayers=%lu surface=%dx%d (compare with main-thread heartbeat: bounds/drawable always 1180x820)",
                      l57.bounds.size.width, l57.bounds.size.height,
                      d57.width, d57.height, (double)l57.contentsScale,
                      (unsigned long)[l57.sublayers count], surfW, surfH);
            }
        }
        // Task55 (root-cause fix for the split image): on first geometry mismatch, attempt progressive
        // realignment (A geometry signal / B delayed recreation / C reverse-transposition journey; stop
        // on the first heal). Healing requires querySurface == layer bounds, preventing Task53 false positives.
        // On success, surface==viewport==drawable==bounds and all compensations return to no-op.
        // This branch should be unreachable with the Task57 patch (surface is frozen at the creation geometry
        // == viewport). If reached, the viewport changed (window resize); step B recreation is the only legal
        // way to change size under the frozen-surface policy, so retain this path.
        if (ame_task53_realign_surface()) {
            // Surface is aligned: reset mode and relatch next frame (matching geometry + FBO0 content
            // → NORMAL; geo-heal exits automatically through Task50's recovery branch).
            s_mode = 0;
            g_ame53_transposed = 0;
            // Refresh local surfW/surfH so the probes/hierarchy/guard below report the new surface's
            // actual state. The surface parameter is now the destroyed old handle; query the new surface
            // in currentBundle instead.
            basic_render_window_t *b53 = currentBundle;
            if (b53 != NULL && es.querySurface != NULL && b53->gl.surface != EGL_NO_SURFACE) {
                EGLint sw53 = 0, sh53 = 0;
                // Task58: corrected constants (0x3056=EGL_HEIGHT, 0x3057=EGL_WIDTH;
                // fixed consistently with the probe/verification function).
                if (es.querySurface(g_EglDisplay, b53->gl.surface, EGL_WIDTH, &sw53) &&
                    es.querySurface(g_EglDisplay, b53->gl.surface, EGL_HEIGHT, &sh53)) {
                    surfW = sw53;
                    surfH = sh53;
                }
            }
            NSLog(@"[RenderDiag] Task55 realign applied: viewport=%dx%d surface=%dx%d (mode reset; expect NORMAL latch next frame)",
                  viewport[2], viewport[3], surfW, surfH);
        } else {
        NSLog(@"[RenderDiag] Task49 geo mismatch ENGAGED: viewport=%dx%d surface=%dx%d (was mode=%d) -- frame covers only %.0f%% of backbuffer",
              viewport[2], viewport[3], surfW, surfH, s_mode,
              100.0 * (double)viewport[2] * (double)viewport[3] / ((double)surfW * (double)surfH));
        s_mode = 2;
        // Task51 Fix F' (semantics reversed by Task55): during persistent transposition, set drawableSize
        // once to the **landscape bounds value**, matching the Task52 guard's heal-align direction.
        // The old behavior (pinning to the transposed surface size for "present consistency") was disproved
        // by log a901050: together with the guard, it pinned the transposition in the wrong direction and
        // blocked ANGLE from self-healing based on drawableSize. Under the old behavior, drawableSize
        // oscillation (updateSavedResolution writing bounds) also caused the user's split image.
        // Keep one writer and one direction (landscape signal) during mismatch; after healing, this becomes
        // a same-value no-op. Dispatch asynchronously to the main thread (e6886e2 proved main-thread writes
        // work; 622166a disproved render-thread writes).
        // s_mode != 2 ensures this runs at most once per mismatch episode; the guard takes over afterward.
        void *ame51_layer_ref = g_ame48_layer_cf;
        if (ame51_layer_ref != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    CALayer *l = (__bridge CALayer *)ame51_layer_ref;
                    if ([l isKindOfClass:CAMetalLayer.class]) {
                        CAMetalLayer *ml = (CAMetalLayer *)l;
                        CGSize old = ml.drawableSize;
                        CGFloat bw = MAX(1.0, round(l.bounds.size.width));
                        CGFloat bh = MAX(1.0, round(l.bounds.size.height));
                        // Task 60: use pixel units (bounds × contentsScale), matching the surface/drawable
                        // pipeline. The old 1x point-based write reset a 2x drawableSize to 1x (blur regression).
                        CGFloat sc51 = l.contentsScale;
                        if (sc51 <= 0.0) sc51 = 1.0;
                        CGSize tgt51 = CGSizeMake(round(bw * sc51), round(bh * sc51));
                        if (fabs(old.width - tgt51.width) > 0.5 || fabs(old.height - tgt51.height) > 0.5) {
                            ml.drawableSize = tgt51;
                            NSLog(@"[GLGeo] Task51 heal-align (main thread): drawableSize %.0fx%.0f -> %.0fx%.0f == bounds x scale (landscape signal, same direction as Task52 guard heal)",
                                  old.width, old.height, tgt51.width, tgt51.height);
                        } else {
                            NSLog(@"[GLGeo] Task51 heal-align: already at bounds x scale %.0fx%.0f (landscape signal in place)", tgt51.width, tgt51.height);
                        }
                    }
                } @catch (NSException *e) {
                    NSLog(@"[GLGeo] Task51 heal-align exception: %@", e);
                }
            });
        }
        }  // Task53 else: realignment unavailable/failed → use existing compensation path (behavior unchanged).
    }

    if (probe) {
        // Task 75: readback probe retired (the entire block was removed). It used to run 8x8 glReadPixels
        // at the center of the current FBO, the center of FBO 0, and a far corner of FBO 0 (UBYTE with
        // FLOAT fallback), then count unique values to decide whether content was present.
        // Log 4770b53: after 46 successful probes (swap#1..#8200 all err=0x0), the 47th at swap#8400
        // (game pause screen, reduced rate from dynamic_fps) triggered angle::CopyBGRA8ToRGBA8+0x114
        // SIGBUS during readback. Stack: GL_ReadPixels ← ame_task41_swap_forensics ← gl_swap_buffers.
        // When drawFb==0, the readback target is the CAMetalLayer drawable about to be presented by
        // eglSwapBuffers. ANGLE Metal's staging blit races with the drawable lifecycle (longer intervals
        // and a changed reclamation cycle during pauses exposed the race). Intermittent iOS glReadPixels
        // crashes are known in the community; the upstream Amethyst swap path never reads back.
        // Diagnostics had no remaining value (geometry checks cover this since Task58), while the risk
        // was a full-device crash, so readback was retired and the swap path now performs none.
        NSLog(@"[RenderDiag] swap#%lu (Task75 geo-probe): drawFb=%d readFb=%d viewport=%d,%d %dx%d surface=%dx%d mode=%d (readback retired -- CopyBGRA8ToRGBA8 SIGBUS @4770b53)",
              swapIndex, drawFb, readFb, viewport[0], viewport[1], viewport[2], viewport[3],
              surfW, surfH, s_mode);

        // Task51 diagnostic: dump full presentation-layer visibility state (first frame + every 500 frames, on main thread).
        // Motivation: four consecutive log rounds (48/49/50/51 baselines) showed "all GL green + presentation succeeded,"
        // yet the user still saw a black screen. The fault was likely in UIKit presentation (layer absent from the tree,
        // occluded, hidden, rotated by a transform, or its window not visible). This dump logs all key visibility state
        // at once to provide a conclusive answer in the next log, whether the problem is present or not.
        if (swapIndex == 1 || (swapIndex > 0 && swapIndex % 500 == 0)) {
            void *ame51_h_layer = g_ame48_layer_cf;
            int h_sw = surfW, h_sh = surfH;
            unsigned long h_idx = swapIndex;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    CALayer *l = (__bridge CALayer *)ame51_h_layer;
                    if (l == nil) {
                        NSLog(@"[GLGeo] Task51 hierarchy #%lu: render layer is NIL", h_idx);
                        return;
                    }
                    NSMutableString *chain = [NSMutableString stringWithCapacity:256];
                    CALayer *cur = l;
                    int depth = 0;
                    while (cur != nil && depth < 10) {
                        [chain appendFormat:@" -> [%@ %dx%d pos=(%d,%d) hid=%d op=%.2f%@]",
                            NSStringFromClass(cur.class),
                            (int)round(cur.bounds.size.width), (int)round(cur.bounds.size.height),
                            (int)round(cur.position.x), (int)round(cur.position.y),
                            (int)cur.hidden, (double)cur.opacity,
                            CATransform3DIsIdentity(cur.transform) ? @"" : @" ROT"];
                        cur = (CALayer *)cur.superlayer;
                        depth++;
                    }
                    NSString *dw = @"n/a";
                    if ([l isKindOfClass:CAMetalLayer.class]) {
                        CAMetalLayer *ml = (CAMetalLayer *)l;
                        dw = [NSString stringWithFormat:@"%.0fx%.0f",
                              ml.drawableSize.width, ml.drawableSize.height];
                    }
                    BOOL inTree = (l.superlayer != nil);
                    NSLog(@"[GLGeo] Task51 hierarchy #%lu: layer=%p drawable=%@ scale=%.2f surface=%dx%d inTree=%d chain=%@",
                          h_idx, ame51_h_layer, dw, (double)l.contentsScale,
                          h_sw, h_sh, (int)inTree, chain);
                } @catch (NSException *e) {
                    NSLog(@"[GLGeo] Task51 hierarchy exception: %@", e);
                }
            });
        }

        // ====================================================================
        // Task 52: presentation-layer visibility guard (every 50 frames; asynchronous on the main thread, no render blocking).
        //
        // Root cause (proven by hierarchy dump in line 8967 of log b805f51): CAMetalLayer had hid=1.
        // The vendor's libSDL3.dylib contains an embedding patch from the Zalith code lineage that, on each
        // real SDL_CreateWindow / SDL_Metal_CreateView, looks up a class name and calls
        // [GameSurfaceView setHidden:YES] (disassembly at @0x152e6c). All GL frames were presented into
        // this hidden layer, producing healthy rendering but a black screen.
        // This guard continuously enforces three invariants (embedding step 3.5 handles the initial frame;
        // this catches MetalCreate, subsequent embedding reruns, and any external code hiding the view):
        //   1) Render layer is visible; 2) SDL touch view has higher z-order than the image layer;
        //   3) drawableSize == surface size (consistent presentation; replaces one-shot Fix F' and
        //      counteracts periodic writes from host updateSavedResolution).
        // ====================================================================
        if (swapIndex == 1 || (swapIndex > 0 && swapIndex % 50 == 0)) {
            int g52_sw = surfW, g52_sh = surfH;
            unsigned long g52_idx = swapIndex;
            void *g52_layer = g_ame48_layer_cf;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    // 1) Unhide the render layer (read/write on the main thread, the authoritative source).
                    UIView *g52_gs = [SurfaceViewController surface];
                    if (g52_gs != nil && (g52_gs.hidden || g52_gs.layer.hidden)) {
                        g52_gs.hidden = NO;
                        g52_gs.layer.hidden = NO;
                        NSLog(@"[GLGeo] Task52 guard #%lu: render layer was HIDDEN by external code -- UN-HIDDEN (surface=%dx%d)",
                              g52_idx, g52_sw, g52_sh);
                    }
                    // 2) Z-order: the SDL touch view must be above the image layer (otherwise the image layer intercepts touches).
                    UIView *g52_sdl = (__bridge UIView *)ame_hook_getEmbeddedSDLView();
                    if (g52_gs != nil && g52_sdl != nil && g52_gs.superview != nil &&
                        g52_sdl.superview == g52_gs.superview) {
                        NSArray *g52_subs = g52_gs.superview.subviews;
                        NSUInteger g52_gi = [g52_subs indexOfObjectIdenticalTo:g52_gs];
                        NSUInteger g52_si = [g52_subs indexOfObjectIdenticalTo:g52_sdl];
                        if (g52_gi != NSNotFound && g52_si != NSNotFound && g52_gi > g52_si) {
                            [g52_gs.superview insertSubview:g52_gs belowSubview:g52_sdl];
                            NSLog(@"[GLGeo] Task52 guard #%lu: z-order re-pinned (GameSurfaceView below SDL touch view)",
                                  g52_idx);
                        }
                    }
                    // 3) Enforce presentation geometry (semantics adapt per Task55):
                    //    - If mismatch remains unfixed (transposition stuck), write the **landscape bounds**
                    //      value to keep signaling ANGLE to return to landscape. Log a901050 proves that writing
                    //      the transposed surface value (820x1180) pins the wrong orientation and prevents ANGLE
                    //      from self-healing based on drawableSize. Log 622166a proves ANGLE can follow layer
                    //      geometry; Task50 proves main-thread writes are the only reliable channel. If ANGLE
                    //      does not follow, the squeeze blit and CA stretch are inverse transformations that
                    //      restore the aspect ratio, better than persistent squeezing and split-image oscillation.
                    //    - If healed/no mismatch, write the surface value (maintain presentation consistency;
                    //      after healing both values match, so this is a no-op).
                    CALayer *g52_l = (__bridge CALayer *)g52_layer;
                    if (g52_l != nil && [g52_l isKindOfClass:CAMetalLayer.class] &&
                        g52_sw > 0 && g52_sh > 0) {
                        CAMetalLayer *g52_ml = (CAMetalLayer *)g52_l;
                        CGSize g52_old = g52_ml.drawableSize;
                        BOOL g52_heal = ame_gl_surface_transposed();
                        // Task60: use pixel units (bounds × contentsScale) in the heal branch too,
                        // matching the surface pixel units in the present branch and avoiding
                        // resetting a 2x drawableSize to 1x.
                        CGFloat g52_sc = g52_l.contentsScale;
                        if (g52_sc <= 0.0) g52_sc = 1.0;
                        CGSize g52_target = g52_heal
                            ? CGSizeMake(round(MAX(1.0, round(g52_l.bounds.size.width)) * g52_sc),
                                         round(MAX(1.0, round(g52_l.bounds.size.height)) * g52_sc))
                            : CGSizeMake(g52_sw, g52_sh);
                        if (fabs(g52_old.width - g52_target.width) > 0.5 ||
                            fabs(g52_old.height - g52_target.height) > 0.5) {
                            g52_ml.drawableSize = g52_target;
                            NSLog(@"[GLGeo] Task52 guard #%lu: %@ drawable %.0fx%.0f -> %.0fx%.0f (%@)",
                                  g52_idx, g52_heal ? @"heal-align" : @"present-align",
                                  g52_old.width, g52_old.height,
                                  g52_target.width, g52_target.height,
                                  g52_heal ? @"transposed-uncured: feeding landscape bounds signal"
                                           : @"== surface, self-consistent present");
                        }
                    }
                } @catch (NSException *e) {
                    NSLog(@"[GLGeo] Task52 guard exception: %@", e);
                }
            });
        }

        // Latch check (rewritten in Task75: geometry only, no readback).
        // The old version relied on reading FBO 0 content (fbo0Content/fbo0Flat); readback was retired
        // in Task75 as a SIGBUS crash source (see the retirement note above). New criterion: aligned
        // geometry (viewport==surface) is both necessary and sufficient to show the frame can fill the
        // back buffer. Task58 concluded that sessions with surface==viewport are 100% healthy, confirmed
        // by 43 probes in this log.
        // Geometry-mismatch detection/healing/fallback (geoMismatch branch: Task57 probe → Task55 realign
        // → Task51/52 pinning) is unchanged and uses no readback. The only way into mode=2 is failed
        // realignment in the geoMismatch branch; exit preserves Task50 semantics (leave geo-heal when
        // geometry realigns, with no content evidence required).
        if (s_mode == 0 && !geoMismatch) {
            s_mode = 1;
            NSLog(@"[RenderDiag] Task41 latch: NORMAL present (geometry aligned, readback retired by Task75)");
        } else if (s_mode == 2 && !geoMismatch) {
            // Preserve Task50 semantics (criterion changed to geometry): once geometry realigns, exit geo-heal
            // and stop scratch transfers every frame. The old version never left mode=2 after entering it,
            // so it kept blitting after geometry was fixed, wasting bandwidth and preventing the state machine
            // from returning to the normal presentation path.
            s_mode = 1;
            NSLog(@"[RenderDiag] Task50 heal disengaged: geometry aligned (viewport==surface) -- back to normal present");
        }
    }

    if (s_mode == 2) {
        // Task 49: two-pass scratch-FBO blit (source = MC viewport region, scaled to fill FBO 0).
        ame_task49_geo_heal_blit(es, drawFb, readFb, viewport[2], viewport[3], surfW, surfH);
    }
}

// ============================================================================
// Task 48: presentation geometry guard (root-cause fix for black screens on the GL path).
//
// Device evidence (latestlog 1518ce1, iPad Air M4 / iPadOS 26.6):
//   - The render pipeline was fully healthy: all 1,032 swaps succeeded, fps=57, swapFail=0, no GL errors,
//     MC 26.3 reached the title screen (atlases/audio loaded), and the FBO content probe reported uniq=44–49.
//   - [RenderDiag] EGL surface was 2360x1640 at creation (the layer was correct, confirmed by eglQuerySurface),
//     but was 1640x2360 (portrait-transposed) by swap and remained so for all 1,032 frames.
//   - CAMetalLayer heartbeat reported drawable=2360x1640 (correct landscape), bounds=1180x820.
//   - MC glViewport=1180x820 (SDL3-on-iOS reports window dimensions in "points," not "pixels";
//     MC requested 2360x1640 but was clamped to 1180x820, so MC actually rendered at 1x).
// These dimensions disagreed, so the presented backbuffer did not match the drawable and the screen was black.
//
// Fix strategy (self-heal without assuming which component transposed the surface):
//   1) Pin on creation: for MobileGlues, set drawableSize to layer.bounds (points) before
//      eglCreateWindowSurface—the actual size MC will render (1180x820). ANGLE reads the layer
//      at creation (confirmed by this log), so surface == MC viewport == drawable and the image is full-screen at 1:1.
//   2) Swap guard: before each eglSwapBuffers, compare the actual surface size with layer drawableSize.
//      If they differ, immediately pin drawableSize to the surface size (drawable must match the backbuffer
//      about to be presented; this is a hard requirement for displaying the frame, and converges regardless
//      of whether ANGLE/MG/rotation changed either side).
//   3) Escalate to recreation: if the surface differs from its creation-time expected size for 30+ consecutive
//      frames, rate-limit (five seconds) an EGL window-surface recreation (pin layer first, create, rebind
//      with MG frontend MakeCurrent, destroy old surface). Recreation is the only reliable way to reset
//      ANGLE's internal surface dimensions. Allow at most three attempts to avoid an infinite loop.
//
// Thread safety: the guard runs on the MC render thread (context current) and touches only CALayer/
// CAMetalLayer APIs (Apple explicitly supports driving CAMetalLayer from a render thread), not UIKit.
// Cache the layer pointer with CFBridgingRetain at creation so the render thread does not access UIView.
// The Vulkan path is unaffected (this file is only the GL bridge).
// ============================================================================
// (Declaration moved to the Task49 static section above; see g_ame48_layer_cf.)
static int   g_ame48_expected_w = 0;         // Expected surface width (creation-time pinned value).
static int   g_ame48_expected_h = 0;         // Expected surface height.
static long  g_ame48_drift_swaps = 0;        // Consecutive frames with surface != drawable (diagnostics only).
static int   g_ame48_recreates = 0;          // Retained for history (no recreation since Task50).
static uint64_t g_ame48_last_recreate_ms = 0;

/// Called at creation: cache the presentation layer, record expected dimensions, and reset guard state.
static void ame48_record_creation(CALayer *layer, EGLDisplay dpy, EGLSurface surface) {
    if (g_ame48_layer_cf != NULL) {
        CFRelease(g_ame48_layer_cf);
        g_ame48_layer_cf = NULL;
    }
    if (layer != nil) {
        g_ame48_layer_cf = (void *)CFBridgingRetain(layer);
    }
    g_ame48_drift_swaps = 0;
    g_ame48_recreates = 0;
    g_ame48_last_recreate_ms = 0;
    g_ame48_expected_w = 0;
    g_ame48_expected_h = 0;
    // Expected value = actual surface dimensions reported by ANGLE after creation (the MC render dimensions
    // once creation-time pinning takes effect). Leave it at 0 if querying fails (disable drift detection,
    // but per-frame drawable == surface pinning remains active throughout).
    ame_es_t es = ame_es();
    if (es.querySurface != NULL && surface != EGL_NO_SURFACE) {
        EGLint sw = 0, sh = 0;
        if (es.querySurface(dpy, surface, EGL_WIDTH, &sw) &&
            es.querySurface(dpy, surface, EGL_HEIGHT, &sh) && sw > 0 && sh > 0) {
            g_ame48_expected_w = sw;
            g_ame48_expected_h = sh;
        }
    }
    NSLog(@"[GLGeo] Task48 creation recorded: layer=%p expectedSurface=%dx%d",
          g_ame48_layer_cf, g_ame48_expected_w, g_ame48_expected_h);
}

/// Swap guard: called every frame by gl_swap_buffers (render thread, context current).
/// Task50 downgraded this function to **diagnostics only** (read-only + logging, no writes).
///
/// Device log 622166a showed all three self-healing actions in the old guard were ineffective and harmful:
///   1. Cross-thread drawableSize writes (render-thread vs. main-thread CA committed-tree state diverged:
///      heartbeat read drawable=2360x1640 while the guard read 1640x2360; there were no "Task48 pin"
///      entries in the entire log, proving per-frame pinning never took effect).
///   2. A second eglCreateWindowSurface on the same layer always returned EGL_BAD_ALLOC 0x3003.
///   3. Pinning conflicted with updateSavedResolution (which writes 2x from the main thread during rotation).
/// Since Task60, geometry consistency is guaranteed by a single source of truth in native-scale pixels
/// (align at gl_init_context creation + GL branch of updateSavedResolution follows bounds × scale).
/// This function now only records drift (surface vs. drawable, both in pixels).
/// ANGLE naturally resizes with the layer (the surface transposition in 622166a proves this);
/// Task49 geo-heal blit handles transient mismatch and exits when geometry realigns (two-way latch).
static void ame48_swap_geometry_guard(basic_render_window_t *bundle) {
    if (bundle == NULL || bundle->gl.surface == EGL_NO_SURFACE) return;
    CALayer *layer = (__bridge CALayer *)g_ame48_layer_cf;
    if (layer == nil || ![layer isKindOfClass:CAMetalLayer.class]) return;
    ame_es_t es = ame_es();
    if (es.querySurface == NULL) return;

    EGLint sw = 0, sh = 0;
    if (!es.querySurface(g_EglDisplay, bundle->gl.surface, EGL_WIDTH, &sw) ||
        !es.querySurface(g_EglDisplay, bundle->gl.surface, EGL_HEIGHT, &sh)) {
        return;  // Do not intervene if the query fails (EGL error).
    }
    if (sw <= 0 || sh <= 0) return;

    CAMetalLayer *ml = (CAMetalLayer *)layer;
    CGSize d = ml.drawableSize;
    int dw = (int)round(d.width), dh = (int)round(d.height);

    if (dw != sw || dh != sh) {
        g_ame48_drift_swaps++;
        if (g_ame48_drift_swaps == 1 || g_ame48_drift_swaps % 200 == 0) {
            NSLog(@"[GLGeo] Task50 drift (info only): surface=%dx%d drawable=%dx%d bounds=%.0fx%.0f (consecutive=%ld) -- ANGLE resizes with layer; transient mismatch covered by geo-heal blit",
                  (int)sw, (int)sh, dw, dh,
                  layer.bounds.size.width, layer.bounds.size.height,
                  g_ame48_drift_swaps);
        }
    } else {
        g_ame48_drift_swaps = 0;
    }
}

static void* load_egl_symbol(void *dl_handle, const char *symbol) {
    dlerror();
    void *addr = dlsym(dl_handle, symbol);
    const char *error = dlerror();
    if (!addr || error) {
        NSLog(@"EGLBridge: failed to resolve %s: %s", symbol, error ?: "symbol not found");
    }
    return addr;
}

// ============================================================================
// Task 36: route EGL calls through the MobileGlues frontend (fix black screens on the GL path).
//
// Device test (latestlog e28e4c3 + libmobileglues.dylib): MC 26.3 accepted the OpenGL
// backend (passed c71dcfa's glGetError consistency check), and the render loop ran at full speed
// (fps=57–58, 485 successful eglSwapBuffers calls, no failures or GL errors), but the screen was black
// and only audio played. MobileGlues' own log provided three conclusive clues:
//
//   [MG] SYMBOL THEFT: ... (flat namespace resolved gl* to another image — warning only).
//   [MG] depth filter scan: context untracked (EGL bypassed this layer)...
//   (depth query returned -1; all per-context state fell back to the context-0 instance).
//
// Root cause: this bridge previously resolved MobileGlues EGL symbols from libtinygl4angle.dylib
// (raw ANGLE), bypassing MobileGlues 2.0.16+'s frontend EGL for all context/MakeCurrent calls.
// In MobileGlues egl/context.cpp, an MGContext virtual-context record can only be created by frontend
// eglCreateContext and bound by frontend eglMakeCurrent (g_current_ctx + mg_framebuffer_bind_context(id)
// + gl_state redirection). When bypassed, mg_context_make_current takes the "handle is not tracked,
// leaving no current record" branch: g_current_ctx remains NULL, FBO translation/state management
// degrade to process-wide singletons, MC 26.3 RenderPearl's composite never reaches the default
// framebuffer, and eglSwapBuffers presents a black frame that was never drawn to.
//
// Fix: route lifecycle functions (eglBindAPI/eglCreateContext/eglDestroyContext/eglMakeCurrent/
// eglSwapBuffers/eglSwapInterval) through libmobileglues.dylib's frontend EGL. Keep infrastructure
// functions (display/config/surface, etc.—already pure pass-throughs in the frontend) on raw ANGLE.
// Both paths point to the same ANGLE instance (tinygl4angle is only an alias shim for libEGL/libGLESv2).
//
// Ordering constraint: the frontend's internal LOAD_EGL static pointers initialize only on first call,
// while its backend handle `egl` is bound only inside mg_init_gles() (on Apple). mg_init_gles in turn
// needs a current context for correct capability detection. Therefore, before the first frontend call,
// create a 16x16 pbuffer and temporary ES context using raw ANGLE → eglMakeCurrent → call mg_init_gles()
// (a real context is current, so capability detection works) → release and destroy the temporary resources
// → then switch lifecycle pointers to the frontend. If bootstrap fails, retain the old all-raw-ANGLE
// behavior and introduce no additional risk.
// ============================================================================
static void *ame_mg_handle = NULL;        // libmobileglues.dylib (frontend EGL/GL).
static void *ame_mg_angle_handle = NULL;  // libtinygl4angle.dylib (raw ANGLE shim).
static BOOL  ame_mgFrontendActive = NO;   // Lifecycle functions have switched to the frontend.
static BOOL  ame_mgBootstrapTried = NO;   // Bootstrap is attempted only once.

typedef void (*ame_mg_init_gles_t)(void);
static ame_mg_init_gles_t ame_mg_init_gles = NULL;

// Raw ANGLE pointers used only for bootstrap (not in the handle table; bootstrap + diagnostics only).
typedef EGLSurface (*ame_fn_create_pbuffer)(EGLDisplay, EGLConfig, const EGLint *);
typedef EGLBoolean (*ame_fn_egl_query_surface)(EGLDisplay, EGLSurface, EGLint, EGLint *);
static ame_fn_create_pbuffer       ame_raw_create_pbuffer = NULL;
static ame_fn_egl_query_surface    ame_raw_query_surface = NULL;
static PFNEGLCREATECONTEXTPROC     ame_raw_create_context = NULL;
static PFNEGLMAKECURRENTPROC       ame_raw_make_current = NULL;
static PFNEGLDESTROYCONTEXTPROC    ame_raw_destroy_context = NULL;
static PFNEGLDESTROYSURFACEPROC    ame_raw_destroy_surface = NULL;
static PFNEGLSWAPINTERVALPROC      ame_raw_swap_interval = NULL;   // Task 76 redundant safeguard.

// ============================================================================
// [sfpew-egl-route] EGL symbol-resolution route when SFPEW is layered (A/B selectable).
//
// Symbol-table facts (verified across the entire vendored SimpleFPEWrapper tree):
//   SFPEW exports only seven EGL symbols: eglGetProcAddress / eglCreateContext /
//   eglDestroyContext / eglMakeCurrent / eglSwapBuffers /
//   eglSwapBuffersWithDamageEXT / eglSwapBuffersWithDamageKHR.
//   It does not export eglGetDisplay / eglInitialize / eglChooseConfig / eglBindAPI /
//   eglCreateWindowSurface.
//
// Therefore, the host has three possible integration models, only one of which works:
//   (a) dlsym(SFPEW) for all EGL functions → all infrastructure pointers are NULL; crashes (before 19ef078d).
//   (b) dlsym(the real backend) for all EGL functions → SFPEW lifecycle functions are never called;
//       sfpewRegisterContextDispatch / sfpewNoteDispatchCurrentContext never register anything,
//       leaving the dispatch registry empty → "No context is current" (19ef078d, currently the default).
//   (c) Resolve all EGL functions through SFPEW's eglGetProcAddress—the model tested on Android/FCL.
//       lookup.cpp routes automatically: create/destroy/makeCurrent/swap return SFPEW wrappers,
//       while other names forward to backend g_eglFuncs.eglGetProcAddress.
//       Three FCL device logs (SFPEW+MG, SFPEW+MobileGL 1.7.10, and 1.12.2) used
//       POJAVEXEC_EGL=libSimpleFPEWrapper.so, exactly this route; both combinations worked.
//
// (c) requires SFPEW to successfully dlopen its backend (SFPEW_EGL, already set by JavaLauncher).
// Disabled by default (preserves current behavior); set AMETHYST_SFPEW_EGL_ROUTE=1 to enable without rebuilding.
// ============================================================================
static BOOL ame_sfpew_egl_route_active = NO;

// Task 179: enabled by default.
//
// Root cause (comment in SFPEW lookup.cpp:75-79, original text):
//   "the wrapper has to drain its pending batch before the frame is presented,
//    or geometry drawn late in the frame is submitted into the next one and
//    cleared away."
// In other words, eglSwapBuffers must go through the SFPEW wrapper, which drains queued geometry
// before presentation. Model (b) (dlsym all EGL functions from the real backend) bypassed it, so
// SFPEW's pending batch was never drained: each frame's geometry moved to the next frame and was then
// cleared. This caused the white loading screen with MobileGL-gles + SFPEW and the fully black screen
// with ANGLE/LTW + SFPEW.
//
// Three FCL device logs used POJAVEXEC_EGL=libSimpleFPEWrapper.so, making SFPEW itself the EGL
// entry point, equivalent to model (c): lifecycle calls (create/destroy/makeCurrent/swap) use
// SFPEW wrappers, while infrastructure calls are forwarded by SFPEW to the backend (lookup.cpp:1048-1055).
//
// Keep an opt-out: AMETHYST_SFPEW_EGL_ROUTE=0 returns to model (b). Resolution failure also falls back.
static BOOL ameSFPEWEglRouteWanted(void) {
    const char *v = getenv("AMETHYST_SFPEW_EGL_ROUTE");
    if (v == NULL) return YES;                    // Enabled by default.
    return !(strcmp(v, "0") == 0);
}

static BOOL ameSFPEWResolveEGL(void) {
    void *sfpew = dlopen("@rpath/libSimpleFPEWrapper.dylib", RTLD_NOW | RTLD_GLOBAL);
    if (!sfpew) sfpew = dlopen("libSimpleFPEWrapper.dylib", RTLD_NOW | RTLD_GLOBAL);
    if (!sfpew) {
        NSLog(@"[SFPEW-EGL] dlopen libSimpleFPEWrapper.dylib failed: %s", dlerror() ?: "unknown");
        return NO;
    }
    void *raw = dlsym(sfpew, "eglGetProcAddress");
    if (!raw) {
        NSLog(@"[SFPEW-EGL] eglGetProcAddress not exported by SFPEW");
        return NO;
    }
    void *(*gpa)(const char *) = NULL;
    // void* → function pointer: use a union to avoid ISO C diagnostics for mixing object and function pointers.
    union { void *obj; void *(*fn)(const char *); } cast;
    cast.obj = raw;
    gpa = cast.fn;

#define AME_SFPEW_EGL(field, name)                                                  \
    do {                                                                            \
        void *fn = gpa(name);                                                       \
        if (fn != NULL) { handle.field = (__typeof__(handle.field))fn; }            \
        else NSLog(@"[SFPEW-EGL] " name " unresolved via eglGetProcAddress");        \
    } while (0)

    AME_SFPEW_EGL(eglBindAPI,             "eglBindAPI");
    AME_SFPEW_EGL(eglChooseConfig,        "eglChooseConfig");
    AME_SFPEW_EGL(eglCreateContext,       "eglCreateContext");
    AME_SFPEW_EGL(eglCreateWindowSurface, "eglCreateWindowSurface");
    AME_SFPEW_EGL(eglDestroyContext,      "eglDestroyContext");
    AME_SFPEW_EGL(eglDestroySurface,      "eglDestroySurface");
    AME_SFPEW_EGL(eglGetConfigAttrib,     "eglGetConfigAttrib");
    AME_SFPEW_EGL(eglGetCurrentContext,   "eglGetCurrentContext");
    AME_SFPEW_EGL(eglGetCurrentSurface,   "eglGetCurrentSurface");
    AME_SFPEW_EGL(eglGetDisplay,          "eglGetDisplay");
    AME_SFPEW_EGL(eglGetError,            "eglGetError");
    AME_SFPEW_EGL(eglGetPlatformDisplay,  "eglGetPlatformDisplay");
    AME_SFPEW_EGL(eglInitialize,          "eglInitialize");
    AME_SFPEW_EGL(eglMakeCurrent,         "eglMakeCurrent");
    AME_SFPEW_EGL(eglReleaseThread,       "eglReleaseThread");
    AME_SFPEW_EGL(eglSwapBuffers,         "eglSwapBuffers");
    AME_SFPEW_EGL(eglSwapInterval,        "eglSwapInterval");
    AME_SFPEW_EGL(eglTerminate,           "eglTerminate");
#undef AME_SFPEW_EGL

    BOOL ok = handle.eglBindAPI && handle.eglChooseConfig && handle.eglCreateContext &&
        handle.eglCreateWindowSurface && handle.eglDestroyContext && handle.eglDestroySurface &&
        handle.eglGetConfigAttrib && handle.eglGetDisplay && handle.eglGetError &&
        handle.eglInitialize && handle.eglMakeCurrent && handle.eglSwapBuffers &&
        handle.eglReleaseThread && handle.eglSwapInterval && handle.eglTerminate;
    NSLog(@"[SFPEW-EGL] resolve %@ (createCtx=%p, makeCurrent=%p, getDisplay=%p)",
          ok ? @"OK" : @"INCOMPLETE",
          (void *)(uintptr_t)handle.eglCreateContext,
          (void *)(uintptr_t)handle.eglMakeCurrent,
          (void *)(uintptr_t)handle.eglGetDisplay);
    return ok;
}

static bool dlsym_EGL() {
    // EGL symbol sources:
    //   - Mithril / MobileGL: these provide a complete EGL implementation; resolve from their own dylib.
    //     Reusing ANGLE EGL would create an ANGLE Metal context instead of the renderer's own surface,
    //     and eglChooseConfig may return zero configurations for their requested attributes, triggering
    //     assert(bundle->config) in gl_init_context.
    //   - MobileGlues: route lifecycle functions through its frontend EGL (Task36; see the detailed note above);
    //     resolve remaining infrastructure functions from ANGLE (the frontend passes these through, and
    //     must not trigger its one-time internal LOAD_EGL initialization before mg_init_gles completes bootstrap).
    //   - Other renderers (gl4es / ANGLE / LTW): resolve everything from ANGLE.
    const char *renderer = getenv("AMETHYST_RENDERER");
    // In SFPEW overlay mode, AMETHYST_RENDERER is libSimpleFPEWrapper.dylib, but EGL infrastructure
    // must come from the real backend (matching Android: POJAVEXEC_EGL stays unchanged; only renderLibrary changes).
    // The real backend name is in AMETHYST_SFPEW_BACKEND (set in JavaLauncher.m):
    //   - MobileGlues: same as standalone use; EGL goes through ANGLE.
    //   - MobileGL(-gles): has its own EGL; resolve from libMobileGL.dylib.
    const char *eglRenderer = renderer;
    if (isSFPEWRenderer(renderer)) {
        const char *sfpewBackend = getenv("AMETHYST_SFPEW_BACKEND");
        if (sfpewBackend != NULL && sfpewBackend[0] != '\0') eglRenderer = sfpewBackend;
    }
    const char *eglLibrary = isSelfEglRenderer(eglRenderer) ? eglRenderer : RENDERER_NAME_MTL_ANGLE;
    NSString *eglPath = [NSString stringWithFormat:@"@rpath/%s", eglLibrary ?: ""];
    void* dl_handle = dlopen(eglPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (!dl_handle) {
        NSLog(@"EGLBridge: failed to load %@ for renderer %s: %s",
            eglPath, renderer ?: "<unset>", dlerror() ?: "unknown dlopen error");
        return false;
    }

    // Task36: prepare the MobileGlues frontend EGL (does not change behavior; only records handles/symbols;
    // pointers actually switch after ame_mgBootstrap succeeds).
    // Under SFPEW overlay, AMETHYST_RENDERER is libSimpleFPEWrapper.dylib, so test the real backend
    // (eglRenderer) here. Otherwise the frontend image will not load → ame_mg_handle remains NULL →
    // bootstrap is skipped → MobileGlues' LOAD_EGL static pointers are permanently initialized to NULL
    // while backend handle `egl` is still NULL (static locals initialize only once and later mg_init_gles
    // cannot recover) → eglCreateContext/eglMakeCurrent fail → no current context.
    if (eglRenderer && strcmp(eglRenderer, RENDERER_NAME_MOBILEGLUES) == 0 &&
        !isSelfEglRenderer(eglRenderer)) {
        ame_mg_angle_handle = dl_handle;
        void *mg = dlopen("@rpath/" RENDERER_NAME_MOBILEGLUES, RTLD_NOW | RTLD_LOCAL);
        if (!mg) {
            mg = dlopen(RENDERER_NAME_MOBILEGLUES, RTLD_NOW | RTLD_LOCAL);
        }
        if (mg) {
            ame_mg_handle = mg;
            ame_mg_init_gles = (ame_mg_init_gles_t)dlsym(mg, "mg_init_gles");
            NSLog(@"[MG-Bridge] MobileGlues frontend image loaded (%p, mg_init_gles=%p); "
                  @"lifecycle EGL will route through it after bootstrap",
                  mg, (void *)ame_mg_init_gles);
        } else {
            NSLog(@"[MG-Bridge] failed to load " RENDERER_NAME_MOBILEGLUES
                  @" (%s) -- EGL stays on raw ANGLE (legacy behavior)",
                  dlerror() ?: "unknown");
        }
        // Raw pointers for bootstrap and diagnostics (always from the ANGLE shim).
        ame_raw_create_pbuffer   = (ame_fn_create_pbuffer)load_egl_symbol(dl_handle, "eglCreatePbufferSurface");
        ame_raw_query_surface    = (ame_fn_egl_query_surface)load_egl_symbol(dl_handle, "eglQuerySurface");
        ame_raw_create_context   = (PFNEGLCREATECONTEXTPROC)load_egl_symbol(dl_handle, "eglCreateContext");
        ame_raw_make_current     = (PFNEGLMAKECURRENTPROC)load_egl_symbol(dl_handle, "eglMakeCurrent");
        ame_raw_destroy_context  = (PFNEGLDESTROYCONTEXTPROC)load_egl_symbol(dl_handle, "eglDestroyContext");
        ame_raw_destroy_surface  = (PFNEGLDESTROYSURFACEPROC)load_egl_symbol(dl_handle, "eglDestroySurface");
        // Task76: raw eglSwapInterval for a redundant POJAV_DISABLE_VSYNC call.
        // After bootstrap, handle.eglSwapInterval points to the MobileGlues frontend (which should
        // pass through to the backend), but in the MG session in bef0f08, 33 heartbeat logs never
        // exceeded 60 fps with max.fps=260 unlocked, suggesting ANGLE Metal did not accept VSync changes.
        // A raw call bypasses the frontend translation chain. Set it through both routes (idempotently)
        // and log both return values on-device for diagnosis.
        ame_raw_swap_interval    = (PFNEGLSWAPINTERVALPROC)load_egl_symbol(dl_handle, "eglSwapInterval");
    }

    // NOTE: mg_init_gles() is called from gl_make_current() after the
    // EGL context is made current, because init_target_gles() queries
    // GL version/extensions which requires an active context.

    // LTW mode: resolve eglCreateContext / eglDestroyContext / eglMakeCurrent directly from libltw.dylib,
    // not from ANGLE.
    //
    // Reason: LTW translates OpenGL Core 3.3 to OpenGL ES 3 and injects wrapper logic into these functions
    // (create an ES3 context, install a GL function-pointer translation table, and emulate ARB extensions).
    // Using ANGLE's eglCreateContext directly would create a native ES3 context; MC 1.17+ rejects it
    // because GL_VERSION lacks "Core Profile," and Sodium/Iris ARB extension queries would all fail.
    // LTW wrappers make MC see OpenGL 3.3 Core Profile and declare extensions such as GL_ARB_buffer_storage,
    // enabling Sodium persistent mapped buffers/texture buffers and Iris draw_buffers_blend.
    //
    // Note: do not use dlsym(RTLD_DEFAULT) (ANGLE symbols are found first in iOS's flat namespace);
    // explicitly dlopen libltw.dylib and resolve symbols from its handle.
    //
    // LTW does not wrap other EGL functions (eglChooseConfig / eglCreateWindowSurface / eglSwapBuffers, etc.);
    // resolve those from ANGLE.
    // Test the "real backend" eglRenderer, not renderer: under SFPEW replacement mode AMETHYST_RENDERER
    // is libSimpleFPEWrapper.dylib, so renderer never equals libltw.dylib and useLTW would always be NO.
    // None of LTW's eglCreateContext / eglDestroyContext / eglMakeCurrent wrappers would be resolved
    // (the load_egl_symbol(ltw_handle, ...) block below would be skipped), so its ES3 context creation,
    // GL function-pointer translation table, and ARB extension emulation would have no effect; the
    // translation layer would effectively be absent and the display would be black. Outside SFPEW mode,
    // eglRenderer == renderer, so behavior is unchanged.
    BOOL useLTW = eglRenderer && strcmp(eglRenderer, RENDERER_NAME_LTW) == 0;
    void *ltw_handle = NULL;
    if (useLTW) {
        ltw_handle = dlopen("@rpath/" RENDERER_NAME_LTW, RTLD_NOW | RTLD_LOCAL);
        if (!ltw_handle) {
            NSLog(@"EGLBridge: LTW renderer selected but failed to load libltw.dylib: %s",
                  dlerror() ?: "unknown dlopen error");
            // Fatal: without LTW wrappers, MC 1.17+ cannot start in LTW mode.
            return false;
        }
        NSLog(@"EGLBridge: LTW mode active, eglCreateContext/Destroy/MakeCurrent resolved from libltw.dylib");
    }

    // SFPEW (SimpleFPEWrapper) — match the integration model in Android Amethyst-Android v3_openjdk.
    //
    // Android JREUtils.java: POJAVEXEC_EGL always points to the real backend (libmobileglues.so /
    // libEGL_angle.so / libEGL_mesa.so / libltw.so). When SFPEW is enabled, it only does two things:
    //   SFPEW_EGL = POJAVEXEC_EGL (real backend); renderLibrary = libSimpleFPEWrapper.so.
    // egl_loader.c dlsym_EGL() then uses loader_dlopen(getenv("POJAVEXEC_EGL")) to obtain
    // eglGetProcAddress, then resolves eglGetDisplay / eglInitialize / eglChooseConfig /
    // eglCreateContext / eglMakeCurrent / eglSwapBuffers, etc.
    // In other words, Android never calls SFPEW's EGL exports; it provides GL only.
    // (JREUtils.java:349 also points SDL_EGL_LIBRARY to POJAVEXEC_EGL for the same reason.)
    //
    // Upstream SFPEW already allows EGL to be bypassed: the sfpewNoteCurrentContext comment in fpe.cpp
    // says "Set by the wrapper's own eglMakeCurrent **when the app routes EGL through us**", and
    // sfpewReconcileContext() recalibrates against the backend's eglGetCurrentContext about every 256
    // resolves (there is also the SFPEW_RELAXED_CONTEXT switch).
    //
    // Therefore, keep EGL lifecycle functions on the real backend dl_handle (= eglRenderer, selected by
    // AMETHYST_SFPEW_BACKEND above). Previously resolving CreateContext/DestroyContext/MakeCurrent/
    // SwapBuffers from SFPEW split EGL in two: infrastructure came from the real backend, while lifecycle
    // calls entered SFPEW and were forwarded to the backend. This differed from Android and caused both
    // SFPEW + MobileGlues and SFPEW + MobileGL-GLES to crash on iOS.

    memset(&handle, 0, sizeof(handle));

    // [sfpew-egl-route] A/B: when AMETHYST_SFPEW_EGL_ROUTE=1, use route (c) and resolve all EGL
    // functions through SFPEW's eglGetProcAddress (the Android/FCL tested model). On failure, fall back
    // to the real-backend dlsym path below; default behavior is unchanged.
    // Task181: the LTW backend must use this route too; Task178's `!useLTW` exclusion was backwards.
    //
    // Key fact: this route does not bypass the backend; it forwards through SFPEW to the backend.
    // For create/destroy/makeCurrent, SFPEW's eglGetProcAddress returns its own wrappers, which call
    // the EGL backend selected by SFPEW_EGL—libltw.dylib's eglCreateContext in this case. LTW wrappers
    // (create an ES3 context, install the GL Core 3.3 → ES3 function-pointer translation table, and
    // emulate ARB extensions) still run and are never bypassed.
    //
    // Excluding it would instead be fatal: eglSwapBuffers would call the backend directly, so SFPEW's
    // pending batch would never drain (see lookup.cpp:75-79). Each frame's geometry would be deferred to
    // the next frame and then cleared—the cause of the fully black LTW/ANGLE + SFPEW screen, related to
    // the white screen with MobileGL-gles. Therefore, do not exclude routes by backend type here.
    if (isSFPEWRenderer(renderer) && ameSFPEWEglRouteWanted()) {
        if (ameSFPEWResolveEGL()) {
            ame_sfpew_egl_route_active = YES;
            NSLog(@"[SFPEW-EGL] route ACTIVE -- lifecycle+infra both resolved through SFPEW "
                  @"(SFPEW forwards infra to backend via SFPEW_EGL)");
            return true;
        }
        NSLog(@"[SFPEW-EGL] route requested but resolution incomplete -- falling back to backend dlsym");
    }

    handle.eglBindAPI = load_egl_symbol(dl_handle, "eglBindAPI");
    handle.eglChooseConfig = load_egl_symbol(dl_handle, "eglChooseConfig");
    if (useLTW && ltw_handle) {
        // Resolve the three wrappers from LTW (required to activate LTW's GL Core→ES translation logic).
        handle.eglCreateContext = load_egl_symbol(ltw_handle, "eglCreateContext");
        handle.eglDestroyContext = load_egl_symbol(ltw_handle, "eglDestroyContext");
        handle.eglMakeCurrent = load_egl_symbol(ltw_handle, "eglMakeCurrent");
    } else {
        handle.eglCreateContext = load_egl_symbol(dl_handle, "eglCreateContext");
        handle.eglDestroyContext = load_egl_symbol(dl_handle, "eglDestroyContext");
        handle.eglMakeCurrent = load_egl_symbol(dl_handle, "eglMakeCurrent");
    }
    handle.eglCreateWindowSurface = load_egl_symbol(dl_handle, "eglCreateWindowSurface");
    handle.eglDestroySurface = load_egl_symbol(dl_handle, "eglDestroySurface");
    handle.eglGetConfigAttrib = load_egl_symbol(dl_handle, "eglGetConfigAttrib");
    handle.eglGetCurrentContext = load_egl_symbol(dl_handle, "eglGetCurrentContext");
    handle.eglGetDisplay = load_egl_symbol(dl_handle, "eglGetDisplay");
    handle.eglGetError = load_egl_symbol(dl_handle, "eglGetError");
    handle.eglGetPlatformDisplay = load_egl_symbol(dl_handle, "eglGetPlatformDisplay");
    handle.eglInitialize = load_egl_symbol(dl_handle, "eglInitialize");
    handle.eglSwapBuffers = load_egl_symbol(dl_handle, "eglSwapBuffers");
    handle.eglReleaseThread = load_egl_symbol(dl_handle, "eglReleaseThread");
    handle.eglSwapInterval = load_egl_symbol(dl_handle, "eglSwapInterval");
    handle.eglTerminate = load_egl_symbol(dl_handle, "eglTerminate");
    handle.eglGetCurrentSurface = load_egl_symbol(dl_handle, "eglGetCurrentSurface");

    return handle.eglBindAPI && handle.eglChooseConfig && handle.eglCreateContext &&
        handle.eglCreateWindowSurface && handle.eglDestroyContext && handle.eglDestroySurface &&
        handle.eglGetConfigAttrib && handle.eglGetDisplay && handle.eglGetError &&
        handle.eglInitialize && handle.eglMakeCurrent && handle.eglSwapBuffers &&
        handle.eglReleaseThread && handle.eglSwapInterval && handle.eglTerminate;
}

// Call only once from gl_init_context (after eglChooseConfig and before eglBindAPI/eglCreateContext).
// Returns YES if lifecycle EGL has switched to the MobileGlues frontend.
static BOOL ame_mgBootstrap(EGLDisplay dpy, EGLConfig config) {
    if (ame_mgBootstrapTried) return ame_mgFrontendActive;
    ame_mgBootstrapTried = YES;

    if (ame_mg_handle == NULL || ame_mg_init_gles == NULL) {
        NSLog(@"[MG-Bridge] bootstrap skipped: frontend image or mg_init_gles unavailable "
              @"-- EGL stays on raw ANGLE (legacy behavior)");
        return NO;
    }
    if (ame_raw_create_pbuffer == NULL || ame_raw_create_context == NULL ||
        ame_raw_make_current == NULL || ame_raw_destroy_context == NULL ||
        ame_raw_destroy_surface == NULL) {
        NSLog(@"[MG-Bridge] bootstrap skipped: raw ANGLE pointers incomplete -- EGL stays on raw ANGLE");
        return NO;
    }

    // 1) Temporary pbuffer + ES3 context (raw ANGLE): solely to ensure mg_init_gles() capability
    //    queries (glGetString, etc.) run in the correct environment with a current context.
    const EGLint pbAttribs[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    EGLSurface pb = ame_raw_create_pbuffer(dpy, config, pbAttribs);
    const EGLint tmpCtxAttribs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext tmpCtx = (pb != EGL_NO_SURFACE)
        ? ame_raw_create_context(dpy, config, EGL_NO_CONTEXT, tmpCtxAttribs)
        : EGL_NO_CONTEXT;

    BOOL ok = NO;
    if (pb != EGL_NO_SURFACE && tmpCtx != EGL_NO_CONTEXT &&
        ame_raw_make_current(dpy, pb, pb, tmpCtx)) {
        // 2) Bind GLES/EGL backend handles + perform real capability detection (idempotent inside MobileGlues).
        ame_mg_init_gles();
        ok = YES;
        NSLog(@"[MG-Bridge] bootstrap: mg_init_gles complete under throwaway ES context "
              @"(GLES/ANGLE handles bound, caps detected)");
    } else {
        NSLog(@"[MG-Bridge] bootstrap FAILED (pbuffer=%p ctx=%p, eglError=0x%x) "
              @"-- EGL stays on raw ANGLE (legacy behavior)",
              (void *)pb, (void *)tmpCtx,
              (unsigned int)(uintptr_t)handle.eglGetError());
    }

    // 3) Release temporary resources regardless of success (MobileGlues never saw them, so no state remains).
    if (pb != EGL_NO_SURFACE || tmpCtx != EGL_NO_CONTEXT) {
        ame_raw_make_current(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (tmpCtx != EGL_NO_CONTEXT) ame_raw_destroy_context(dpy, tmpCtx);
        if (pb != EGL_NO_SURFACE) ame_raw_destroy_surface(dpy, pb);
    }
    if (!ok) return NO;

    // 4) Switch lifecycle EGL to the MobileGlues frontend (eglCreateContext will then create an
    //    MGContext record, eglMakeCurrent will bind g_current_ctx and per-context subsystems,
    //    and eglSwapBuffers will use presentSurface). If any symbol is missing, that call falls back to raw EGL.
    //
    // [fix/sfpew-split-egl] With SFPEW layered over MobileGlues, this switch is still required.
    // Commit 19ef078d removed SFPEW-specific lifecycle handling; handle.egl* now comes from dl_handle,
    // which is ANGLE for non-self-EGL renderers such as MobileGlues. An early return here would produce
    // an ANGLE ES context but MG GL calls (LWJGL → SFPEW → MG gl*), leaving MG per-context state NULL.
    // This caused glTexImage2D crashes, eight "No context is current" errors, and garbage from
    // glCheckFramebufferStatus with SFPEW + MobileGlues 1.7.10.
    // Match the Android model (Amethyst-Android egl_loader.c): dl_handle is libmobileglues.so (MG frontend),
    // and eglCreateContext/eglMakeCurrent resolve from that frontend, so the context belongs to MG throughout.
    // SFPEW handles only GL forwarding (renderLibrary); none of its EGL exports are called. The iOS equivalent
    // is exactly the same AME_MG_SWAP path used for standalone MobileGlues.

    // [sfpew-egl-route] When the route is active, lifecycle calls already use SFPEW:
    // SFPEW's sfpewEglCreateContext forwards to the MG backend's eglCreateContext, and MG creates
    // its own MGContext. Applying AME_MG_SWAP here would remove SFPEW from the EGL chain entirely,
    // returning to model (b) with an empty registry. mg_init_gles bootstrap has completed; leave it intact.
    if (ame_sfpew_egl_route_active) {
        ame_mgFrontendActive = YES;
        NSLog(@"[MG-Bridge] bootstrap done; SFPEW EGL route active -- lifecycle stays on SFPEW "
              @"(backend reached via SFPEW_EGL, MGContext built by MG itself)");
        return YES;
    }

    void *fn = NULL;
    #define AME_MG_SWAP(field, name)                                                  \
        do {                                                                          \
            fn = dlsym(ame_mg_handle, name);                                          \
            if (fn != NULL) { handle.field = fn; }                                    \
            else NSLog(@"[MG-Bridge] frontend " name " missing -- raw ANGLE retained"); \
        } while (0)
    AME_MG_SWAP(eglBindAPI,        "eglBindAPI");
    AME_MG_SWAP(eglCreateContext,  "eglCreateContext");
    AME_MG_SWAP(eglDestroyContext, "eglDestroyContext");
    AME_MG_SWAP(eglMakeCurrent,    "eglMakeCurrent");
    AME_MG_SWAP(eglSwapBuffers,    "eglSwapBuffers");
    AME_MG_SWAP(eglSwapInterval,   "eglSwapInterval");
    #undef AME_MG_SWAP

    ame_mgFrontendActive = YES;
    NSLog(@"[MG-Bridge] EGL lifecycle routed through MobileGlues frontend "
          @"(MGContext tracking + presentSurface active)");
    return YES;
}

static bool gl_init() {
    if (!dlsym_EGL()) {
        return false;
    }

    g_EglDisplay = handle.eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_EglDisplay == EGL_NO_DISPLAY) {
        NSDebugLog(@"EGLBridge: eglGetDisplay(EGL_DEFAULT_DISPLAY) returned EGL_NO_DISPLAY");
        return false;
    }
    if (!handle.eglInitialize(g_EglDisplay, NULL, NULL)) {
        NSDebugLog(@"EGLBridge: Error eglInitialize() failed: 0x%x", handle.eglGetError());
        return false;
    }
    return true;
}

// Whether to classify desktop GL by the real backend under SFPEW overlay (diagnostic escape hatch, default off).
static BOOL ameSFPEWForceDesktopGL(void) {
    const char *v = getenv("AMETHYST_SFPEW_DESKTOPGL");
    return v != NULL && v[0] != '\0' && v[0] != '0';
}

gl_render_window_t* gl_init_context(gl_render_window_t *share) {
    gl_render_window_t* bundle = calloc(1, sizeof(gl_render_window_t));

    NSString *renderer = NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"];
    // Under SFPEW overlay, AMETHYST_RENDERER has been replaced with libSimpleFPEWrapper.dylib;
    // the real backend name is in AMETHYST_SFPEW_BACKEND (used to select EGL sources; see dlsym_EGL()).
    const char *apiRenderer = renderer.UTF8String;
    const BOOL sfpewActive = isSFPEWRenderer(apiRenderer);
    if (sfpewActive) {
        const char *sfpewBackend = getenv("AMETHYST_SFPEW_BACKEND");
        if (sfpewBackend != NULL && sfpewBackend[0] != '\0') apiRenderer = sfpewBackend;
    }
    // ANGLE / Mithril / MobileGL expose desktop OpenGL and use EGL_OPENGL_BIT +
    // eglBindAPI(EGL_OPENGL_API); others (gl4es / MobileGlues / LTW) use OpenGL ES.
    BOOL desktopGL = isDesktopGLRenderer(apiRenderer);
    // ---- SFPEW overlay: always use an OpenGL ES context ----------------------
    // SFPEW-generated fixed-pipeline shaders always use `#version 300 es`
    // (mg_shader_header in fpe_shadergen.cpp is unconditionally prepended to both VS/FS; there is no desktop branch).
    // Therefore, whenever SFPEW is present, the context must be ES—even if the real backend reports desktop GL.
    //
    // MobileGL-gles is the clearest counterexample: GL_VERSION reports "4.6.0 MobileGL 26.09-dev,
    // Direct (OpenGL ES) Backend"; ANGLE provides EGL with only ES configs. SFPEW also classifies it
    // as an ES backend (capabilities.cpp's sfpewBackendTakesBgra enables BGRA reordering for it).
    // Previously, however, isDesktopGLRenderer matched the real backend name, requesting EGL_OPENGL_BIT
    // + eglBindAPI(EGL_OPENGL_API). This sent ES 3.00 shaders to a desktop context → compile/link failure
    // → draw with an invalid program → repeated GL_INVALID_OPERATION(1282) in Pre/Post startup and render.
    //
    // Android also defaults eglBindAPI to ES (only zink uses desktop), matching this behavior.
    // Escape hatch: AMETHYST_SFPEW_DESKTOPGL=1 restores the old "classify by real backend" behavior.
    if (sfpewActive && !ameSFPEWForceDesktopGL()) {
        if (desktopGL) {
            NSDebugLog(@"EGLBridge: SFPEW overlay active -- forcing OpenGL ES context "
                       @"(FPE shaders are #version 300 es, backend '%s' self-reports desktop GL)",
                       apiRenderer);
        }
        desktopGL = NO;
    }
    BOOL mobileGL = isMobileGLRenderer(apiRenderer);

    const EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT|EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, desktopGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };

    EGLint num_configs;
    EGLint vid;
    if (!handle.eglChooseConfig(g_EglDisplay, attribs, &bundle->config, 1, &num_configs)) {
        NSDebugLog(@"EGLBridge: Error couldn't get an EGL visual config: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    assert(bundle->config);
    assert(num_configs > 0);

    if (!handle.eglGetConfigAttrib(g_EglDisplay, bundle->config, EGL_NATIVE_VISUAL_ID, &vid)) {
        NSDebugLog(@"EGLBridge: Error eglGetConfigAttrib() failed: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    // Task36: bootstrap MobileGlues before the first frontend EGL call (eglBindAPI):
    // bind backend handles, detect capabilities, and switch lifecycle pointers to the frontend.
    // It must run here: config is available (required by bootstrap), and eglBindAPI/eglCreateContext
    // have not yet run (the frontend's internal LOAD_EGL static pointers require the backend to be bound).
    ame_mgBootstrap(g_EglDisplay, bundle->config);

    EGLBoolean bindResult;
    if (desktopGL) {
        NSDebugLog(@"EGLBridge: Binding to desktop OpenGL");
        bindResult = handle.eglBindAPI(EGL_OPENGL_API);
    } else {
        NSDebugLog(@"EGLBridge: Binding to OpenGL ES");
        bindResult = handle.eglBindAPI(EGL_OPENGL_ES_API);
    }
    if (!bindResult) NSDebugLog(@"EGLBridge: bind failed: %p\n", handle.eglGetError());

    CALayer *layer = SurfaceViewController.surface.layer;
    // ============================================================================
    // Task50 (root-cause fix for black screen) → Task60 (root-cause fix for blur): a single source of
    // truth for presentation geometry—alignment to native-scale pixels.
    //
    // History (622166a black-screen era; this block replaced Task48 creation pinning + Task49 retry loop):
    //   1. No "Task48 pin" entries appeared in any log (per-frame guard pinning never worked): render-thread
    //      layer reads disagreed with main-thread heartbeat reads (CALayer cross-thread state divergence),
    //      and render-thread drawableSize writes did not enter the main thread's CA committed tree.
    //   2. Task49 retry loop failed five times: even after pinning to 1180x820, ANGLE created 2360x1640
    //      because ANGLE reads bounds × contentsScale (=1180x820×2.0), not drawableSize.
    //   3. Guard surface recreation always failed with EGL_BAD_ALLOC 0x3003 (creating a second window
    //      surface on the same layer always fails). After failure, surface remained transposed at
    //      1640x2360 while drawable/viewport were landscape 2360x1640. A 600+ frame present-size mismatch
    //      produced the black screen.
    //
    // Structural cause of the black screen was a conflict among three dimensions (1x point viewport,
    // 2x drawable, ANGLE surface). Task50 ended the conflict with 1x point alignment, but halved render resolution:
    //   - MC 26.3: surface 1180x820 → MC viewport followed → half-resolution rendering, then CA linearly
    //     enlarged it 2x, blurring the full screen (blur measured on device in 5f1df50). The assumption
    //     that MC's pixel art would remain sharp with nearest-neighbor scaling was false: CAMetalLayer
    //     defaults to linear filtering, and MC 26.3 uses smooth lighting/fonts/gradients.
    //   - MC 26.2 LWJGL: MC expected 2360x1640 != surface 1180x820, so Task49 geo-heal downsampled
    //     every frame (double blur + bandwidth cost), measured on device as "MG compatibility regression
    //     with LWJGL." The MG 2.0.16 SYMBOL THEFT warning was harmless environment diagnostics; its symbol
    //     resolution does not depend on flat-namespace order.
    //
    // Task60 fix (unit consistency established by Task58 EGL constant correction + Task59 direct input-pixel
    // pass-through): align to native-scale pixels—contentsScale = authoritative screen scale (the window
    // screen of the view owning the layer, falling back to the main screen); drawableSize = bounds × scale
    // (=2360x1640). The entire pipeline uses pixels: surface==drawable==physical screen pixels at 1:1 with
    // no scaling; launchJVM reports 2360x1640 to MC, matching its window dimensions; Task59's direct input
    // path is unaffected; and the MC 26.2 LWJGL viewport 2360x1640 == surface, so geo-heal blit exits
    // naturally. During rotation, bounds follow and dimensions flip together (ANGLE's ability to follow
    // layer geometry is proven by the transposition event in 622166a).
    //   Vulkan is unaffected: gl_init_context runs only on the GL path.
    // ============================================================================
    // Task60 layer alignment must be written on the main thread. A fatal flaw in the old code was writing
    // drawableSize from the render thread (CALayer state diverged across threads: the render thread and
    // main-thread CA committed tree saw different values—the 622166a mismatch between heartbeat
    // drawable=2360x1640 and guard reading 1640x2360). Single-writer discipline: this block and
    // updateSavedResolution (main thread during rotation) are the only two layer-size writers, and both
    // run on the main thread.
    if ([layer isKindOfClass:CAMetalLayer.class]) {
        __block CGSize oldDrawable50 = CGSizeZero;
        __block CGFloat oldScale50 = 0.0;
        void (^align60)(void) = ^{
            CAMetalLayer *ml60 = (CAMetalLayer *)layer;
            CGFloat w60 = MAX(1.0, round(layer.bounds.size.width));
            CGFloat h60 = MAX(1.0, round(layer.bounds.size.height));
            // Task60: authoritative scale—the window screen of the view owning the layer
            // (correct for external displays), falling back to the main screen, then 1.0.
            // Same source as screenScale in the Task59 input path; resolutionScale semantics belong
            // to host updateSavedResolution (at creation, align to native scale here).
            CGFloat scale60 = 0.0;
            UIView *v60 = (UIView *)layer.delegate;  // CALayer.delegate == owning UIView
            if (v60 != nil && v60.window != nil && v60.window.screen != nil) {
                scale60 = v60.window.screen.scale;
            }
            if (scale60 <= 0.0) scale60 = UIScreen.mainScreen.scale;
            if (scale60 <= 0.0) scale60 = 1.0;
            // Task78: apply resolutionScale (video.resolution) at creation too.
            // Previously, when resolutionScale<100%, drawableSize was pinned to full physical resolution,
            // then updateSavedResolution wrote a smaller value, causing a post-creation conflict. Under
            // the Task57 freeze patch, surface stayed at its creation size and the guard reset drawableSize
            // to full surface size each time; users saw a "half-resolution option + per-frame geo-heal blit."
            // Creation and rotation writers now use the same units (bounds × screenScale × resolutionScale),
            // establishing a single source of truth. At 100%, values exactly match the old behavior (no regression).
            // Task78 FSR integration: updateSavedResolution alone scales the window reported to MC
            // (=viewport=render size) to surface/fsr_scale. This block handles only surface/drawable units
            // and is independent of fsr_scale.
            CGFloat rs60 = resolutionScale;
            if (rs60 <= 0.0) rs60 = 1.0;  // Guard against an uninitialized global (e.g. JavaGUI paths).
            oldDrawable50 = ml60.drawableSize;
            oldScale50 = layer.contentsScale;
            layer.contentsScale = scale60 * rs60;
            ml60.drawableSize = CGSizeMake(round(w60 * scale60 * rs60), round(h60 * scale60 * rs60));
        };
        if ([NSThread isMainThread]) {
            align60();
        } else {
            // gl_init_context runs on the JVM render thread; the main thread is in an idle run loop at this point.
            // (launchJVM runs on a background thread, and the main thread holds no lock that the render thread
            // is waiting for—the dispatch_sync of ame_embedSDLViewIntoHost was verified safe on-device in the same window.)
            dispatch_sync(dispatch_get_main_queue(), align60);
        }
        NSLog(@"[GLGeo] Task60 native-scale alignment (main thread): bounds=%.0fx%.0f drawableSize %.0fx%.0f scale %.2f -> drawableSize %.0fx%.0f scale %.2f (surface==drawable==physical px; Task50 1x retired -- CA linear 2x upscale was the blur)",
              layer.bounds.size.width, layer.bounds.size.height,
              oldDrawable50.width, oldDrawable50.height, oldScale50,
              layer.bounds.size.width * layer.contentsScale,
              layer.bounds.size.height * layer.contentsScale,
              (double)layer.contentsScale);
    }
    // MobileGL's eglCreateWindowSurface does not infer dimensions from CALayer; supply width/height
    // explicitly (read from the native-scale-aligned layer to match drawableSize), or it creates a 1x1
    // surface and the in-game display is broken. Other renderers infer size from the layer; pass NULL.
    const EGLint mobileGLSurfaceAttribs[] = {
        EGL_WIDTH, (EGLint)MAX(1.0, round(layer.bounds.size.width * layer.contentsScale)),
        EGL_HEIGHT, (EGLint)MAX(1.0, round(layer.bounds.size.height * layer.contentsScale)),
        EGL_NONE
    };
    // Create once (no retry loop): after native-scale alignment, whether ANGLE reads bounds×scale
    // or drawableSize, it gets the same dimensions as MC viewport; no enforcement is needed.
    bundle->surface = handle.eglCreateWindowSurface(g_EglDisplay, bundle->config,
        (__bridge EGLNativeWindowType)layer, mobileGL ? mobileGLSurfaceAttribs : NULL);
    if (!bundle->surface) {
        NSDebugLog(@"EGLBridge: eglCreateWindowSurface finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    // Black-screen diagnostics (Task32): on successful surface creation, log full presentation-target state—
    // layer pointer/bounds/contentsScale/drawableSize/whether it is in the window hierarchy.
    // If the screen later goes black, compare against this to tell whether the layer size/hierarchy was
    // already wrong when the context was created.
    {
        BOOL isMetal = [layer isKindOfClass:CAMetalLayer.class];
        CGSize drawable = isMetal ? ((CAMetalLayer *)layer).drawableSize : CGSizeZero;
        UIView *layerView = layer.delegate;  // CALayer.delegate == owning UIView
        BOOL inWindow = (layerView != nil && [(UIView *)layerView window] != nil);
        NSLog(@"[RenderDiag] EGL window surface created: surface=%p layer=%p bounds=%.0fx%.0f contentsScale=%.2f drawableSize=%.0fx%.0f ownerInWindow=%d",
              (void *)bundle->surface, (__bridge void *)layer,
              layer.bounds.size.width, layer.bounds.size.height,
              (double)layer.contentsScale, drawable.width, drawable.height, (int)inWindow);
        // Task36 diagnostics: actual EGL-side surface dimensions. MC RenderPearl's surface configuration
        // reported 1180x820; if eglQuerySurface reports 2360x1640 here, a 2x mismatch exists. Use the
        // next device log to diagnose compositing/scaling.
        if (ame_raw_query_surface != NULL && bundle->surface != EGL_NO_SURFACE) {
            EGLint sw = 0, sh = 0;
            if (ame_raw_query_surface(g_EglDisplay, bundle->surface, EGL_WIDTH, &sw) &&
                ame_raw_query_surface(g_EglDisplay, bundle->surface, EGL_HEIGHT, &sh)) {
                NSLog(@"[RenderDiag] eglQuerySurface: %dx%d", sw, sh);
            }
        }
        // Task48: record the presentation layer (CFBridgingRetain) and expected surface size for
        // per-frame healing by ame48_swap_geometry_guard.
        ame48_record_creation(layer, g_EglDisplay, bundle->surface);
        // Task50: GL owns the presentation layer (cross-thread flag); from now on main-thread
        // updateSavedResolution uses native-scale alignment (bounds × scale, follows rotation).
        atomic_store(&g_ame50_gl_owns_layer, 1);
    }

    const EGLint gles_ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    // MobileGL uses true desktop GL and requires 3.3 Core Profile.
    // Mithril also exposes desktop GL 3.3 Core, but its EGLConfig declares both
    // EGL_OPENGL_BIT | EGL_OPENGL_ES3_BIT, so it can use the ES-style CLIENT_VERSION=3
    // (matching the configuration verified in Uniaball's official launcher patch).
    const EGLint desktop_ctx_attribs[] = {
        EGL_CONTEXT_MAJOR_VERSION, 3,
        EGL_CONTEXT_MINOR_VERSION, 3,
        EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
        EGL_NONE
    };
    bundle->context = handle.eglCreateContext(g_EglDisplay, bundle->config, share ? share->context : EGL_NO_CONTEXT,
        mobileGL ? desktop_ctx_attribs : gles_ctx_attribs);
    if (!bundle->context) {
        NSDebugLog(@"EGLBridge: Error eglCreateContext finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    //NSDebugLog(@"EGLBridge: Created CTX pointer = %p (source = %p)", bundle->context, share?share->context:0);

    return bundle;
}

void gl_make_current(gl_render_window_t* bundle) {
    if(!bundle) {
        if(handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)) {
            currentBundle = NULL;
        }
        return;
    }

    if(handle.eglMakeCurrent(g_EglDisplay, bundle->surface, bundle->surface, bundle->context)) {
        currentBundle = (basic_render_window_t *)bundle;
        if (ame_mgFrontendActive) {
            NSLog(@"[MG-Bridge] eglMakeCurrent via frontend OK (ctx=%p) -- "
                  @"MGContext tracked, per-context state bound",
                  (void *)bundle->context);
        }

        // MobileGlues 2.0: on Apple, init GL ES function pointers now that
        // we have a current context.  mg_init_gles() uses RTLD_DEFAULT to
        // resolve ANGLE's GLES symbols and queries GL version/extensions.
        // Only runs once; subsequent calls are a no-op.
        // (After successful Task36 bootstrap this is a harmless no-op; if bootstrap failed, this remains the original fallback path.)
        static BOOL mgInitialized = NO;
        if (!mgInitialized) {
            mgInitialized = YES;
            typedef void (*mg_init_gles_t)(void);
            mg_init_gles_t fn = (mg_init_gles_t)dlsym(RTLD_DEFAULT, "mg_init_gles");
            if (fn) {
                fn();
                NSLog(@"[gl_bridge] mg_init_gles() called after eglMakeCurrent");
            } else {
                NSLog(@"[gl_bridge] mg_init_gles not found (old MobileGlues?)");
            }
        }

        // Key to unlocking the frame rate: set swap interval=0 as soon as the EGL context first becomes current.
        //
        // Why it must be set here (rather than waiting for MC to call glfwSwapInterval):
        //
        // For the zink renderer (Mesa 21.0), the Vulkan swapchain is created lazily—
        // on the first eglSwapBuffers or when the swapchain is needed.
        // When creating the swapchain, zink chooses its present mode from the current eglSwapInterval:
        //   - interval=0 → VK_PRESENT_MODE_IMMEDIATE_KHR (no VSync wait; frame rate can exceed 60).
        //   - interval=1 → VK_PRESENT_MODE_FIFO_KHR (wait for VSync; lock to the display refresh rate).
        //
        // If this waits until MC calls glfwSwapInterval(1) → pojavSwapInterval(0) → eglSwapInterval(0),
        // the swapchain may already have been created with the default FIFO mode.
        // Mesa 21.0 zink does not recreate the swapchain when eglSwapInterval changes,
        // so present mode stays FIFO and frame rate is locked to display refresh (60Hz/120Hz).
        //
        // Setting eglSwapInterval(0) early in gl_make_current ensures zink sees interval=0 when it
        // creates the swapchain and selects IMMEDIATE present mode.
        //
        // This also works for the ANGLE Metal backend (ANGLE does not wait for VSync when interval=0).
        if (getenv("POJAV_DISABLE_VSYNC") && strcmp(getenv("POJAV_DISABLE_VSYNC"), "1") == 0) {
            static BOOL s_loggedInitialSwapInterval = NO;
            EGLBoolean feOk = handle.eglSwapInterval(g_EglDisplay, 0);
            // Task76: redundant safeguard—set once through the MobileGlues frontend and once through raw ANGLE.
            // The frontend's LOAD_EGL should pass through to the backend, but the MG session stayed capped
            // at 60 fps (none of 33 heartbeats exceeded 60 with max.fps=260 unlocked), suggesting ANGLE Metal
            // did not honor interval=0. The raw call bypasses frontend translation. Log both return values
            // to diagnose in the next device log (frontend swallowed the call vs. ANGLE Metal does not
            // support interval=0).
            EGLBoolean rawOk = EGL_FALSE;
            if (ame_raw_swap_interval != NULL) {
                rawOk = ame_raw_swap_interval(g_EglDisplay, 0);
            }
            if (!s_loggedInitialSwapInterval) {
                s_loggedInitialSwapInterval = YES;
                NSLog(@"[gl_bridge] eglSwapInterval(0) after eglMakeCurrent (POJAV_DISABLE_VSYNC=1, renderer=%s) frontend=%d raw=%d(rawPtr=%p)",
                      getenv("AMETHYST_RENDERER") ?: "<unset>", (int)feOk, (int)rawOk,
                      (void *)(uintptr_t)ame_raw_swap_interval);
            }
        }
    } else {
        NSLog(@"EGLBridge: eglMakeCurrent returned with error: 0x%x", handle.eglGetError());
    }
}

void gl_swap_buffers() {
    // currentBundle is assigned only after eglMakeCurrent succeeds. If MC calls swap before MakeCurrent
    // (or after MakeCurrent(NULL) releases the context), dereferencing a null pointer here would segfault.
    // On the SDL3 path, we take over SDL_GL_SwapWindow, so GLFW no longer constrains when it is called;
    // an explicit guard is required.
    if (currentBundle == NULL) {
        NSLog(@"EGLBridge: gl_swap_buffers called with no current context, ignored");
        return;
    }
    // Task77: start of the build phase—the elapsed MC frame construction time (tick/event pump/GL encoding)
    // since the previous present returned is captured here. Record before guard/diagnostics so their time
    // belongs to neither phase (probe frames are rare after Task76 and can be ignored).
    uint64_t ame77_t_entry = ame77_now_us();
    ame77_record_build(ame77_t_entry);
    // Task48 presentation geometry guard: run before any swap action (it may recreate the surface internally,
    // updating currentBundle->gl.surface; subsequent probes/swaps then use the new surface).
    ame48_swap_geometry_guard(currentBundle);
    // Black-screen diagnostics (Task32): record the actual result of every swap.
    // Success: log the first success (proves the presentation path worked at least once), then rely on atomic
    // counters summarized by SurfaceViewController's five-second [RenderDiag] heartbeat.
    // Failure: log any error code (remove the old EGL_BAD_SURFACE-only filter), log the first 10 individually,
    // then every 100th to avoid flooding.
    ame_task41_swap_forensics(currentBundle->gl.surface,
                              atomic_load(&g_eglSwapOK) + atomic_load(&g_eglSwapFail) + 1);
    // Task77: time the present phase around eglSwapBuffers only.
    uint64_t ame77_t_present0 = ame77_now_us();
    EGLBoolean swapResult = handle.eglSwapBuffers(g_EglDisplay, currentBundle->gl.surface);
    uint64_t ame77_t_present1 = ame77_now_us();
    ame77_record_present((uint32_t)(ame77_t_present1 - ame77_t_present0), ame77_t_present1);
    if (!swapResult) {
        unsigned long fails = atomic_fetch_add(&g_eglSwapFail, 1) + 1;
        unsigned int eglErr = (unsigned int)(uintptr_t)handle.eglGetError();
        if (fails <= 10 || fails % 100 == 0) {
            NSLog(@"[RenderDiag] eglSwapBuffers FAILED #%lu eglError=0x%x surface=%p (render loop alive, presentation broken)",
                  fails, eglErr, (void *)currentBundle->gl.surface);
        }
        return;
    }
    unsigned long oks = atomic_fetch_add(&g_eglSwapOK, 1) + 1;
    if (oks == 1) {
        NSLog(@"[RenderDiag] first eglSwapBuffers OK surface=%p (presentation path confirmed)",
              (void *)currentBundle->gl.surface);
        // ★ [SDL-FIRSTFRAME] Fallback first-frame signal: this counter is hard evidence that a frame was actually presented.
        //   egl_bridge posts PojavFirstFrameRendered only at the entry to pojavSwapBuffers. If MC/the renderer
        //   reaches this bridge through its own eglSwapBuffers (bypassing pojavSwapBuffers—the old log message
        //   "egl_bridge swap is not used" describes this case), the first-frame notification is never posted.
        //   The overlay then waits until its 45-second timeout and incorrectly reports "startup failed."
        //   Post a one-time notification here to supply the signal. If both paths post it, the overlay is still
        //   dismissed only once (onFirstFrameRendered / dismiss paths both guard with launchOverlayDismissed).
        static dispatch_once_t ameFirstSwapNotifyOnce;
        dispatch_once(&ameFirstSwapNotifyOnce, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"PojavFirstFrameRendered"
                                                                    object:nil];
                NSLog(@"[SDL-FIRSTFRAME] first frame signalled from gl_bridge swap #1 "
                      @"(pojavSwapBuffers-independent present path) -- launch overlay may now be "
                      @"dismissed early instead of waiting for the 45s timeout");
            });
        });
    }
    // Task76: track frame-interval spikes (see the counter block comment at the top of this file).
    ame76_record_swap(ame53_now_ms());
}

void gl_swap_interval(int swapInterval) {
    handle.eglSwapInterval(g_EglDisplay, swapInterval);
}

void gl_terminate() {
    // Task50: GL no longer owns the presentation layer (the next updateSavedResolution returns to the 2x default).
    atomic_store(&g_ame50_gl_owns_layer, 0);
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    handle.eglDestroySurface(g_EglDisplay, currentBundle->gl.surface);
    handle.eglDestroyContext(g_EglDisplay, currentBundle->gl.context);
    handle.eglTerminate(g_EglDisplay);
    handle.eglReleaseThread();
    free(currentBundle);
    currentBundle = nil;
}

void set_gl_bridge_tbl() {
    br_init = gl_init;
    br_init_context = (br_init_context_t) gl_init_context;
    br_make_current = (br_make_current_t) gl_make_current;
    br_swap_buffers = gl_swap_buffers;
    br_swap_interval = gl_swap_interval;
    br_terminate = gl_terminate;
}
