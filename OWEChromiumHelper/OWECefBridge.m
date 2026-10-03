// The only code that talks to CEF. It uses CEF's C API from the headers vendored for the pinned
// version (Vendor/cef) and resolves every function with dlsym from the framework the app
// installed, so nothing links CEF at build time and the app itself never loads it.

#import "OWECefBridge.h"

#import <AppKit/AppKit.h>
#import <crt_externs.h>
#import <dlfcn.h>
#import <os/log.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/internal/cef_string.h"

static NSString *const kFrameworkName = @"Chromium Embedded Framework.framework";
static NSString *const kFrameworkBinary = @"Chromium Embedded Framework";
static const char *kFrameworkDirSwitch = "--framework-dir-path=";
static const char *kFrameworkDirEnvironment = "OWE_CEF_FRAMEWORK_DIR";
/// CEF's helper, copied into the engine bundle's Frameworks folder with its (Renderer), (GPU) and
/// (Plugin) variants, the names Chromium derives from this one.
static NSString *const kHelperName = @"OWE Chromium Helper";

// MARK: - The main bundle CEF sees

// Chromium gives each sandboxed subprocess read access to the browser's main bundle
// (`(allow file-read* (subpath (param bundle-path)))`), computed from +[NSBundle mainBundle].
// CEF's main_bundle_path setting doesn't change that parameter, and this process's own bundle is
// the XPC service, so the framework and helpers in the engine bundle would be unreadable once a
// subprocess enters the sandbox. This process exists only to host CEF, so from just before
// cef_initialize its main bundle is the engine bundle (OWE Chromium.app).
static NSBundle *engineMainBundle;
@implementation NSBundle (OWEEngineMainBundle)
+ (NSBundle *)owe_mainBundle { return engineMainBundle ?: [self owe_mainBundle]; }
@end
static void use_engine_main_bundle(NSString *path) {
    engineMainBundle = [NSBundle bundleWithPath:path];
    method_exchangeImplementations(class_getClassMethod(NSBundle.class, @selector(mainBundle)),
                                   class_getClassMethod(NSBundle.class, @selector(owe_mainBundle)));
}

// MARK: - The NSApplication CEF requires

/// CEF's macOS message loop requires NSApp to implement CefAppProtocol (cef_application_mac.h).
/// The protocol header is C++, so the two methods are implemented by name.
@interface OWECefApplication : NSApplication {
    BOOL _handlingSendEvent;
}
@end

