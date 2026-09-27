import CoreAudio
import Foundation

/// Whether an application other than this one plays sound, from Core Audio's process objects
/// (macOS 14.2 and later; earlier systems report none).
final class OtherApplicationAudio {
    private let ownPID: pid_t
    private var reportedFailure = false

    init(ownPID: pid_t) {
        self.ownPID = ownPID
    }

    /// `ignoringWebKit` leaves out WebKit's helper processes, which play web wallpapers' sound.
    func isPlaying(ignoringWebKit: Bool) -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let processes: [AudioObjectID] = array(system, kAudioHardwarePropertyProcessObjectList) else { return false }
        for process in processes {
            guard let pid: pid_t = value(process, kAudioProcessPropertyPID), pid != ownPID,
                  let running: UInt32 = value(process, kAudioProcessPropertyIsRunningOutput), running != 0 else { continue }
            if ignoringWebKit, bundleID(of: process)?.hasPrefix("com.apple.WebKit") == true { continue }
            return true
        }
        return false
    }

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func array(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
        var address = address(selector)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard status == noErr else { return failed(selector, status) }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids)
        guard status == noErr else { return failed(selector, status) }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private func value<Value: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Value? {
        var address = address(selector)
        var result: Value = 0
        var size = UInt32(MemoryLayout<Value>.size)
        // A process that quits between the list and this read has no properties: not a failure.
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result
    }

    private func bundleID(of process: AudioObjectID) -> String? {
        guard #available(macOS 14.2, *) else { return nil }
        var address = address(kAudioProcessPropertyBundleID)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result?.takeRetainedValue() as String?
    }

    private func failed<Result>(_ selector: AudioObjectPropertySelector, _ status: OSStatus) -> Result? {
        if !reportedFailure {
            reportedFailure = true
            OWELog.error(.audio, "Core Audio's process list can't be read (\(selector), status \(status)); \"Other application playing audio\" sees no audio")
        }
        return nil
    }
}
