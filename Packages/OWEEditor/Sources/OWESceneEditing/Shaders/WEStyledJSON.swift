import Foundation

/// JSON as Wallpaper Engine's editor writes a project's effect and material files: JsonCpp's
/// `StyledStreamWriter` with a tab indent (keys sorted by their bytes, `"key" : value`, an array
/// or object that is a member's value on a line of its own, a short array of plain values on one
/// line `[ a, b ]`), without the trailing newline (WE's `effects/<name>/effect.json` of a new effect).
public enum WEStyledJSON {
    /// JsonCpp's right margin: a plain array at least this long breaks into lines.
    static let rightMargin = 74

    public static func string(_ value: SceneJSONValue) -> String {
        var writer = Writer()
        writer.write(value)
        return writer.document
    }

    public static func data(_ value: SceneJSONValue) -> Data {
        Data(string(value).utf8)
    }

    private struct Writer {
        var document = ""
        var indentString = ""
        /// The next line is already started at the current indent (JsonCpp's `indented_`).
        var indented = true
        /// A plain array's elements, written apart to measure the line (`childValues_`).
        var childValues: [String] = []
        var addChildValues = false

        mutating func write(_ value: SceneJSONValue) {
            indentString = ""
            indented = true
            writeValue(value)
        }

        mutating func writeValue(_ value: SceneJSONValue) {
            switch value {
            case .null: push("null")
            case .bool(let flag): push(flag ? "true" : "false")
            case .number(let number): push(WEStyledJSON.number(number))
            case .string(let text): push(WEStyledJSON.quoted(text))
            case .array(let values): writeArray(values)
            case .object(let members):
                guard !members.isEmpty else { push("{}"); return }
                writeWithIndent("{")
                indent()
                let keys = members.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                for (index, key) in keys.enumerated() {
                    writeWithIndent(WEStyledJSON.quoted(key))
                    document += " : "
                    writeValue(members[key]!)
                    if index < keys.count - 1 { document += "," }
                }
                unindent()
                writeWithIndent("}")
            }
        }

        mutating func writeArray(_ values: [SceneJSONValue]) {
            guard !values.isEmpty else { push("[]"); return }
            if isMultiline(values) {
                writeWithIndent("[")
                indent()
                let hasChildValues = !childValues.isEmpty
                for (index, value) in values.enumerated() {
                    if hasChildValues {
                        writeWithIndent(childValues[index])
                    } else {
                        if !indented { writeIndent() }
                        indented = true
                        writeValue(value)
                        indented = false
                    }
                    if index < values.count - 1 { document += "," }
                }
                unindent()
                writeWithIndent("]")
            } else {
                document += "[ " + childValues.joined(separator: ", ") + " ]"
            }
        }

        mutating func isMultiline(_ values: [SceneJSONValue]) -> Bool {
            var multiline = values.count * 3 >= WEStyledJSON.rightMargin
            childValues = []
            for value in values where !multiline {
                switch value {
                case .array(let inner): multiline = !inner.isEmpty
                case .object(let inner): multiline = !inner.isEmpty
                default: break
                }
            }
            if !multiline {
                addChildValues = true
                var length = 4 + (values.count - 1) * 2
                for value in values {
                    writeValue(value)
                    length += childValues.last?.count ?? 0
                }
                addChildValues = false
                multiline = length >= WEStyledJSON.rightMargin
            }
            return multiline
        }

        mutating func push(_ text: String) {
            if addChildValues { childValues.append(text) } else { document += text }
        }

        mutating func writeIndent() {
            document += "\n" + indentString
        }

        mutating func writeWithIndent(_ text: String) {
            if !indented { writeIndent() }
            document += text
            indented = false
        }

        mutating func indent() { indentString += "\t" }
        mutating func unindent() { indentString.removeLast() }
    }

    /// A whole number without a fraction (WE's `"version" : 1`), any other as Swift's shortest form.
    static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

    /// JsonCpp's `valueToQuotedString`: quotes, backslashes and control characters escaped,
    /// anything else (`/`, non-ASCII) as it is.
    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
