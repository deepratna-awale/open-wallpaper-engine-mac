import Foundation

/// Collects the elements that element-wise decoding skipped. Pass one to `decodeTolerant` (or put
/// it in `JSONDecoder.userInfo[.decodeFailureLog]`) to inspect failures, e.g. in tests.
public final class DecodeFailureLog {
    private var storage: [String] = []
    private let lock = NSLock()

    public init() {}

    public var messages: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    public func record(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(message)
    }
}

extension CodingUserInfoKey {
    public static let decodeFailureLog = CodingUserInfoKey(rawValue: "owe.decodeFailureLog")!
}

/// What WE's text files may start with: a UTF-8 byte order mark, which WE's readers skip and
/// Foundation's don't. The one place the app skips it (the editor package's `WETolerantJSON`,
/// which can't link the app, has its own).
public enum TolerantJSON {
    public static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Whether `bytes` start with a UTF-8 byte order mark.
    public static func hasBOM<Bytes: Collection>(_ bytes: Bytes) -> Bool where Bytes.Element == UInt8 {
        bytes.starts(with: byteOrderMark)
    }

    /// `data` without a leading UTF-8 byte order mark.
    public static func withoutBOM(_ data: Data) -> Data {
        hasBOM(data) ? Data(data.dropFirst(byteOrderMark.count)) : data
    }
}

/// Decodes WE JSON, which may contain trailing commas, comments or a UTF-8 BOM
/// (the stock fluidsimulation effect.json has a trailing comma).
public func decodeTolerant<T: Decodable>(_ type: T.Type, from data: Data, failures: DecodeFailureLog? = nil) throws -> T {
    let decoder = JSONDecoder()
    decoder.allowsJSON5 = true
    if let failures { decoder.userInfo[.decodeFailureLog] = failures }
    return try decoder.decode(T.self, from: TolerantJSON.withoutBOM(data))
}

/// A coding key for dictionaries with arbitrary keys.
public struct AnyCodingKey: CodingKey {
    public let stringValue: String
    public let intValue: Int?
    public init(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    public init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}
