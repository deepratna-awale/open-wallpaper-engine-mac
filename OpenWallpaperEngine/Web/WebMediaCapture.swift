import WebKit

/// Web wallpapers never get the microphone or the camera through `getUserMedia`, in either
/// engine. Without this, WebKit asks the user itself and, once they allow it, macOS asks for the
/// Microphone permission: the app declares that permission only for WE's "Audio recording device"
/// and asks for it only when the user chooses one. A page hears the system's sound through WE's
/// audio listener (`wallpaperRegisterAudioListener`) instead. The Chromium engine refuses the same
/// requests: its windowless browsers have no permission handler, which CEF answers with a refusal,
/// and its helper has no audio-input entitlement.
///
/// Wallpaper Engine itself starts its browser with `--enable-media-stream
/// --use-fake-ui-for-media-stream` (wallpaper64.exe), so there a page's request is granted
/// without asking; on macOS that grant would bring up the Microphone prompt.
enum WebMediaCapture {
    /// The answer to every capture request.
    static func decision(for type: WKMediaCaptureType) -> WKPermissionDecision { .deny }

    static func name(of type: WKMediaCaptureType) -> String {
        switch type {
        case .camera: "camera"
        case .microphone: "microphone"
        case .cameraAndMicrophone: "camera and microphone"
        @unknown default: "media capture"
        }
    }
}

extension WebWallpaperViewModel: WKUIDelegate {
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        OWELog.info(.web, "Refused \(currentWallpaper.project.title)'s request for the \(WebMediaCapture.name(of: type)) (getUserMedia): web wallpapers hear sound through WE's audio listener")
        decisionHandler(WebMediaCapture.decision(for: type))
    }
}
