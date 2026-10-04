import Foundation

/// Reads and writes the system preferences theming changes. Everything that would change the Mac's
/// settings goes through it, so tests use a fake and an isolated copy of the app a writer that
/// never writes (`ReadOnlyAppearanceWriter`).
public protocol SystemAppearanceWriter: AnyObject {
    /// The stored value; nil when the key is absent (the system default).
    func value(for key: SystemPreferenceKey) -> PreferenceValue?
    /// Stores `value`, or removes the key for nil.
    func setValue(_ value: PreferenceValue?, for key: SystemPreferenceKey)
    /// Tells running apps that `change` happened, after the values are stored.
    func post(_ change: SystemAppearanceChange)
}

/// The real writer: the current user's global preferences through CFPreferences, and the
/// distributed notification System Settings posts.
public final class GlobalPreferencesWriter: SystemAppearanceWriter {
    public init() {}

    public func value(for key: SystemPreferenceKey) -> PreferenceValue? {
        let stored: CFPropertyList? = CFPreferencesCopyValue(key.rawValue as CFString, kCFPreferencesAnyApplication,
                                                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return Self.decode(stored)
    }

    public func setValue(_ value: PreferenceValue?, for key: SystemPreferenceKey) {
        let stored: CFPropertyList?
        switch value {
        case .integer(let number): stored = number as NSNumber
        case .string(let text): stored = text as NSString
        case nil: stored = nil
        }
        CFPreferencesSetValue(key.rawValue as CFString, stored, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    public func post(_ change: SystemAppearanceChange) {
        switch change {
        case .colorPreferences:
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("AppleColorPreferencesChangedNotification"), object: nil, userInfo: nil,
                deliverImmediately: true)
        case .iconAppearance:
            // No public notification; the Dock reads the style when it starts (docs/theming.md).
            break
        }
    }

    static func decode(_ stored: CFPropertyList?) -> PreferenceValue? {
        if let text = stored as? String { return .string(text) }
        if let number = stored as? NSNumber { return .integer(number.intValue) }
        return nil
    }
}

/// Reads the real preferences and writes nothing: an isolated copy of the app (tests, screenshots)
/// computes and logs what it would do without changing the Mac.
public final class ReadOnlyAppearanceWriter: SystemAppearanceWriter {
    private let reader = GlobalPreferencesWriter()
    /// What would have been written, last value per key.
    public private(set) var skipped: [SystemPreferenceKey: PreferenceValue?] = [:]

    public init() {}

    public func value(for key: SystemPreferenceKey) -> PreferenceValue? {
        if let skippedValue = skipped[key] { return skippedValue }
        return reader.value(for: key)
    }

    public func setValue(_ value: PreferenceValue?, for key: SystemPreferenceKey) {
        skipped[key] = .some(value)
    }

    public func post(_ change: SystemAppearanceChange) {}
}
