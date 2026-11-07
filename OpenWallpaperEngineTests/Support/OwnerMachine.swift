import Foundation

/// The maintainer's drive, where the library tests find the wallpaper library, WE's install, the
/// SceneScript corpus and reference captures. A test that needs it skips when its path is missing,
/// as on GitHub's runners. CI sets `OWE_HERMETIC=1` (`TEST_RUNNER_OWE_HERMETIC` through
/// `xcodebuild`) so those tests skip on any runner where the drive exists: CI's answer mustn't
/// depend on which runner took the job.
enum OwnerMachine {
    static let volume: String = ProcessInfo.processInfo.environment["OWE_HERMETIC"] == "1"
        ? "/nonexistent/owe-hermetic" : "\(OwnerMachine.volume)"
}
