import AVFoundation
import CoreAudio

/// Plays an `AVAudioEngine` in realtime manual rendering mode on an `OutputOnlyAudioDevice`: an IO
/// proc on the device pulls the engine's frames (`manualRenderingBlock`), resampled when the
/// device runs at another rate, and copies them to the device's first two channels. The engine
/// never makes its own hardware output, whose `AUHAL` would open the default output device with
/// its inputs (see `OutputOnlyAudioDevice`).
///
/// Threading: the IO proc is made, started, stopped and destroyed on `queue`, never on the caller's
/// thread (the render thread), so a HAL call that waits on coreaudiod never stalls a frame or a
/// wallpaper change. The IO proc runs on the HAL's IO thread and touches only `Renderer`, which
/// `queue` replaces only while the IO proc is stopped.
final class ManualRenderingOutput {
    /// The most frames one call of the engine's block renders (`enableManualRenderingMode`).
    static let maximumFrameCount: AVAudioFrameCount = 4096

    private let queue = DispatchQueue(label: "com.owe.audio.manual-output", qos: .userInitiated)
    private let device: OutputOnlyAudioDevice
    private let render: AVAudioEngineManualRenderingBlock
    private let format: AVAudioFormat
    private let label: String

    // Queue only.
    private var wantsRunning = false
    private var ioDevice = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var renderer: Renderer?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var rateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                         mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)

    /// `render` is the engine's block and `format` its manual rendering format (stereo floats).
    init(device: OutputOnlyAudioDevice, render: @escaping AVAudioEngineManualRenderingBlock, format: AVAudioFormat,
         label: String) {
        self.device = device
        self.render = render
        self.format = format
        self.label = label
    }

    /// Starts or stops the IO proc, on the output's queue.
    func setRunning(_ running: Bool) {
        queue.async { [self] in
            guard running != wantsRunning else { return }
            wantsRunning = running
            if running { start() } else { stop() }
        }
    }

    /// Stops and destroys the IO proc, then runs `completion` on the output's queue (the engine
    /// may go then: nothing pulls from it any more).
    func shutdown(then completion: @escaping () -> Void) {
        queue.async { [self] in
            wantsRunning = false
            stop()
            completion()
        }
    }

    // MARK: - Queue only

    private func start() {
        guard ioProcID == nil else { return }
        guard let id = device.deviceID else { return } // Logged by the device.
        let rate = OutputOnlyAudioDevice.nominalSampleRate(of: id)
        guard rate > 0, let renderer = Renderer(render: render, format: format, deviceRate: rate) else {
            OWELog.error(.audio, "\(label): the output device's rate (\(rate) Hz) can't be played; sound layers stay silent.")
            return
        }
        var procID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, id, nil) { _, _, _, output, _ in
            renderer.fill(output)
        }
        guard status == noErr, let procID else {
            OWELog.error(.audio, "\(label): can't open the output device (status \(status)); sound layers stay silent.")
            return
        }
        status = AudioDeviceStart(id, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(id, procID)
            OWELog.error(.audio, "\(label): can't start the output device (status \(status)); sound layers stay silent.")
            return
        }
        ioDevice = id
        ioProcID = procID
        self.renderer = renderer
        // The device follows the default output device, whose rate may differ: start again at it.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rateDidChange() }
        if AudioObjectAddPropertyListenerBlock(id, &rateAddress, queue, listener) == noErr { rateListener = listener }
    }

    private func stop() {
        guard let ioProcID else { return }
        if let rateListener {
            AudioObjectRemovePropertyListenerBlock(ioDevice, &rateAddress, queue, rateListener)
            self.rateListener = nil
        }
        AudioDeviceStop(ioDevice, ioProcID)
        AudioDeviceDestroyIOProcID(ioDevice, ioProcID)
        self.ioProcID = nil
        ioDevice = AudioObjectID(kAudioObjectUnknown)
        renderer = nil
    }

    private func rateDidChange() {
        guard wantsRunning, let renderer, renderer.deviceRate != OutputOnlyAudioDevice.nominalSampleRate(of: ioDevice) else { return }
        stop()
        start()
    }

    // MARK: - IO

    /// Fills the device's buffers from the engine; IO thread only once made. Its buffers are made
    /// up front, so a callback allocates nothing.
    final class Renderer: @unchecked Sendable {
        let deviceRate: Float64
        private let render: AVAudioEngineManualRenderingBlock
        /// The engine's frames.
        private let engineBuffer: AVAudioPCMBuffer
        /// At the device's rate, when it differs from the engine's (the device moved to another
        /// output device after the engine was made).
        private let converter: AVAudioConverter?
        private let deviceBuffer: AVAudioPCMBuffer?
        /// `deviceBuffer`'s memory, framed to one callback's frames (the converter fills a buffer
        /// to its capacity).
        private let deviceList: UnsafeMutableAudioBufferListPointer?

        init?(render: @escaping AVAudioEngineManualRenderingBlock, format: AVAudioFormat, deviceRate: Float64) {
            guard format.channelCount == 2, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
                  let engineBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: ManualRenderingOutput.maximumFrameCount)
            else { return nil }
            self.render = render
            self.deviceRate = deviceRate
            self.engineBuffer = engineBuffer
            if deviceRate == format.sampleRate {
                converter = nil
                deviceBuffer = nil
                deviceList = nil
            } else {
                guard let deviceFormat = AVAudioFormat(standardFormatWithSampleRate: deviceRate, channels: 2),
                      let converter = AVAudioConverter(from: format, to: deviceFormat),
                      let deviceBuffer = AVAudioPCMBuffer(pcmFormat: deviceFormat, frameCapacity: ManualRenderingOutput.maximumFrameCount)
                else { return nil }
                self.converter = converter
                self.deviceBuffer = deviceBuffer
                deviceList = AudioBufferList.allocate(maximumBuffers: 2)
            }
        }

        deinit {
            if let deviceList { free(deviceList.unsafeMutablePointer) }
        }

        func fill(_ output: UnsafeMutablePointer<AudioBufferList>) {
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            guard let first = buffers.first, first.mNumberChannels > 0 else { return }
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * Int(first.mNumberChannels))
            var done = 0
            while done < frames {
                let chunk = min(frames - done, Int(ManualRenderingOutput.maximumFrameCount))
                let source = produce(AVAudioFrameCount(chunk))
                Self.copy(source, frames: chunk, into: buffers, at: done)
                done += chunk
            }
        }

        /// `frames` frames at the device's rate, silence where the engine renders nothing (paused).
        private func produce(_ frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
            guard let converter, let deviceBuffer, let deviceList, let channels = deviceBuffer.floatChannelData else {
                return renderEngine(frames) ? engineBuffer : nil
            }
            let bytes = UInt32(Int(frames) * MemoryLayout<Float>.size)
            for index in 0..<2 { deviceList[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: channels[index]) }
            guard let framed = AVAudioPCMBuffer(pcmFormat: deviceBuffer.format, bufferListNoCopy: deviceList.unsafePointer,
                                                deallocator: nil) else { return nil }
            var failed = false
            let status = converter.convert(to: framed, error: nil) { [self] packets, inputStatus in
                guard renderEngine(min(packets, ManualRenderingOutput.maximumFrameCount)) else {
                    failed = true
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return engineBuffer
            }
            return failed || status == .error ? nil : framed
        }

        private func renderEngine(_ frames: AVAudioFrameCount) -> Bool {
            engineBuffer.frameLength = frames
            var error: OSStatus = noErr
            let status = render(frames, engineBuffer.mutableAudioBufferList, &error)
            return status == .success
        }

        /// Left and right into the device's first two channels (both into a mono one), interleaved
        /// or not; every other channel, and anything missing, is silence.
        static func copy(_ source: AVAudioPCMBuffer?, frames: Int, into buffers: UnsafeMutableAudioBufferListPointer, at offset: Int) {
            let available = source.map { min(Int($0.frameLength), frames) } ?? 0
            let left = source?.floatChannelData?[0], right = source?.floatChannelData?[1]
            var channelIndex = 0
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = Int(buffer.mNumberChannels)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        let index = (offset + frame) * channels + channel
                        guard frame < available, let left, let right else {
                            data[index] = 0
                            continue
                        }
                        switch (channelIndex + channel, channels == 1 && buffers.count == 1) {
                        case (_, true): data[index] = (left[frame] + right[frame]) / 2
                        case (0, _): data[index] = left[frame]
                        case (1, _): data[index] = right[frame]
                        default: data[index] = 0
                        }
                    }
                }
                channelIndex += channels
            }
        }
    }
}
