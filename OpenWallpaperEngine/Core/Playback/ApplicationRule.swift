import Foundation

/// Settings › Performance › Application Rules: WE's per-application playback rules. Each rule
/// names an application (by bundle identifier, as WE names it by its executable) and what the
/// wallpaper does while that application meets the rule's condition.
///
/// WE's actions are pause, stop and mute, plus switching to another performance profile. This app
/// offers the playback actions it performs (`GSPlayback`: mute, pause per display, pause all,
/// stop); it has no performance profiles to switch to, so that action isn't offered.
struct ApplicationRule: Codable, Equatable, Identifiable {
    /// When a rule applies.
    enum Condition: String, Codable, CaseIterable, Identifiable {
        var id: Self { self }
        /// The application is running: acts on every display.
        case running
        /// The application is the active one: acts on the display its front window is on.
        case focused
        /// One of the application's windows fills a display (full screen or maximized): acts on
        /// that display.
        case fullscreen

        /// The condition looks at windows, so the window list has to be read.
        var watchesWindows: Bool { self != .running }
    }

    var id = UUID()
    /// The application's bundle identifier, e.g. `com.apple.FinalCut`.
    var bundleIdentifier: String
    /// The application's name when it was picked, shown while it isn't installed.
    var name: String
    var condition = Condition.running
    var action = GSPlayback.pause
    var isEnabled = true

    init(id: UUID = UUID(), bundleIdentifier: String, name: String, condition: Condition = .running,
         action: GSPlayback = .pause, isEnabled: Bool = true) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.condition = condition
        self.action = action
        self.isEnabled = isEnabled
    }

    /// Whether the rule can act at all.
    var isActive: Bool { isEnabled && action != .keepRunning && !bundleIdentifier.isEmpty }
}

extension ApplicationRule {
    enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, name, condition, action, isEnabled
    }

    /// A rule needs its application; any other field that is missing or unknown keeps its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        self.init(bundleIdentifier: bundleIdentifier, name: bundleIdentifier)
        func read<Value: Decodable>(_ key: CodingKeys, _ value: inout Value) {
            do {
                if let stored = try container.decodeIfPresent(Value.self, forKey: key) { value = stored }
            } catch {
                OWELog.error(.settings, "Application rule \(bundleIdentifier): \(key.stringValue) can't be read and keeps its default: \(error)")
            }
        }
        read(.id, &id)
        read(.name, &name)
        read(.condition, &condition)
        read(.action, &action)
        read(.isEnabled, &isEnabled)
    }
}

/// Reads stored application rules one at a time, so one unreadable rule doesn't drop the others.
struct ApplicationRuleList: Decodable {
    var rules: [ApplicationRule] = []

    init() {}

    init(from decoder: Decoder) throws {
        rules = try [Element](from: decoder).compactMap(\.rule)
    }

    private struct Element: Decodable {
        var rule: ApplicationRule?

        init(from decoder: Decoder) throws {
            do {
                rule = try ApplicationRule(from: decoder)
            } catch {
                OWELog.error(.settings, "An application rule can't be read and is left out: \(error)")
                rule = nil
            }
        }
    }
}