@implementation OWECefApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent { _handlingSendEvent = handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event {
    BOOL previous = _handlingSendEvent;
    _handlingSendEvent = YES;
    [super sendEvent:event];
    _handlingSendEvent = previous;
}
@end

void owe_cef_prepare_application(void) {
    [OWECefApplication sharedApplication];
    // No Dock icon, no menu bar: the helper has no UI.
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
}

// MARK: - Loading the framework

typedef const char *(*api_hash_fn)(int, int);
typedef int (*execute_process_fn)(const cef_main_args_t *, cef_app_t *, void *);
typedef int (*initialize_fn)(const cef_main_args_t *, const cef_settings_t *, cef_app_t *, void *);
typedef void (*void_fn)(void);
typedef cef_browser_t *(*create_browser_sync_fn)(const cef_window_info_t *, cef_client_t *, const cef_string_t *,
                                                 const cef_browser_settings_t *, cef_dictionary_value_t *,
                                                 cef_request_context_t *);
typedef int (*utf8_to_utf16_fn)(const char *, size_t, cef_string_utf16_t *);
typedef void (*utf16_clear_fn)(cef_string_utf16_t *);
typedef void *(*sandbox_initialize_fn)(int, char **);
typedef void (*sandbox_destroy_fn)(void *);

static struct {
    api_hash_fn api_hash;
    execute_process_fn execute_process;
    initialize_fn initialize;
    void_fn do_message_loop_work;
    void_fn shutdown;
    create_browser_sync_fn create_browser_sync;
    utf8_to_utf16_fn utf8_to_utf16;
    utf16_clear_fn utf16_clear;
} cef;

static void set_error(char *error, size_t size, NSString *message) {
    if (error && size > 0) strlcpy(error, message.UTF8String, size);
}

/// Loads the framework binary under `frameworkDir` and resolves the functions used here, then
/// configures the API version the vendored headers describe and checks the library agrees.
static BOOL load_cef(NSString *frameworkDir, char *error, size_t errorSize) {
    NSString *binary = [[frameworkDir stringByAppendingPathComponent:kFrameworkName]
        stringByAppendingPathComponent:kFrameworkBinary];
    void *handle = dlopen(binary.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST);
    if (!handle) {
        const char *reason = dlerror();
        set_error(error, errorSize, [NSString stringWithFormat:@"Can't load %@: %s", binary, reason ? reason : "unknown"]);
        return NO;
    }
#define OWE_RESOLVE(field, symbol)                                                                   \
    cef.field = (__typeof__(cef.field))dlsym(handle, symbol);                                        \
    if (!cef.field) {                                                                                \
        set_error(error, errorSize, [NSString stringWithFormat:@"The framework has no %s", symbol]); \
        return NO;                                                                                   \
    }
    OWE_RESOLVE(api_hash, "cef_api_hash")
    OWE_RESOLVE(execute_process, "cef_execute_process")
    OWE_RESOLVE(initialize, "cef_initialize")
    OWE_RESOLVE(do_message_loop_work, "cef_do_message_loop_work")
    OWE_RESOLVE(shutdown, "cef_shutdown")
    OWE_RESOLVE(create_browser_sync, "cef_browser_host_create_browser_sync")
    OWE_RESOLVE(utf8_to_utf16, "cef_string_utf8_to_utf16")
    OWE_RESOLVE(utf16_clear, "cef_string_utf16_clear")
#undef OWE_RESOLVE
    // Must be the first call into libcef: it fixes the struct layouts both sides use.
    const char *hash = cef.api_hash(CEF_API_VERSION, 0);
    if (!hash || strcmp(hash, CEF_API_HASH_PLATFORM) != 0) {
        set_error(error, errorSize,
                  [NSString stringWithFormat:@"The framework's API (%s) doesn't match the helper's (%s)",
                                             hash ? hash : "none", CEF_API_HASH_PLATFORM]);
        return NO;
    }
    return YES;
}

static void set_string(cef_string_t *target, const char *utf8) {
    if (utf8) cef.utf8_to_utf16(utf8, strlen(utf8), target);
}

// MARK: - Subprocesses

/// A subprocess failure goes to stderr and the unified log: an XPC service's stderr goes nowhere.
static void report(const char *message) {
    fprintf(stderr, "owe-chromium-helper: %s\n", message);
    os_log_error(OS_LOG_DEFAULT, "owe-chromium-helper: %{public}s", message);
}

int owe_cef_is_subprocess(int argc, char *const *argv) {
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--type=", 7) == 0) return 1;
    }
    return 0;
}

static NSString *subprocess_framework_dir(int argc, char **argv) {
    // CEF's layout: <engine>.app/Contents/Frameworks/<helper>.app beside the framework.
    NSString *frameworks = NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent;
    if ([NSFileManager.defaultManager fileExistsAtPath:[frameworks stringByAppendingPathComponent:kFrameworkName]]) {
        return frameworks;
    }
    size_t prefix = strlen(kFrameworkDirSwitch);
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], kFrameworkDirSwitch, prefix) == 0) {
            // The switch names the .framework itself; the folder above holds it.
            NSString *path = [NSString stringWithUTF8String:argv[i] + prefix];
            return [path.lastPathComponent isEqualToString:kFrameworkName] ? path.stringByDeletingLastPathComponent : path;
        }
    }
    const char *environment = getenv(kFrameworkDirEnvironment);
    return environment ? [NSString stringWithUTF8String:environment] : nil;
}

/// A subprocess runs unsandboxed only when the browser was started without the sandbox (Debug
/// builds only, `owe_cef_start`); CEF then passes --no-sandbox on.
static BOOL sandbox_disabled(int argc, char **argv) {
#if DEBUG
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--no-sandbox") == 0) return YES;
    }
#else
    (void)argc; (void)argv;
#endif
    return NO;
}

