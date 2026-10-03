import Foundation

/// What an effect lets the editor change, read from its material and shaders by the app
/// (`SceneEffectParameters`): its constants with their controls, its combos and its texture slots.
public struct EffectSchema: Hashable, Sendable {
    /// A uniform with a `material` key: a slider, a colour, a vector or a switch.
    public struct Parameter: Hashable, Sendable, Identifiable {
        /// The constant's key in `constantshadervalues`.
        public var key: String
        public var title: String
        public var defaultValue: [Double]
        public var minimum: Double
        public var maximum: Double
        public var isInteger: Bool
        public var isColor: Bool
        /// WE's linked vec2: one slider for both components while they are equal.
        public var isLinked: Bool

        public var id: String { key }

        public init(key: String, title: String, defaultValue: [Double], minimum: Double = 0, maximum: Double = 1,
                    isInteger: Bool = false, isColor: Bool = false, isLinked: Bool = false) {
            self.key = key
            self.title = title
            self.defaultValue = defaultValue
            self.minimum = minimum
            self.maximum = maximum
            self.isInteger = isInteger
            self.isColor = isColor
            self.isLinked = isLinked
        }

        /// The control WE's editor shows for it.
        public enum Control: Hashable, Sendable {
            /// An integer 0…1 shown as a checkbox.
            case toggle
            case slider
            case color
            /// Several components, each a slider.
            case vector(Int)
        }

        public var control: Control {
            if isColor { return .color }
            if defaultValue.count > 1 { return .vector(defaultValue.count) }
            if isInteger, minimum == 0, maximum == 1 { return .toggle }
            return .slider
        }
    }

    /// A `// [COMBO]` switch: options, or on/off when it has none.
    public struct Combo: Hashable, Sendable, Identifiable {
        public struct Option: Hashable, Sendable {
            public var title: String
            public var value: Int
            /// The heading WE groups it under, if any.
            public var group: String?

            public init(title: String, value: Int, group: String? = nil) {
                self.title = title
                self.value = value
                self.group = group
            }
        }

        public var name: String
        public var title: String
        public var defaultValue: Int
        public var options: [Option]
        /// Other combos' values this one is shown for (WE's `require`).
        public var requirements: [String: Int]

        public var id: String { name }

        public init(name: String, title: String, defaultValue: Int, options: [Option] = [], requirements: [String: Int] = [:]) {
            self.name = name
            self.title = title
            self.defaultValue = defaultValue
            self.options = options
            self.requirements = requirements
        }
    }

    /// A sampler the editor shows: a texture to pick, or a mask to paint.
    public struct TextureSlot: Hashable, Sendable, Identifiable {
        /// `g_TextureN`'s N: its index in the pass's `textures`.
        public var slot: Int
        public var title: String
        /// What fills it when nothing is set (`util/white`), if anything.
        public var defaultTexture: String?
        /// WE's `"mode": "opacitymask"` and other painted masks: the editor offers a brush.
        public var isMask: Bool
        /// The combo it switches on while bound (`MASK`).
        public var combo: String?
        /// The colour a new mask is painted from (`paintdefaultcolor`), 0…1 RGBA.
        public var paintDefault: [Double]?

        public var id: Int { slot }

        public init(slot: Int, title: String, defaultTexture: String? = nil, isMask: Bool = false, combo: String? = nil,
                    paintDefault: [Double]? = nil) {
            self.slot = slot
            self.title = title
            self.defaultTexture = defaultTexture
            self.isMask = isMask
            self.combo = combo
            self.paintDefault = paintDefault
        }
    }

    public var parameters: [Parameter]
    public var combos: [Combo]
    public var textures: [TextureSlot]
    /// How many passes `effect.json` lists, which an added effect's scene object lists too.
    public var passCount: Int

    public init(parameters: [Parameter] = [], combos: [Combo] = [], textures: [TextureSlot] = [], passCount: Int = 1) {
        self.parameters = parameters
        self.combos = combos
        self.textures = textures
        self.passCount = passCount
    }

    /// Whether `combo` shows given the effect's current combo values (WE hides one whose
    /// requirements don't hold).
    public static func requirementsHold(_ combo: Combo, values: (String) -> Int) -> Bool {
        combo.requirements.allSatisfy { values($0.key) == $0.value }
    }
}
