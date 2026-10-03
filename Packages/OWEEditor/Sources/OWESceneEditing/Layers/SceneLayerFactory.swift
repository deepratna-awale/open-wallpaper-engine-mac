import Foundation

/// The scene.json objects of the layers WE's editor adds, with the fields its new layers carry
/// (as WE's own scenes write them: `models/util/*.json` for solid, composition and fullscreen
/// layers, a `text` object for text, a `sound` list for sound).
public enum SceneLayerFactory {
    /// Fields every planar layer WE's editor makes has.
    static func planar(name: String, origin: SIMD2<Double>, size: SIMD2<Double>?) -> [String: SceneJSONValue] {
        var object: [String: SceneJSONValue] = [
            "name": .string(name),
            "origin": SceneVector.value([origin.x, origin.y, 0]),
            "scale": .string("1 1 1"),
            "angles": .string("0 0 0"),
            "alpha": .number(1),
            "color": .string("1 1 1"),
            "colorBlendMode": .number(0),
            "brightness": .number(1),
            "parallaxDepth": .string("1 1"),
            "perspective": .bool(false),
            "solid": .bool(true),
            "copybackground": .bool(true),
            "locktransforms": .bool(false),
            "visible": .bool(true),
        ]
        if let size { object["size"] = SceneVector.value([size.x, size.y]) }
        return object
    }

    /// An image layer drawing `model` (`models/…json`, written by `EditorAssetStore`).
    public static func image(name: String, model: String, size: SIMD2<Double>, origin: SIMD2<Double>) -> [String: SceneJSONValue] {
        var object = planar(name: name, origin: origin, size: size)
        object["image"] = .string(model)
        return object
    }

    /// A fill of `color` (0…1 RGB) over `size`.
    public static func solid(name: String, color: SIMD3<Double>, size: SIMD2<Double>, origin: SIMD2<Double>) -> [String: SceneJSONValue] {
        var object = planar(name: name, origin: origin, size: size)
        object["image"] = .string("models/util/solidlayer.json")
        object["color"] = SceneVector.value([color.x, color.y, color.z])
        return object
    }

    /// The scene under its rectangle as its image, for its effects.
    public static func composition(name: String, size: SIMD2<Double>, origin: SIMD2<Double>) -> [String: SceneJSONValue] {
        var object = planar(name: name, origin: origin, size: size)
        object["image"] = .string("models/util/composelayer.json")
        object["config"] = .object(["passthrough": .bool(true)])
        return object
    }

    /// The whole scene drawn so far as its image, for its effects.
    public static func fullscreen(name: String) -> [String: SceneJSONValue] {
        [
            "name": .string(name),
            "image": .string("models/util/fullscreenlayer.json"),
            "parallaxDepth": .string("0 0"),
            "visible": .bool(true),
        ]
    }

    /// A text layer as WE's editor makes one (`WETextDefaults` are the parser's when a field is
    /// missing; these are the new layer's own).
    public static func text(name: String, value: String, font: String, pointSize: Double, origin: SIMD2<Double>,
                            script: String? = nil, scriptProperties: [String: SceneJSONValue]? = nil) -> [String: SceneJSONValue] {
        var object = planar(name: name, origin: origin, size: nil)
        var text: [String: SceneJSONValue] = ["value": .string(value)]
        if let script { text["script"] = .string(script) }
        if let scriptProperties, !scriptProperties.isEmpty { text["scriptproperties"] = .object(scriptProperties) }
        object["text"] = .object(text)
        object["font"] = .string(font)
        object["pointsize"] = .number(pointSize)
        object["horizontalalign"] = .string("center")
        object["verticalalign"] = .string("center")
        object["anchor"] = .string("none")
        object["padding"] = .number(32)
        object["backgroundcolor"] = .string("0 0 0")
        object["backgroundbrightness"] = .number(1)
        object["opaquebackground"] = .bool(false)
        return object
    }

    /// A sound layer playing `files` (`sounds/…`) as WE's editor makes one.
    public static func sound(name: String, files: [String], volume: Double = 1) -> [String: SceneJSONValue] {
        [
            "name": .string(name),
            "sound": .array(files.map(SceneJSONValue.string)),
            "playbackmode": .string("loop"),
            "volume": .number(volume),
            "startsilent": .bool(false),
            "muteineditor": .bool(false),
            "mintime": .number(1),
            "maxtime": .number(5),
            "origin": .string("0 0 0"),
            "scale": .string("1 1 1"),
            "angles": .string("0 0 0"),
        ]
    }

    /// An empty object other layers are parented to.
    public static func group(name: String, origin: SIMD2<Double>) -> [String: SceneJSONValue] {
        [
            "name": .string(name),
            "origin": SceneVector.value([origin.x, origin.y, 0]),
            "scale": .string("1 1 1"),
            "angles": .string("0 0 0"),
            "parallaxDepth": .string("1 1"),
            "visible": .bool(true),
        ]
    }

    // MARK: Text scripts

    /// The text scripts WE's editor offers for a text layer, as SceneScript (`update(value)` returns
    /// the text each frame; `scriptProperties` are its options).
    public enum TextScript: String, CaseIterable, Sendable {
        case clock, date

        public var source: String {
            switch self {
            case .clock:
                return """
                'use strict';

                export var scriptProperties = createScriptProperties()
                \t.addCheckbox({ name: 'use24hFormat', label: 'ui_editor_properties_use_24h_format', value: true })
                \t.addCheckbox({ name: 'showSeconds', label: 'ui_editor_properties_show_seconds', value: false })
                \t.addText({ name: 'delimiter', label: 'ui_editor_properties_delimiter', value: ':' })
                \t.finish();

                function pad(number) {
                \treturn ('0' + number).slice(-2);
                }

                export function update(value) {
                \tlet now = new Date();
                \tlet hours = now.getHours();
                \tif (!scriptProperties.use24hFormat) {
                \t\thours = hours % 12 || 12;
                \t}
                \tlet text = pad(hours) + scriptProperties.delimiter + pad(now.getMinutes());
                \tif (scriptProperties.showSeconds) {
                \t\ttext += scriptProperties.delimiter + pad(now.getSeconds());
                \t}
                \treturn text;
                }

                """
            case .date:
                return """
                'use strict';

                export var scriptProperties = createScriptProperties()
                \t.addCheckbox({ name: 'showWeekday', label: 'ui_editor_properties_show_day', value: true })
                \t.finish();

                export function update(value) {
                \tlet now = new Date();
                \tlet options = { year: 'numeric', month: 'long', day: 'numeric' };
                \tif (scriptProperties.showWeekday) {
                \t\toptions.weekday = 'long';
                \t}
                \treturn now.toLocaleDateString(undefined, options);
                }

                """
            }
        }

        /// The script's options as a new layer starts with them.
        public var properties: [String: SceneJSONValue] {
            switch self {
            case .clock: return ["use24hFormat": .bool(true), "showSeconds": .bool(false), "delimiter": .string(":")]
            case .date: return ["showWeekday": .bool(true)]
            }
        }

        /// The text the layer shows before the script first runs.
        public var placeholder: String {
            switch self {
            case .clock: return "12:34"
            case .date: return "1 January 2026"
            }
        }

        /// Which of these a layer's script is, by its source.
        public init?(source: String?) {
            guard let source else { return nil }
            guard let match = Self.allCases.first(where: { $0.source == source }) else { return nil }
            self = match
        }
    }
}