int owe_cef_run_subprocess(int argc, char **argv) {
    @autoreleasepool {
        NSString *frameworkDir = subprocess_framework_dir(argc, argv);
        if (!frameworkDir) {
            report("no framework folder for this subprocess");
            return 1;
        }
        // The sandbox is entered before the framework loads, as CefScopedSandboxContext does.
        void *sandboxContext = NULL;
        sandbox_destroy_fn sandboxDestroy = NULL;
        if (!sandbox_disabled(argc, argv)) {
            NSString *library = [[frameworkDir stringByAppendingPathComponent:kFrameworkName]
                stringByAppendingPathComponent:@"Libraries/libcef_sandbox.dylib"];
            void *sandbox = dlopen(library.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST);
            sandbox_initialize_fn initialize = sandbox ? (sandbox_initialize_fn)dlsym(sandbox, "cef_sandbox_initialize") : NULL;
            sandboxDestroy = sandbox ? (sandbox_destroy_fn)dlsym(sandbox, "cef_sandbox_destroy") : NULL;
            sandboxContext = initialize ? initialize(argc, argv) : NULL;
            if (!sandboxContext) {
                report("can't enter CEF's sandbox");
                return 1;
            }
        }
        char error[2048] = {0};
        if (!load_cef(frameworkDir, error, sizeof error)) {
            report(error);
            return 1;
        }
        cef_main_args_t args = {.argc = argc, .argv = argv};
        int code = cef.execute_process(&args, NULL, NULL);
        if (sandboxContext && sandboxDestroy) sandboxDestroy(sandboxContext);
        return code;
    }
}

// MARK: - Reference counting of the handlers below

// The client and render handler live for the whole process, so counting is a no-op.
static void CEF_CALLBACK static_add_ref(cef_base_ref_counted_t *self) { (void)self; }
static int CEF_CALLBACK static_release(cef_base_ref_counted_t *self) { (void)self; return 0; }
static int CEF_CALLBACK static_has_one_ref(cef_base_ref_counted_t *self) { (void)self; return 0; }
static int CEF_CALLBACK static_has_at_least_one_ref(cef_base_ref_counted_t *self) { (void)self; return 1; }

static void init_base(cef_base_ref_counted_t *base, size_t size) {
    base->size = size;
    base->add_ref = static_add_ref;
    base->release = static_release;
    base->has_one_ref = static_has_one_ref;
    base->has_at_least_one_ref = static_has_at_least_one_ref;
}

// MARK: - The browser

static struct {
    cef_client_t client;
    cef_render_handler_t renderHandler;
    cef_browser_t *browser;
    int width;
    int height;
    owe_cef_frame_callback callback;
    void *context;
    NSTimer *pump;
    atomic_int started;
} state;

static cef_render_handler_t *CEF_CALLBACK client_get_render_handler(cef_client_t *self) {
    (void)self;
    return &state.renderHandler;
}

static void CEF_CALLBACK render_get_view_rect(cef_render_handler_t *self, cef_browser_t *browser, cef_rect_t *rect) {
    (void)self; (void)browser;
    // One device pixel per view pixel: the app asks for the pixel size it shows.
    rect->x = 0;
    rect->y = 0;
    rect->width = state.width;
    rect->height = state.height;
}

static void CEF_CALLBACK render_on_paint(cef_render_handler_t *self, cef_browser_t *browser, cef_paint_element_type_t type,
                                         size_t dirtyRectsCount, cef_rect_t const *dirtyRects, const void *buffer,
                                         int width, int height) {
    // Only called when shared textures are unavailable; phase 1 shares textures only.
    (void)self; (void)browser; (void)type; (void)dirtyRectsCount; (void)dirtyRects; (void)buffer;
    (void)width; (void)height;
}

static void CEF_CALLBACK render_on_accelerated_paint(cef_render_handler_t *self, cef_browser_t *browser,
                                                     cef_paint_element_type_t type, size_t dirtyRectsCount,
                                                     cef_rect_t const *dirtyRects,
                                                     const cef_accelerated_paint_info_t *info) {
    (void)self; (void)browser; (void)dirtyRectsCount; (void)dirtyRects;
    if (type != PET_VIEW || !info || !info->shared_texture_io_surface || !state.callback) return;
    state.callback(state.context, (IOSurfaceRef)info->shared_texture_io_surface);
}

