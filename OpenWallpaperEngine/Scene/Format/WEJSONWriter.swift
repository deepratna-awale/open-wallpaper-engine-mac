import Foundation

/// Writes JSON exactly as WE writes the files it generates (scene.json and project.json in its
/// mobile packages): JsonCpp's styled stream writer with a tab indentation, `" : "` after a name,
/// members sorted by name, an object or a non-empty array of objects on lines of their own, a
/// short array of scalars on one line (`[ a, b ]`, under JsonCpp's right margin of 74), reals
/// with 8 significant digits (`%.8g`, `.0` added to whole numbers: `0.64999998`, `2.0`),
/// non-ASCII characters escaped as `\uxxxx`, no newline at the end, and Windows line ends.
///
/// Checked byte for byte against WE 2.8.42's mobile export of a Workshop scene
/// (`MobilePackageTests`).
enum WEJSONWriter {
    /// JsonCpp's `rightMargin_`.
    static let rightMargin = 74
    static let precision = 8

    static func data(_ document: WEJSONDocument) -> Data {
        var writer = Writer()
        writer.write(document)
        return Data(writer.output.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    /// A real as JsonCpp writes it at `precision` significant digits.
    static func real(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        var text = String(format: "%.\(precision)g", value)
        if !text.contains("."), !text.contains("e") { text += ".0" }
        return text
    }

    static func quoted(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\u{8}": result += "\\b"
            case "\u{C}": result += "\\f"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                let value = scalar.value
                if value < 0x20 || (0x80..<0x10000).contains(value) {
                    result += String(format: "\\u%04x", value)
                } else if value >= 0x10000 {
                    let offset = value - 0x10000
                    result += String(format: "\\u%04x\\u%04x", 0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF))
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    static func scalar(_ document: WEJSONDocument) -> String? {
        switch document {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .unsigned(let value): return String(value)
        case .real(let value): return real(value)
        case .string(let value): return quoted(value)
        case .array, .object: return nil
        }
    }

    /// JsonCpp's `BuiltStyledStreamWriter`, its state as it keeps it.
    private struct Writer {
        var output = ""
        var indentation = ""
        var indented = true

        mutating func newLine() { output += "\n" + indentation }

        mutating func writeWithIndent(_ text: String) {
            if !indented { newLine() }
            output += text
            indented = false
        }

        mutating func write(_ document: WEJSONDocument) {
            switch document {
            case .object(let members):
                guard !members.isEmpty else { output += "{}"; return }
                writeWithIndent("{")
                indentation += "\t"
                let names = members.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
                for (index, name) in names.enumerated() {
                    writeWithIndent(WEJSONWriter.quoted(name))
                    output += " : "
                    write(members[name] ?? .null)
                    if index + 1 < names.count { output += "," }
                }
                indentation.removeLast()
                writeWithIndent("}")
            case .array(let elements):
                guard !elements.isEmpty else { output += "[]"; return }
                if let line = Self.singleLine(elements) {
                    output += "[ " + line.joined(separator: ", ") + " ]"
                    return
                }
                writeWithIndent("[")
                indentation += "\t"
                for (index, element) in elements.enumerated() {
                    if let text = WEJSONWriter.scalar(element) {
                        writeWithIndent(text)
                    } else {
                        if !indented { newLine() }
                        indented = true
                        write(element)
                        indented = false
                    }
                    if index + 1 < elements.count { output += "," }
                }
                indentation.removeLast()
                writeWithIndent("]")
            default:
                output += WEJSONWriter.scalar(document) ?? "null"
            }
        }

        /// The elements written on one line, or nil when JsonCpp puts them on lines of their own
        /// (`isMultilineArray`).
        static func singleLine(_ elements: [WEJSONDocument]) -> [String]? {
            guard elements.count * 3 < WEJSONWriter.rightMargin else { return nil }
            var texts: [String] = []
            var length = 4 + (elements.count - 1) * 2
            for element in elements {
                switch element {
                case .array(let inner) where !inner.isEmpty: return nil
                case .object(let inner) where !inner.isEmpty: return nil
                default: break
                }
                var writer = Writer()
                writer.write(element)
                texts.append(writer.output)
                length += writer.output.utf8.count
            }
            return length < WEJSONWriter.rightMargin ? texts : nil
        }
    }
}
