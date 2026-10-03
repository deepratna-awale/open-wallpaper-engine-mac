#ifndef OWE_CEF_BRIDGE_H
#define OWE_CEF_BRIDGE_H

#include <IOSurface/IOSurfaceRef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Called on the main thread for every frame CEF paints into a shared texture. The surface is
/// CEF's and goes back to its pool when this returns, so it must be copied before returning.
typedef void (*owe_cef_frame_callback)(void *context, IOSurfaceRef surface);

/// Whether `argv` belongs to a CEF subprocess (renderer, GPU, utility): it has a `--type=` switch.
int owe_cef_is_subprocess(int argc, char *const *argv);

/// Runs a CEF subprocess: enters CEF's sandbox (unless it is turned off), loads the framework and
/// returns the exit code of `cef_execute_process`. The framework folder comes from the
/// `--framework-dir-path=` switch CEF passes on, else `OWE_CEF_FRAMEWORK_DIR`.
int owe_cef_run_subprocess(int argc, char **argv);

/// Creates the NSApplication subclass CEF requires. Call before anything touches `NSApp`.
void owe_cef_prepare_application(void);

/// Loads the framework in `framework_dir` (the folder holding `Chromium Embedded Framework.framework`),
/// starts CEF and creates one windowless browser of `width`×`height` pixels that paints shared
/// textures to `callback`. Main thread only, once per process. Returns 0 on success, else writes a
/// message into `error` (size `error_size`) and returns nonzero.
int owe_cef_start(const char *framework_dir, const char *cache_dir, const char *url, int width, int height,
                  int frame_rate, owe_cef_frame_callback callback, void *context, char *error, size_t error_size);

/// Closes the browser and stops pumping CEF's message loop. The process is expected to exit next.
void owe_cef_stop(void);

#ifdef __cplusplus
}
#endif

#endif