int owe_cef_start(const char *engine_bundle, const char *cache_dir, const char *url, int width, int height,
                  int frame_rate, int no_sandbox, owe_cef_frame_callback callback, void *context, char *error, size_t error_size) {
    @autoreleasepool {
        int expected = 0;
        if (!atomic_compare_exchange_strong(&state.started, &expected, 1)) {
            set_error(error, error_size, @"The helper already started a browser");
            return 1;
        }
        // Everything CEF runs from lives in one bundle, so its sandbox (which allows the main
        // bundle) covers the framework, its resources and the helpers.
        NSString *bundle = [NSString stringWithUTF8String:engine_bundle];
        NSString *frameworks = [bundle stringByAppendingPathComponent:@"Contents/Frameworks"];
        NSString *helper = [frameworks stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.app/Contents/MacOS/%@", kHelperName, kHelperName]];
        if (![NSFileManager.defaultManager isExecutableFileAtPath:helper]) {
            set_error(error, error_size, [NSString stringWithFormat:@"The engine has no helper at %@", helper]);
            return 1;
        }
        if (!load_cef(frameworks, error, error_size)) return 1;
        use_engine_main_bundle(bundle);
        // Subprocesses find the framework through this when CEF doesn't pass the switch on.
        setenv(kFrameworkDirEnvironment, frameworks.fileSystemRepresentation, 1);

        cef_main_args_t args = {.argc = *_NSGetArgc(), .argv = *_NSGetArgv()};
        cef_settings_t settings;
        memset(&settings, 0, sizeof settings);
        settings.size = sizeof settings;
#if DEBUG
        settings.no_sandbox = no_sandbox != 0;
#else
        (void)no_sandbox;
#endif
        settings.windowless_rendering_enabled = 1;
        settings.external_message_pump = 1;
        settings.command_line_args_disabled = 1;
        settings.persist_session_cookies = 0;
        settings.log_severity = LOGSEVERITY_WARNING;
        NSString *frameworkPath = [frameworks stringByAppendingPathComponent:kFrameworkName];
        set_string(&settings.framework_dir_path, frameworkPath.fileSystemRepresentation);
        set_string(&settings.main_bundle_path, bundle.fileSystemRepresentation);
        set_string(&settings.browser_subprocess_path, helper.fileSystemRepresentation);
        set_string(&settings.root_cache_path, cache_dir);
        // CEF's own log (fatal checks included): an XPC service's stderr goes nowhere.
        NSString *logFile = [[NSString stringWithUTF8String:cache_dir] stringByAppendingPathComponent:@"cef.log"];
        set_string(&settings.log_file, logFile.fileSystemRepresentation);
        int initialized = cef.initialize(&args, &settings, NULL, NULL);
        cef.utf16_clear(&settings.framework_dir_path);
        cef.utf16_clear(&settings.browser_subprocess_path);
        cef.utf16_clear(&settings.main_bundle_path);
        cef.utf16_clear(&settings.root_cache_path);
        cef.utf16_clear(&settings.log_file);
        if (!initialized) {
            set_error(error, error_size, @"CEF didn't initialize");
            return 1;
        }

        state.width = width;
        state.height = height;
        state.callback = callback;
        state.context = context;
        memset(&state.client, 0, sizeof state.client);
        init_base(&state.client.base, sizeof state.client);
        state.client.get_render_handler = client_get_render_handler;
        memset(&state.renderHandler, 0, sizeof state.renderHandler);
        init_base(&state.renderHandler.base, sizeof state.renderHandler);
        state.renderHandler.get_view_rect = render_get_view_rect;
        state.renderHandler.on_paint = render_on_paint;
        state.renderHandler.on_accelerated_paint = render_on_accelerated_paint;

        cef_window_info_t windowInfo;
        memset(&windowInfo, 0, sizeof windowInfo);
        windowInfo.size = sizeof windowInfo;
        windowInfo.windowless_rendering_enabled = 1;
        windowInfo.shared_texture_enabled = 1;
        cef_browser_settings_t browserSettings;
        memset(&browserSettings, 0, sizeof browserSettings);
        browserSettings.size = sizeof browserSettings;
        browserSettings.windowless_frame_rate = frame_rate;
        cef_string_t address = {0};
        set_string(&address, url);
        state.browser = cef.create_browser_sync(&windowInfo, &state.client, &address, &browserSettings, NULL, NULL);
        cef.utf16_clear(&address);
        if (!state.browser) {
            set_error(error, error_size, @"CEF didn't create the browser");
            return 1;
        }

        // External pump: CEF's work runs on this thread's run loop, at least once per frame.
        NSTimeInterval interval = 1.0 / (frame_rate > 0 ? frame_rate * 2 : 120);
        state.pump = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            cef.do_message_loop_work();
        }];
        return 0;
    }
}

void owe_cef_run(void) {
    // CEF's message pump observes the main run loop's entries and exits and pops one record per
    // exit. CEF starts from a callout inside a run-loop pass whose entry it never saw, so letting
    // that pass end trips its check (EXC_BREAKPOINT). Running nested passes from here keeps the
    // outer one open; every pass CEF sees from now on has both its entry and its exit.
    while (atomic_load(&state.started) && state.callback) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    }
}

void owe_cef_stop(void) {
    if (!atomic_load(&state.started) || !state.browser) return;
    cef_browser_host_t *host = state.browser->get_host(state.browser);
    if (host) {
        host->close_browser(host, 1);
        host->base.release(&host->base);
    }
    state.callback = NULL;
}
