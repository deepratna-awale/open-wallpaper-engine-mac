import Foundation

/// Reads a WE JSON file as WE's own reader does: a UTF-8 byte order mark, `//` and `/* */`
/// comments and trailing commas are allowed. WE ships such files (the `water` preset's
/// `preset.json` has trailing commas, and its editor lists it).
public enum WETolerantJSON {
    /// The file's value as `JSONSerialization` reads it.
    public static func object(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: cleaned(data), options: [.fragmentsAllowed])
    }

    /// `data` without its byte order mark, comments and trailing commas; strings are kept as
    /// they are.
    static func cleaned(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        let newline = UInt8(ascii: "\n"), comma = UInt8(ascii: ",")
        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote {
                // A string, copied whole with its escapes.
                output.append(byte)
                index += 1
                while index < bytes.count {
                    let inner = bytes[index]
                    output.append(inner)
                    index += 1
                    if inner == backslash, index < bytes.count {
                        output.append(bytes[index])
                        index += 1
                    } else if inner == quote {
                        break
                    }
                }
                continue
            }
            if byte == slash, index + 1 < bytes.count, bytes[index + 1] == slash {
                while index < bytes.count, bytes[index] != newline { index += 1 }
                continue
            }
            if byte == slash, index + 1 < bytes.count, bytes[index + 1] == star {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == star && bytes[index + 1] == slash) { index += 1 }
                index = min(index + 2, bytes.count)
                continue
            }
            if byte == comma, closesAfter(bytes, from: index + 1) {
                index += 1
                continue
            }
            output.append(byte)
            index += 1
        }
        return Data(output)
    }

    /// Whether the next token after `start` (past white space and comments) closes an object or array.
    private static func closesAfter(_ bytes: [UInt8], from start: Int) -> Bool {
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                index += 1
            case UInt8(ascii: "/") where index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "/"):
                while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
            case UInt8(ascii: "/") where index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "*"):
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) {
                    index += 1
                }
                index += 2
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                return true
            default:
                return false
            }
        }
        return false
    }
}
