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
    /// Listener queue only. Cleared by `stop()`: Core Audio still runs a removed listener for a
    /// notification it already queued, and destroying the aggregate queues one (it's no longer
    /// alive). That one arrived while `SystemAudioCapture` was starting the next capture and
    /// restarted it again, so the capture was rebuilt every couple of seconds.
    private var listenersActive = true

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
        let tapFormat = StreamFormat(streamDescription)
        // The tap clocks the aggregate, so the two rates agree. Reading the device's is optional:
        // the tap's own rate is the fallback.
        let aggregateRate: Float64? = try? Self.property(aggregateID, kAudioDevicePropertyNominalSampleRate,
                                                         default: Float64(0))
        if let aggregateRate, aggregateRate > 0 {
            streamDescription.mSampleRate = aggregateRate
        }
        guard let format = AVAudioFormat(streamDescription: &streamDescription),
              let converter = CaptureFormatConverter(inputFormat: format) else {
            throw StartError(description: "unsupported tap format \(streamDescription)")
        }
        self.converter = converter

        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }, "create the IO block")
        addListeners(tapFormat: tapFormat, aggregateRate: aggregateRate)
        try check(AudioDeviceStart(aggregateID, ioProcID), "start the aggregate device")
    }

    /// Watches what the capture was built for. Core Audio also sends these notifications when
    /// nothing changed: adding or removing the private aggregate makes coreaudiod look for its
    /// default devices again, which notifies the default output device's listeners. A restart on
    /// that one builds a new aggregate, which notifies again, and the capture is rebuilt every
    /// couple of seconds, stalling coreaudiod. So each listener reads the value again and only
    /// reports one that differs from the value at start (`isInterruption`).
    @available(macOS 14.2, *)
    private func addListeners(tapFormat: StreamFormat, aggregateRate: Float64?) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let tap = tapID
        let aggregate = aggregateID
        // A global tap follows the default output device, and takes its format.
        let outputDevice = ProcessTapAudioCapture.outputDevice()
        addListener(system, kAudioHardwarePropertyDefaultOutputDevice, reason: "the default output device changed") {
            ProcessTapAudioCapture.isInterruption(atStart: outputDevice, now: ProcessTapAudioCapture.outputDevice())
        }
        addListener(tap, kAudioTapPropertyFormat, reason: "the tap's format changed") {
            let now = try? ProcessTapAudioCapture.property(tap, kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
            return ProcessTapAudioCapture.isInterruption(atStart: tapFormat, now: now.map(StreamFormat.init))
        }
        addListener(aggregate, kAudioDevicePropertyNominalSampleRate, reason: "the output sample rate changed") {
            ProcessTapAudioCapture.isInterruption(atStart: aggregateRate,
                                now: try? ProcessTapAudioCapture.property(aggregate, kAudioDevicePropertyNominalSampleRate, default: Float64(0)))
        }
        addListener(aggregate, kAudioDevicePropertyDeviceIsAlive, reason: "the output device went away") {
            ProcessTapAudioCapture.isInterruption(atStart: UInt32(1),
                                now: try? ProcessTapAudioCapture.property(aggregate, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0)))
        }
    }

    /// The parts of a stream format the capture's converter is built from.
    struct StreamFormat: Equatable {
        let sampleRate: Float64
        let formatID: AudioFormatID
        let formatFlags: AudioFormatFlags
        let bytesPerFrame: UInt32
        let channelsPerFrame: UInt32
        let bitsPerChannel: UInt32

        init(_ description: AudioStreamBasicDescription) {
            sampleRate = description.mSampleRate
            formatID = description.mFormatID
            formatFlags = description.mFormatFlags
            bytesPerFrame = description.mBytesPerFrame
            channelsPerFrame = description.mChannelsPerFrame
            bitsPerChannel = description.mBitsPerChannel
        }
    }

    /// Whether a property notification means the capture no longer matches the hardware: the
    /// value differs from the one the capture started with. A value that can't be read any more
    /// (nil, its object is gone) differs from one that could.
    static func isInterruption<Value: Equatable>(atStart: Value?, now: Value?) -> Bool {
        atStart != now
    }

    private static func outputDevice() -> AudioObjectID? {
        try? property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                      default: AudioObjectID(kAudioObjectUnknown))
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
        listenerQueue.sync { listenersActive = false }
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

    /// `changed` runs on the listener queue; it must not touch the capture's own state.
    private func addListener(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, reason: String,
                             changed: @escaping @Sendable () -> Bool) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.listenersActive, changed() else { return }
            self.onInterruption(reason)
        }
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
