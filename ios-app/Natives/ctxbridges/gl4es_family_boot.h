//
//  gl4es_family_boot.h
//  AngelAuraAmethyst
//
//  ★ [RENDERER-GAP] Runtime bootstrap interface for additional renderers (VGPU / GL4ESZL2 / NG-GL4ES / VirGL).
//  Source: Gsjsjzhznsz/Air-Minecraft-iOS-Launcher (a later fork in the same project family).
//  Consolidates the Task204/206/211/215 bootstrap logic scattered across teammates' egl_bridge.m,
//  leaving only a few call sites in the host file (egl_bridge.m), with no impact on existing renderers.
//
#ifndef AMETHYST_GL4ES_FAMILY_BOOT_H
#define AMETHYST_GL4ES_FAMILY_BOOT_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Whether any additional ("gap") renderer is selected (reads AMETHYST_RENDERER).
bool ame_gap_renderer_selected(void);

/// Idempotent post-MakeCurrent bootstrap for the gl4es family (VGPU / GL4ESZL2 / NG-GL4ES).
/// Must be called after the actual game context is current (at the end of pojavMakeCurrent).
/// - GL4ESZL2 / NG-GL4ES: dlopen(RTLD_NOLOAD) + set_getprocaddress(resolver) +
///   initialize_gl4es() (built with NO_INIT_CONSTRUCTOR, so the constructor does not run).
/// - VGPU: its own lazy loader takes over; this function only logs and enforces idempotency.
/// Returns immediately for non-gap renderers (one getenv comparison, no side effects).
void ame_gap_gl4es_family_boot(void);

/// Idempotent VirGL server bootstrap. Calls ame_virgl_start_server() only when AMETHYST_RENDERER == libOSMesaVirgl.dylib
/// (starts the in-process vtest server and creates an ANGLE offscreen host context).
/// Returns 0 for success or when unselected; nonzero indicates bootstrap failure (the caller logs it and continues through the OSM bridge).
int ame_gap_virgl_boot(void);

#ifdef __cplusplus
}
#endif

#endif /* AMETHYST_GL4ES_FAMILY_BOOT_H */
