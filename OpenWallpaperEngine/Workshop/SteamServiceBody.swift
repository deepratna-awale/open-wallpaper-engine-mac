import Foundation

/// A Steam service method's request message for the Steam helper (`call`), made from the Web API
/// parameters the app builds for the same method (`WorkshopAPIService.queryItems`…): `name[n]`
/// becomes a list, `true`/`false` a bool, digits a number, and the rest stays text.
struct SteamServiceBody: Encodable, Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case bool(Bool)
        case number(Int64)
        case text(String)
        case list([String])
    }

    /// Fields that are text even when they hold digits: a search for "2024", 64-bit ids.
    static let textFields: Set<String> = ["search_text", "cursor", "type", "steamid", "child_publishedfileid"]

    private(set) var fields: [String: Value] = [:]

    init(_ parameters: [URLQueryItem]) {
        var lists: [String: [(index: Int, value: String)]] = [:]
        for parameter in parameters {
            let value = parameter.value ?? ""
            if let open = parameter.name.firstIndex(of: "["), parameter.name.hasSuffix("]"),
               let index = Int(parameter.name[parameter.name.index(after: open)..<parameter.name.index(before: parameter.name.endIndex)]) {
                lists[String(parameter.name[..<open]), default: []].append((index, value))
            } else if Self.textFields.contains(parameter.name) {
                fields[parameter.name] = .text(value)
            } else if value == "true" || value == "false" {
                fields[parameter.name] = .bool(value == "true")
            } else if let number = Int64(value) {
                fields[parameter.name] = .number(number)
            } else {
                fields[parameter.name] = .text(value)
            }
        }
        for (name, values) in lists {
            fields[name] = .list(values.sorted { $0.index < $1.index }.map(\.value))
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            let key = Key(stringValue: name)
            switch value {
            case .bool(let flag): try container.encode(flag, forKey: key)
            case .number(let number): try container.encode(number, forKey: key)
            case .text(let text): try container.encode(text, forKey: key)
            case .list(let list): try container.encode(list, forKey: key)
            }
        }
    }
}
