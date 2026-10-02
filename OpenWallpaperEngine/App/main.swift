//
//  main.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/6.
//

import Cocoa

// Before any JavaScriptCore VM exists: the SceneScript watchdog must be able to stop JIT-compiled
// loops.
SceneScriptJIT.configurePollingTraps()

// The crash watcher (Settings › Restart after crashing) only waits on the app: no JavaScriptCore,
// no app lifecycle.
if let status = CrashWatcher.runIfRequested(arguments: ProcessInfo.processInfo.arguments) {
	exit(status)
}

MainActor.assumeIsolated {
	// A helper run (`ShaderPrewarmCommand`) does its work and exits before the app's lifecycle
	// starts: no delegate, no windows, no playback.
	if let status = ShaderPrewarmCommand.run(arguments: ProcessInfo.processInfo.arguments) {
		exit(status)
	}
	// Unit tests are hosted in the app; skip the delegate so a test run doesn't open wallpaper
	// windows, start playback or overwrite the user's saved state.
	if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
		NSApplication.shared.delegate = AppDelegate.shared
	} else {
		// A test host has no delegate, so it marks its own Dock icon (`DockBadge.test`).
		DockBadge.current.apply(to: NSApplication.shared.dockTile)
	}
	NSApplication.shared.run()
}
