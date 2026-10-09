import Foundation
import OWEControlProtocol

/// The screen saver: Scene Edit / Export's Screen Saver mode (its layer and property choices,
/// Record and Set as Screen Saver, Stop Using as Screen Saver) and the daily re-recording.
extension SystemControlRequests {
    /// Choosing it in macOS is the user's: OWE only opens that pane for them.
    static let pickInSystemSettings = "To use it, pick \"Open Wallpaper Engine\" in System Settings › Screen Saver if it isn't your screen saver yet."

    func screenSaver(_ params: ControlParameters, lookup: ControlLookup) throws -> JSONValue {
        let state = service.screenSaver
        var result: [String: JSONValue] = [
            "plugin_enabled": .bool(state.pluginEnabled),
            "recording": .bool(state.isRecording),
            "selection": state.selection.map(Self.json) ?? .null,
            "schedule": Self.json(service.schedule),
        ]
        var message = state.pluginEnabled ? "The Screen Saver plugin is on" : "The Screen Saver plugin is off"
        if let selection = state.selection {
            message += "; \(selection.wallpaper.map { "\"\($0.title)\"" } ?? "a wallpaper no longer in the library")'s recording of \(selection.recorded.formatted(date: .abbreviated, time: .shortened)) is the screen saver."
        } else {
            message += state.pluginEnabled ? "; it loops the desktop's wallpaper (no recording is set as the screen saver)." : "."
        }
        if state.isRecording { message += " A recording is running." }
        if let id = try params.string("wallpaper_id") {
            let wallpaper = try lookup.wallpaper(id)
            result["wallpaper"] = try screenSaverWallpaper(wallpaper, selection: state.selection)
        }
        result["message"] = .string(message + " " + Self.pickInSystemSettings)
        return .object(result)
    }

    /// The wallpaper's screen saver version: its layers as the screen saver shows them and its
    /// user properties, from the screen saver's own choices or the wallpaper's values.
    private func screenSaverWallpaper(_ wallpaper: ControlWallpaper, selection: SystemScreenSaverSelection?) throws -> JSONValue {
        var object: [String: JSONValue] = ["wallpaper": ControlLookup.json(wallpaper)]
        let isSelected = selection?.wallpaper.map { $0.folder.standardizedFileURL == wallpaper.folder.standardizedFileURL } ?? false
        object["is_screen_saver"] = .bool(isSelected)
        guard wallpaper.type == "scene" else {
            object["eligible"] = false
            return .object(object)
        }
        object["eligible"] = true
        let values = try service.screenSaverValues(of: wallpaper)
        object["own_choices"] = .bool(values.isOwn)
        object["layers"] = .array(try service.layers(of: wallpaper).map { Self.json($0, values: values.values) })
        let properties = WallpaperPropertyReset.values(removingSceneInspectorEditsFrom: values.values)
        object["properties"] = .object(properties.mapValues { .string($0) })
        return .object(object)
    }

    /// The mode's layer switches and user properties, saved as the screen saver's own choices.
    func setScreenSaverLayers(_ params: ControlParameters, lookup: ControlLookup) throws -> JSONValue {
        let wallpaper = try lookup.sceneWallpaper(params.required("wallpaper_id"))
        let layerItems = try params.objects("layers")
        let propertyItems = try params.objects("properties")
        guard !layerItems.isEmpty || !propertyItems.isEmpty else {
            throw ControlError(.invalidParams, "Give layers to show or hide, properties to set, or both.")
        }
        let layers = try service.layers(of: wallpaper)
        var changes: [String: String] = [:]
        var described: [String] = []
        for item in layerItems {
            let layer = try Self.layer(try item.required("layer"), in: layers, wallpaper: wallpaper)
            let visible = try item.requiredBool("visible")
            changes[sceneObjectVisibilityKey(objectID: layer.id)] = visible ? "true" : "false"
            described.append("\(visible ? "showed" : "hid") \"\(layer.name)\"")
        }
        if !propertyItems.isEmpty {
            let properties = lookup.model.properties(of: wallpaper)
            for item in propertyItems {
                let key = try item.required("key")
                guard let property = properties.first(where: { $0.key == key }) else {
                    let keys = properties.filter { !["text", "group", ""].contains($0.type) }.map(\.key).sorted().joined(separator: ", ")
                    throw ControlError(.notFound, "\"\(wallpaper.title)\" has no user property \"\(key)\". "
                                       + (keys.isEmpty ? "It has none to set." : "Its properties: \(keys)."))
                }
                guard let value = item.raw["value"] else { throw ControlError(.invalidParams, "properties: \(key) needs a value.") }
                let stored = try ControlUserPropertyValue.stored(value, for: property)
                changes[key] = stored
                described.append("set \(key) to \(stored)")
            }
        }
        var values = try service.screenSaverValues(of: wallpaper).values
        values.merge(changes) { _, new in new }
        let saved = try service.setScreenSaverValues(values, of: wallpaper)
        let message = saved
            ? "Saved the screen saver's choices for \"\(wallpaper.title)\": \(Self.sentenceList(described)). The desktop is unchanged; the next recording (screensaver_record, or the daily re-recording when this is the screen saver) uses them."
            : "These are \"\(wallpaper.title)\"'s own values, which the screen saver follows until its choices differ, so nothing was saved."
        return [
            "wallpaper": ControlLookup.json(wallpaper),
            "saved": .bool(saved),
            "layers": .array(layers.map { Self.json($0, values: values) }),
            "properties": .object(WallpaperPropertyReset.values(removingSceneInspectorEditsFrom: values).mapValues { .string($0) }),
            "message": .string(message),
        ]
    }

    func recordScreenSaver(_ params: ControlParameters, lookup: ControlLookup) async throws -> JSONValue {
        let wallpaper = try lookup.wallpaper(params.required("wallpaper_id"))
        guard wallpaper.type == "scene" else {
            throw ControlError(.unsupported, "\"\(wallpaper.title)\" is a \(wallpaper.type) wallpaper; the Screen Saver mode records scenes only. The Screen Saver plugin loops other wallpapers by itself while they are on the desktop.")
        }
        let recording = try await service.recordScreenSaver(wallpaper)
        var message = "Recorded \"\(wallpaper.title)\" at \(recording.selection.width)×\(recording.selection.height) and set it as the screen saver."
        if recording.enabledPlugin {
            message += " The Screen Saver plugin was off, so the recording turned it on (which installs the saver), as the Screen Saver mode does."
        }
        return [
            "wallpaper": ControlLookup.json(wallpaper),
            "selection": Self.json(recording.selection),
            "enabled_plugin": .bool(recording.enabledPlugin),
            "message": .string(message + " " + Self.pickInSystemSettings),
        ]
    }

    func stopUsingScreenSaver() throws -> JSONValue {
        let state = service.screenSaver
        guard !state.isRecording else {
            throw ControlError(.unavailable, "A screen saver recording is running. Wait for it to finish, then try again.")
        }
        guard let selection = state.selection else {
            return ["stopped": false, "message": "No recording is set as the screen saver; it already follows the desktop's wallpaper."]
        }
        service.stopUsingScreenSaver()
        let title = selection.wallpaper.map { "\"\($0.title)\"'s recording" } ?? "The recording"
        return ["stopped": true, "message": .string("\(title) is no longer the screen saver; it follows the desktop's wallpaper again.")]
    }

    // MARK: Schedule

    func schedule(message: String) -> JSONValue {
        guard case .object(var object) = Self.json(service.schedule) else { return .null }
        object["message"] = .string(message)
        return .object(object)
    }

    func setSchedule(_ params: ControlParameters) throws -> JSONValue {
        let enabled = try params.requiredBool("enabled")
        let hour = try params.int("hour"), minute = try params.int("minute")
        if let hour, !(0...23).contains(hour) { throw ControlError(.invalidParams, "hour must be 0 to 23.") }
        if let minute, !(0...59).contains(minute) { throw ControlError(.invalidParams, "minute must be 0 to 59.") }
        if !enabled, hour != nil || minute != nil {
            throw ControlError(.invalidParams, "The time is set with enabled: true; the Screen Saver mode's time picker is off while the daily re-recording is off.")
        }
        let current = service.schedule
        if current.enabled != enabled { service.setScheduleEnabled(enabled) }
        let newHour = hour ?? current.hour, newMinute = minute ?? current.minute
        if enabled, newHour != current.hour || newMinute != current.minute {
            service.setScheduleTime(hour: newHour, minute: newMinute)
        }
        var message = Self.scheduleSentence(service.schedule)
        if enabled, service.screenSaver.selection == nil {
            message += " Nothing is set as the screen saver yet, so a run has nothing to record until screensaver_record sets one."
        }
        return schedule(message: message)
    }

    static func scheduleSentence(_ schedule: SystemScreenSaverSchedule) -> String {
        guard schedule.enabled else { return "The daily re-recording is off." }
        var sentence = "The screen saver is recorded again every day at \(String(format: "%02d:%02d", schedule.hour, schedule.minute))"
        if let next = schedule.nextRun { sentence += ", next \(next.formatted(date: .abbreviated, time: .shortened))" }
        return sentence + ", while the app runs (a missed time runs at the next wake or launch)."
    }

    // MARK: Lookup and writing

    /// A layer by its id, or by its name when only one layer has it.
    static func layer(_ name: String, in layers: [SystemSceneLayer], wallpaper: ControlWallpaper) throws -> SystemSceneLayer {
        if let id = Int(name), let layer = layers.first(where: { $0.id == id }) { return layer }
        let named = layers.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if named.count == 1 { return named[0] }
        if named.count > 1 {
            throw ControlError(.invalidParams, "\"\(wallpaper.title)\" has \(named.count) layers named \"\(name)\"; give one's id: "
                               + named.map { String($0.id) }.joined(separator: ", ") + ".")
        }
        let known = layers.prefix(40).map { "\($0.id) (\($0.name))" }.joined(separator: ", ")
        throw ControlError(.notFound, "\"\(wallpaper.title)\" has no layer \"\(name)\". Its layers: \(known)\(layers.count > 40 ? ", …" : "").")
    }

    /// A layer as the screen saver shows it: its own choice, else scene.json's.
    static func json(_ layer: SystemSceneLayer, values: [String: String]) -> JSONValue {
        let visible = values[sceneObjectVisibilityKey(objectID: layer.id)].map { $0 != "false" } ?? layer.authoredVisible
        return [
            "id": .number(Double(layer.id)), "name": .string(layer.name), "kind": .string(layer.kind),
            "visible": .bool(visible), "authored_visible": .bool(layer.authoredVisible),
        ]
    }

    static func json(_ selection: SystemScreenSaverSelection) -> JSONValue {
        [
            "wallpaper": selection.wallpaper.map(ControlLookup.json) ?? .null,
            "folder": .string(selection.folder),
            "recorded": date(selection.recorded),
            "width": .number(Double(selection.width)), "height": .number(Double(selection.height)),
        ]
    }

    static func json(_ schedule: SystemScreenSaverSchedule) -> JSONValue {
        [
            "enabled": .bool(schedule.enabled),
            "hour": .number(Double(schedule.hour)), "minute": .number(Double(schedule.minute)),
            "time": .string(String(format: "%02d:%02d", schedule.hour, schedule.minute)),
            "anchor": date(schedule.anchor),
            "next_run": date(schedule.nextRun),
        ]
    }
}
