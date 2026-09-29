import Foundation

/// Where system audio comes from.
///
/// - `processTap`: a Core Audio process tap (macOS 14.2+). It needs only the System Audio
///   Recording permission.
/// - `screenCapture`: a ScreenCaptureKit stream, which needs Screen Recording. Used before macOS
///   14.2, and when the tap can't start.
enum SystemAudioBackend: Equatable {
    case processTap
    case screenCapture

    /// The backends one capture start tries, in order, skipping any that would make macOS show a
    /// permission prompt (the permission gate leaves prompting to explicit user actions).
    ///
    /// The tap comes first whenever it may start: it is cheaper and asks for less. An `.unknown`
    /// tap permission (its TCC functions are missing) still tries the tap, because then nothing
    /// can tell whether it was granted. ScreenCaptureKit follows as the fallback when Screen
    /// Recording is already granted, so a user who granted only that keeps their audio.
    static func candidates(tapSupported: Bool,
                           tapPermission: SystemAudioRecordingPermission.Status,
                           screenRecordingGranted: Bool) -> [SystemAudioBackend] {
        var result: [SystemAudioBackend] = []
        if tapSupported, tapPermission == .authorized || tapPermission == .unknown {
            result.append(.processTap)
        }
        if screenRecordingGranted { result.append(.screenCapture) }
        return result
    }

    /// The permission to ask the user for when no backend can start: System Audio Recording where
    /// the tap exists, Screen Recording before.
    static func requestedPermission(tapSupported: Bool) -> SystemAudioBackend {
        tapSupported ? .processTap : .screenCapture
    }
}
