import AVFoundation
import CoreAudio

/// System audio through a Core Audio process tap (macOS 14.2+): a global stereo tap, a private
/// aggregate device that reads it, and an IO block that converts each buffer to the consumer
/// pipeline's format (`CaptureFormatConverter`). Needs only the System Audio Recording permission.
///
/// The aggregate holds the tap and nothing else. With the output device as a sub-device, it also
/// carried that device's input streams (a headset's microphone), so the IO block was a client of
/// a microphone and coreaudiod checked the Microphone permission, the same prompt
/// `OutputOnlyAudioDevice` keeps playback from asking for.
///
/// Threading: `start()` and `stop()` are called by one owner, never concurrently (at most one
/// capture exists and `SystemAudioCapture` starts and stops it in turn). The IO block runs on
/// `ioQueue`, which alone touches `converter` and `tapBuffers` while the device runs.
final class ProcessTapAudioCapture {
    /// Receives 48 kHz non-interleaved float stereo (left, right) on the IO queue.
    typealias Consumer = (UnsafeBufferPointer<Float>, UnsafeBufferPointer<Float>) -> Void

    struct StartError: Error, CustomStringConvertible {
        let description: String
    }

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    private let consume: Consumer
    /// Called with a reason when the capture no longer matches the hardware (the default output
    /// device or its sample rate changed) and should be restarted. Runs on an arbitrary queue.
    private let onInterruption: (String) -> Void
    private let ioQueue = DispatchQueue(label: "com.owe.audio.process-tap", qos: .userInteractive)
    private let listenerQueue = DispatchQueue(label: "com.owe.audio.process-tap-listeners")

    /// Set by `start()`, cleared by `stop()`; `stop()` does nothing while it's false, so the
    /// `deinit` after an explicit `stop()` never waits on the IO queue.
    private var isStarted = false
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var listeners: [(object: AudioObjectID, address: AudioObjectPropertyAddress,
                             block: AudioObjectPropertyListenerBlock)] = []

    // IO queue only while the device runs.
    private var converter: CaptureFormatConverter?

    init(consume: @escaping Consumer, onInterruption: @escaping (String) -> Void) {
        self.consume = consume
        self.onInterruption = onInterruption
    }

    deinit {
        stop()
    }

    /// Throws, with everything already torn down, when any step fails.
    func start() throws {
        guard #available(macOS 14.2, *) else {
            throw StartError(description: "process taps need macOS 14.2")
        }
        isStarted = true
        do {
            try startTap()
        } catch {
            stop()
            throw error
        }
    }

    @available(macOS 14.2, *)
    private func startTap() throws {
        let description = Self.tapDescription()
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create the process tap")
        try check(AudioHardwareCreateAggregateDevice(
            Self.aggregateDescription(tapUID: description.uuid.uuidString) as CFDictionary, &aggregateID),
                  "create the aggregate device")

        var streamDescription: AudioStreamBasicDescription = try Self.property(
            tapID, kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
        // The tap clocks the aggregate, so the two rates agree. Reading the device's is optional:
        // the tap's own rate is the fallback.
        if let rate: Float64 = try? Self.property(aggregateID, kAudioDevicePropertyNominalSampleRate,
                                                  default: Float64(0)), rate > 0 {
            streamDescription.mSampleRate = rate
        }
        guard let format = AVAudioFormat(streamDescription: &streamDescription),
              let converter = CaptureFormatConverter(inputFormat: format) else {
            throw StartError(description: "unsupported tap format \(streamDescription)")
        }
        self.converter = converter

        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }, "create the IO block")
        // A global tap follows the default output device, and takes its format.
        addListener(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                    reason: "the default output device changed")
        addListener(tapID, kAudioTapPropertyFormat, reason: "the tap's format changed")
        addListener(aggregateID, kAudioDevicePropertyNominalSampleRate, reason: "the output sample rate changed")
        addListener(aggregateID, kAudioDevicePropertyDeviceIsAlive, reason: "the output device went away")
        try check(AudioDeviceStart(aggregateID, ioProcID), "start the aggregate device")
    }

    /// Every process's output, including this app's own sounds: WE's loopback capture hears its
    /// own wallpapers too, and the ScreenCaptureKit path keeps `excludesCurrentProcessAudio` off.
    /// Private, so no other app sees the tap; unmuted, so playback is untouched.
    @available(macOS 14.2, *)
    static func tapDescription() -> CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Open Wallpaper Engine system audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }

    /// A private aggregate device whose only stream is the tap, which clocks it: no sub-device, so
    /// no device's input streams (a microphone) come with it. Nothing else clocks it, so the tap
    /// needs no drift compensation.
    static func aggregateDescription(tapUID: String) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "Open Wallpaper Engine system audio",
            kAudioAggregateDeviceUIDKey: "com.owe.audio.process-tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID]]
        ]
    }

    /// Stops and destroys everything `start()` created. Safe to call more than once.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        for listener in listeners {
            var address = listener.address
            let status = AudioObjectRemovePropertyListenerBlock(listener.object, &address, listenerQueue, listener.block)
            if status != noErr { OWELog.debug(.audio, "Removing a process tap listener failed (status \(status))") }
        }
        listeners = []
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                logFailure(AudioDeviceStop(aggregateID, ioProcID), "stop the aggregate device")
                logFailure(AudioDeviceDestroyIOProcID(aggregateID, ioProcID), "destroy the IO block")
            }
            logFailure(AudioHardwareDestroyAggregateDevice(aggregateID), "destroy the aggregate device")
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown {
            logFailure(AudioHardwareDestroyProcessTap(tapID), "destroy the process tap")
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
        // The device is stopped, so this drains the last IO block before its converter goes away.
        ioQueue.sync { converter = nil }
    }

    // MARK: - IO

    /// The aggregate's input is the tap's buffers alone (`aggregateDescription`).
    private func process(_ input: UnsafePointer<AudioBufferList>) {
        guard let converter else { return }
        let format = converter.inputFormat
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard buffers.count == Int(format.isInterleaved ? 1 : format.channelCount), let first = buffers.first else { return }
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        guard bytesPerFrame > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
        pcm.frameLength = min(first.mDataByteSize / bytesPerFrame, pcm.frameCapacity)
        guard let output = converter.convert(pcm), let channels = output.floatChannelData else { return }
        let count = Int(output.frameLength)
        consume(UnsafeBufferPointer(start: channels[0], count: count),
                UnsafeBufferPointer(start: channels[1], count: count))
    }

    // MARK: - Core Audio helpers

    private func addListener(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, reason: String) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onInterruption(reason) }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, listenerQueue, block)
        guard status == noErr else {
            OWELog.error(.audio, "Unable to watch for \(reason) (status \(status)); the process tap won't follow it.")
            return
        }
        listeners.append((object, address, block))
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                    default value: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else {
            throw StartError(description: "reading property \(Self.fourCharacterCode(selector)) failed (status \(status))")
        }
        return result
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw StartError(description: "unable to \(step) (status \(status))") }
    }

    private func logFailure(_ status: OSStatus, _ step: String) {
        guard status != noErr else { return }
        OWELog.debug(.audio, "Process tap teardown: unable to \(step) (status \(status))")
    }

    private static func fourCharacterCode(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
        return String(bytes: bytes, encoding: .ascii) ?? String(value)
    }
}
