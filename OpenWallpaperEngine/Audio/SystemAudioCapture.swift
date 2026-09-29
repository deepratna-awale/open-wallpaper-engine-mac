import Accelerate
import Cocoa
import CoreMedia
import ScreenCaptureKit

/// System audio capture: the capture itself and its restarts, the overall level (video music
/// sync) and WE's spectrum analyzer (shaders' `g_AudioSpectrum*`, SceneScript's
/// `registerAudioBuffers`). Owned by `WallpaperServices`.
///
/// The audio comes from a Core Audio process tap on macOS 14.2+ (System Audio Recording
/// permission), or from a ScreenCaptureKit stream (Screen Recording) before that or when the tap
/// can't start (`SystemAudioBackend`). Both feed `consume(left:right:)`.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let levelLock = NSLock()
    private var level: Double = 0

    /// Guards `stream` and `processTap`, the one running capture (at most one is set); capture
    /// starts and stops on arbitrary tasks.
    private let captureLock = NSLock()
    private var stream: SCStream?
    private var processTap: ProcessTapAudioCapture?

    /// Only touched on the main actor. Never starts a capture that would make macOS prompt:
    /// ScreenCaptureKit shows the Screen Recording prompt itself whenever that grant is missing.
    @MainActor private lazy var permissionGate = AudioCapturePermissionGate(
        preflight: { !Self.backendCandidates().isEmpty },
        isAlertDismissed: { GlobalSettingsViewModel.isAudioPermissionAlertDismissed })
    /// Only touched on the main actor. The single owner of capture starts, so at most one
    /// capture exists app-wide.
    @MainActor private lazy var restartScheduler = CaptureRestartScheduler(
        schedule: { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
        },
        start: { [weak self] in self?.startSystemAudioCapture() })

    /// The consumers that need audio now. Capture runs only while there is one, and stops
    /// `idleGrace` seconds after the last one goes.
    let demand = AudioCaptureDemand(schedule: { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    })

    override init() {
        super.init()
        // Unit tests run ad-hoc signed with this bundle id; a capture request from them is denied
        // and that denial replaces the user's grant for the real app.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { @MainActor [weak self] in self?.setUpSystemAudioCapture() }
    }

    /// The backends a start may try now, without prompting (`SystemAudioBackend.candidates`).
    static func backendCandidates() -> [SystemAudioBackend] {
        let tapSupported = ProcessTapAudioCapture.isSupported
        return SystemAudioBackend.candidates(
            tapSupported: tapSupported,
            tapPermission: tapSupported ? SystemAudioRecordingPermission.status : .notDetermined,
            screenRecordingGranted: CGPreflightScreenCaptureAccess())
    }

    @MainActor
    private func setUpSystemAudioCapture() {
        observeCaptureInterruptions()
        demand.observe { [weak self] active in
            MainActor.assumeIsolated { self?.demandDidChange(active: active) }
        }
        if permissionGate.canCapture() {
            if demand.isDemanded { restartScheduler.requestRestart() }
        } else {
            OWELog.info(.audio, "No system audio permission granted; system audio capture is off.")
            if permissionGate.shouldAlertMissingPermission() {
                NotificationCenter.default.post(name: .audioCapturePermissionMissing, object: nil)
            }
        }
    }

    /// A capture does not survive system sleep, and a ScreenCaptureKit stream not a display
    /// reconfiguration either; nothing else would ever start a new one, so every audio-reactive
    /// feature would stay silent until the app is relaunched. (The process tap watches its own
    /// output device, `ProcessTapAudioCapture.onInterruption`.)
    @MainActor
    private func observeCaptureInterruptions() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    // AppKit posts all three on the main thread.
    @MainActor @objc private func systemDidWake() {
        restartSystemAudioCapture(reason: "system woke")
    }

    /// Only a ScreenCaptureKit stream depends on the displays.
    @MainActor @objc private func screenParametersDidChange() {
        captureLock.lock()
        let usesScreenCapture = stream != nil
        captureLock.unlock()
        guard usesScreenCapture else { return }
        restartSystemAudioCapture(reason: "display configuration changed")
    }

    @MainActor @objc private func applicationDidBecomeActive() {
        recheckCapturePermission()
    }

    /// Starts capture if a permission was granted since the last check. Never prompts, so it is
    /// safe to call whenever the app activates or the Permissions page appears.
    @MainActor
    func recheckCapturePermission() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard permissionGate.becameGranted() else { return }
        OWELog.info(.audio, "System audio permission granted; starting system audio capture.")
        restartScheduler.reset()
        if demand.isDemanded { restartScheduler.requestRestart() }
    }

    /// Starts capture when the first consumer arrives and stops it once the last one has been
    /// gone for the demand's grace period.
    @MainActor
    private func demandDidChange(active: Bool) {
        guard active else { return stopSystemAudioCapture() }
        captureLock.lock()
        let running = stream != nil || processTap != nil
        captureLock.unlock()
        guard !running else { return }
        restartSystemAudioCapture(reason: "a wallpaper needs audio")
    }

    /// Stops the capture and cancels any queued start; the next demand starts a new one.
    @MainActor
    private func stopSystemAudioCapture() {
        restartScheduler.reset()
        let current = takeRunningCapture()
        resetAudioLevels()
        guard current.stream != nil || current.tap != nil else { return }
        OWELog.info(.audio, "No wallpaper needs audio; stopping system audio capture.")
        Task { await Self.stop(current) }
    }

    @MainActor
    private func restartSystemAudioCapture(reason: String) {
        guard demand.isDemanded, permissionGate.canCapture() else { return }
        OWELog.info(.audio, "Restarting system audio capture: \(reason).")
        restartScheduler.requestRestart()
    }

    /// Without this, visuals stay frozen on the last buffer that arrived before capture stopped.
    private func resetAudioLevels() {
        levelLock.lock()
        level = 0
        levelLock.unlock()
        audioSpectrumAnalyzer.reset()
    }

    var audioLevel: Double {
        levelLock.lock()
        defer { levelLock.unlock() }
        return level
    }

    private typealias RunningCapture = (stream: SCStream?, tap: ProcessTapAudioCapture?)

    private func takeRunningCapture() -> RunningCapture {
        captureLock.lock()
        defer { captureLock.unlock() }
        let current = (stream, processTap)
        stream = nil
        processTap = nil
        return current
    }

    private static func stop(_ capture: RunningCapture) async {
        capture.tap?.stop()
        guard let stream = capture.stream else { return }
        do { try await stream.stopCapture() } catch {
            OWELog.debug(.audio, "Stopping capture stream failed: \(error.localizedDescription)")
        }
    }

    /// Called only by `restartScheduler`, which guarantees a single start in flight; the previous
    /// capture is stopped before a new one is created.
    @MainActor
    private func startSystemAudioCapture() {
        let previous = takeRunningCapture()
        resetAudioLevels()
        let candidates = Self.backendCandidates()
        guard !candidates.isEmpty else {
            // Revoked while the start was queued. Touching ScreenCaptureKit now would prompt.
            Task { await Self.stop(previous) }
            restartScheduler.reset()
            restartScheduler.finished(success: true)
            return
        }
        Task { [weak self] in
            await Self.stop(previous)
            let success = await self?.startCapture(trying: candidates) ?? false
            await MainActor.run { [weak self] in
                guard let self else { return }
                // The last consumer left while the capture was starting.
                if success, !self.demand.isDemanded { self.stopSystemAudioCapture() }
                if self.restartScheduler.finished(success: success) {
                    OWELog.error(.audio, "Giving up on system audio capture after \(self.restartScheduler.maxFailures) failed attempts; it restarts on the next wake, display change or permission change.")
                }
            }
        }
    }

    /// Tries each backend in turn; a tap that can't start falls back to ScreenCaptureKit.
    private func startCapture(trying candidates: [SystemAudioBackend]) async -> Bool {
        for backend in candidates {
            switch backend {
            case .processTap:
                if startProcessTap() { return true }
            case .screenCapture:
                if await createAndStartStream() { return true }
            }
        }
        return false
    }

    private func startProcessTap() -> Bool {
        let tap = ProcessTapAudioCapture(
            consume: { [weak self] left, right in self?.consume(left: left, right: right) },
            onInterruption: { [weak self] reason in
                Task { @MainActor [weak self] in self?.restartSystemAudioCapture(reason: reason) }
            })
        do {
            try tap.start()
        } catch {
            OWELog.error(.audio, "Failed to start Core Audio process tap audio capture: \(error)")
            return false
        }
        captureLock.lock()
        processTap = tap
        captureLock.unlock()
        OWELog.info(.audio, "Core Audio process tap audio capture started.")
        return true
    }

    private func createAndStartStream() async -> Bool {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            OWELog.error(.audio, "Unable to read shareable content: \(error.localizedDescription)")
            return false
        }
        guard let display = content.displays.first else {
            OWELog.error(.audio, "No shareable display found for ScreenCaptureKit audio capture.")
            return false
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: Self.streamConfiguration(), delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            // Takes the video frames (one 2×2 frame a second) and drops them at once; without a
            // screen output ScreenCaptureKit logs every frame it has nowhere to send.
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .utility))
            try await stream.startCapture()
        } catch {
            OWELog.error(.audio, "Failed to start ScreenCaptureKit audio capture: \(error.localizedDescription)")
            return false
        }
        setCurrentStream(stream)
        OWELog.info(.audio, "ScreenCaptureKit audio capture started.")
        return true
    }

    /// ScreenCaptureKit has no audio-only stream, so the video side is made as cheap as it gets:
    /// a 2×2 frame at most once a second, without the cursor. The default captures the whole
    /// display at its refresh rate, and an animated wallpaper dirties it every frame.
    static func streamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = Int(CaptureFormatConverter.outputSampleRate)
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        return configuration
    }

    private func setCurrentStream(_ stream: SCStream) {
        captureLock.lock()
        self.stream = stream
        captureLock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureLock.lock()
        let wasCurrent = stream === self.stream
        if wasCurrent { self.stream = nil }
        captureLock.unlock()
        guard wasCurrent else { return }
        OWELog.error(.audio, "ScreenCaptureKit audio capture stopped: \(error.localizedDescription)")
        resetAudioLevels()
        Task { @MainActor [weak self] in self?.restartSystemAudioCapture(reason: "stream stopped") }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        feedScreenCaptureAudio(sampleBuffer)
    }

    // MARK: - Consumers

    /// WE's `g_AudioSpectrum*` source. Fed on the audio thread; the analyzer owns its own lock.
    private let audioSpectrumAnalyzer = AudioSpectrumAnalyzer(sampleRate: CaptureFormatConverter.outputSampleRate)

    /// The latest frame a scene's spectrum clock advanced to, without advancing anything.
    var audioSpectrumSnapshot: AudioSpectrumSnapshot { audioSpectrumAnalyzer.snapshot }

    /// A consumer's own spectrum smoothing over this capture (`AudioSpectrumClock`).
    func makeAudioSpectrumClock(publishes: Bool) -> AudioSpectrumClock {
        audioSpectrumAnalyzer.makeClock(publishes: publishes)
    }

    /// The pipeline both backends feed, on their audio thread: 48 kHz float stereo, one buffer per
    /// channel (`CaptureFormatConverter.outputFormat`). Pass the same buffer twice for mono.
    private func consume(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>) {
        audioSpectrumAnalyzer.ingest(left: left, right: right)
        let sampleCount = left.count + right.count
        guard sampleCount > 0 else { return }
        let squaredSum = Self.sumOfSquares(left) + Self.sumOfSquares(right)
        let normalizedLevel = min(Double(sqrt(squaredSum / Float(sampleCount))) * 8, 1)
        levelLock.lock()
        level = normalizedLevel
        levelLock.unlock()
    }

    private static func sumOfSquares(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard let base = samples.baseAddress, !samples.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_svesq(base, 1, &sum, vDSP_Length(samples.count))
        return sum
    }

    /// Splits the stream's buffer (non-interleaved float32) into its channels for `consume`.
    private func feedScreenCaptureAudio(_ sampleBuffer: CMSampleBuffer) {
        var sizeNeeded = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            blockBufferOut: nil) == noErr, sizeNeeded > 0 else { return }
        let listMemory = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded,
                                                          alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { listMemory.deallocate() }
        let listPointer = listMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlock: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: listPointer, bufferListSize: sizeNeeded,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &retainedBlock)
        guard status == noErr else {
            OWELog.debug(.audio, "Audio buffer list unavailable (status \(status))")
            return
        }
        let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
        func channel(_ buffer: AudioBuffer) -> UnsafeBufferPointer<Float> {
            guard let data = buffer.mData else { return UnsafeBufferPointer(start: nil, count: 0) }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            return UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
        }
        guard let first = buffers.first else { return }
        let left = channel(first)
        let right = buffers.count > 1 ? channel(buffers[1]) : left
        withExtendedLifetime(retainedBlock) {
            consume(left: left, right: right)
        }
    }
}
