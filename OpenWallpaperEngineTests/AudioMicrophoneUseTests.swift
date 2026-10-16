import AVFoundation
import CoreAudio
import XCTest
@testable import OpenWallpaperEngine

/// With the default "Audio recording device" (the system output), nothing the app does with
/// sound may ask for the microphone. A client of a device that also records (a headset) makes
/// coreaudiod check the Microphone permission, so wallpaper sound plays on the default output
/// device without its inputs (`OutputOnlyAudioDevice`), the scene engine never makes its own
/// hardware output, and only a chosen recording device is ever recorded.
final class AudioMicrophoneUseTests: XCTestCase {
    func testTheDefaultSettingNeverRecordsAnInputDevice() {
        for permission in [SystemAudioRecordingPermission.Status.authorized, .unknown, .notDetermined, .denied] {
            for screenRecording in [true, false] {
                let candidates = SystemAudioBackend.candidates(tapSupported: true, tapPermission: permission,
                                                               screenRecordingGranted: screenRecording,
                                                               inputDevice: nil, microphoneGranted: true)
                XCTAssertFalse(candidates.contains { if case .inputDevice = $0 { return true } else { return false } },
                               "\(permission), screen recording \(screenRecording): \(candidates)")
            }
        }
    }

    func testWallpaperSoundPlaysOnAStackedDeviceWithOnlyTheOutput() throws {
        let description = OutputOnlyAudioDevice.aggregateDescription(outputUID: "headset", uid: "owe-output")
        XCTAssertEqual(description[kAudioAggregateDeviceIsStackedKey] as? Bool, true, "a stack exposes only its sub-devices' outputs")
        XCTAssertEqual(description[kAudioAggregateDeviceIsPrivateKey] as? Bool, true)
        XCTAssertEqual(description[kAudioAggregateDeviceMainSubDeviceKey] as? String, "headset")
        let subDevices = try XCTUnwrap(description[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]])
        XCTAssertEqual(subDevices.map { $0[kAudioSubDeviceUIDKey] as? String }, ["headset"])
        XCTAssertNil(description[kAudioAggregateDeviceTapListKey], "no tap: nothing is recorded")
    }

    /// The real device, on a Mac with an output device: it has no input stream for coreaudiod to
    /// check the microphone for, whatever the default output device records.
    func testTheOutputOnlyDeviceHasNoInputs() throws {
        let device = OutputOnlyAudioDevice()
        guard let id = device.deviceID else { throw XCTSkip("no output device on this Mac") }
        XCTAssertEqual(OutputOnlyAudioDevice.inputStreamCount(of: id), 0)
        XCTAssertNotNil(device.sampleRate)
        let player = WallpaperAVPlayer.make(output: device)
        XCTAssertEqual(player.audioOutputDeviceUniqueID, device.uid, "video wallpapers play on it too")
    }

    /// The test host is the app: its video players play on the output-only device too, or every
    /// freshly signed test build asked for the microphone on a Mac whose output is a headset.
    /// Scene sound layers stay silent or offline in tests.
    @MainActor
    func testTheTestHostsPlayersUseTheOutputOnlyDevice() throws {
        let services = WallpaperServices.shared
        XCTAssertNil(services.sceneSoundOutput, "sound layers never play live in a test host")
        guard let output = services.soundOutput, let id = output.deviceID else { throw XCTSkip("no output device on this Mac") }
        XCTAssertEqual(OutputOnlyAudioDevice.inputStreamCount(of: id), 0)
        XCTAssertEqual(WallpaperAVPlayer.make().audioOutputDeviceUniqueID, output.uid)
        XCTAssertEqual(VideoLoop().player.audioOutputDeviceUniqueID, output.uid, "muted previews are routed too")
    }

    /// Every player the app makes is routed (`WallpaperAVPlayer`): a file that makes an `AVPlayer`
    /// or an `AVQueuePlayer` routes it.
    func testEveryPlayerTheAppMakesIsRouted() throws {
        let sources = AppIdentityLintTests.repository.appending(path: "OpenWallpaperEngine")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("AVPlayer(") || text.contains("AVQueuePlayer(") else { continue }
            checked += 1
            XCTAssertTrue(text.contains("WallpaperAVPlayer.route(") || url.lastPathComponent == "WallpaperAVPlayer.swift",
                          "\(url.lastPathComponent) makes a player without routing it to the output-only device")
        }
        XCTAssertGreaterThan(checked, 0)
    }

    /// The scene engine renders manually, so it never opens the default output device itself.
    func testSceneSoundNeverMakesItsOwnHardwareOutput() {
        let live = SceneSoundMixer(label: "test", device: nil)
        XCTAssertTrue(live.engine.isInManualRenderingMode)
        XCTAssertEqual(live.engine.manualRenderingMode, .realtime)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        let offline = SceneSoundMixer(label: "test", offline: format, device: nil)
        XCTAssertEqual(offline.engine.manualRenderingMode, .offline)
    }

    /// The output copies left and right into the device's first two channels, silence elsewhere.
    func testTheOutputCopiesStereoIntoTheDevicesChannels() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        source.frameLength = 4
        for frame in 0..<4 {
            source.floatChannelData![0][frame] = 1
            source.floatChannelData![1][frame] = 0.5
        }
        // One interleaved buffer of four channels, two frames written at frame 1.
        var samples = [Float](repeating: 9, count: 3 * 4)
        samples.withUnsafeMutableBytes { bytes in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 4, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
            ManualRenderingOutput.Renderer.copy(source, frames: 2, into: list, at: 1)
        }
        XCTAssertEqual(Array(samples[0..<4]), [9, 9, 9, 9], "frames before the offset are untouched")
        XCTAssertEqual(Array(samples[4..<12]), [1, 0.5, 0, 0, 1, 0.5, 0, 0])
        // Nothing rendered (the engine paused): silence.
        var silent = [Float](repeating: 9, count: 2)
        silent.withUnsafeMutableBytes { bytes in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
            ManualRenderingOutput.Renderer.copy(nil, frames: 2, into: list, at: 0)
        }
        XCTAssertEqual(silent, [0, 0])
    }
}
