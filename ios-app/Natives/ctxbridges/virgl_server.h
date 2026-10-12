//
//  virgl_server.h
//  Amethyst-iOS-MyRemastered
//
//  Task 111: public interface for the VirGLRenderer (≤26.2) server bootstrap bridge.
//
#ifndef AMETHYST_VIRGL_SERVER_H
#define AMETHYST_VIRGL_SERVER_H

/// vtest server host dylib (virglrenderer 1.3.0 + libepoxy, built by Makefile dep_virgl).
#define AME_VIRGL_VTEST_SERVER_LIB "libvtestserver.dylib"

/// virgl guest library (Mesa 25.0.7 virgl driver + osmesa frontend, built by Makefile dep_virgl).
#define AME_VIRGL_GUEST_LIB "libOSMesaVirgl.dylib"

#if __cplusplus
extern "C" {
#endif

/// Start the virgl vtest service (idempotent).
/// Set VTEST_SOCKET_NAME / GALLIUM_DRIVER=virgl, create an ANGLE offscreen ES3 host context,
/// and start a service thread running vtest_main from libvtestserver.dylib.
/// Returns 0 on success; nonzero indicates bootstrap failure (the caller logs it and continues through the OSM bridge;
/// the error will be exposed when the guest connects).
int ame_virgl_start_server(void);

#if __cplusplus
}
#endif

#endif /* AMETHYST_VIRGL_SERVER_H */
