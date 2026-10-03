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
/// helper's place in the engine bundle, else the `--framework-dir-path=` switch, else `OWE_CEF_FRAMEWORK_DIR`.
int owe_cef_run_subprocess(int argc, char **argv);

/// Creates the NSApplication subclass CEF requires. Call before anything touches `NSApp`.
void owe_cef_prepare_application(void);

/// Loads the framework from the engine bundle `engine_bundle` (`OWE Chromium.app`, CEF's macOS
/// app layout: framework and helpers in `Contents/Frameworks`), starts CEF and creates one windowless browser of `width`×`height` pixels that paints shared
/// textures to `callback`. `no_sandbox` turns CEF's sandbox off in Debug builds and is ignored otherwise. Main thread only, once per process. Returns 0 on success, else writes a
/// message into `error` (size `error_size`) and returns nonzero.
int owe_cef_start(const char *engine_bundle, const char *cache_dir, const char *url, int width, int height,
                  int frame_rate, int no_sandbox, owe_cef_frame_callback callback, void *context, char *error, size_t error_size);

/// Runs the main run loop from inside the call that started CEF, until `owe_cef_stop`. Call right
/// after a successful `owe_cef_start`, from the same main-thread callout.
void owe_cef_run(void);

/// Closes the browser and stops pumping CEF's message loop. The process is expected to exit next.
void owe_cef_stop(void);

#ifdef __cplusplus
}
#endif

#endif
