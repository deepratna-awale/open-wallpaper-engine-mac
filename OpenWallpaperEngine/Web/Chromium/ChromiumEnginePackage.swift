import CryptoKit
import Foundation

/// Checking and unpacking a downloaded CEF archive. Nothing here trusts the archive before its
/// SHA-256 matches the pin.
enum ChromiumEnginePackage {
    static let frameworkName = "Chromium Embedded Framework.framework"
    static let frameworkBinary = "Chromium Embedded Framework"
    /// Written last into an install folder; a folder without it is not an install.
    static let manifestName = ".owe-chromium-engine.json"

    struct Manifest: Codable, Equatable {
        let version: String
        let platform: String
        let sha256: String
    }

    enum Failure: LocalizedError, Equatable {
        case checksumMismatch(expected: String, actual: String)
        case notBzip2
        case extractionFailed(String)
        case missingFramework

        var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                return String(localized: "The Chromium download doesn't match the version this app expects, so it wasn't installed. Try again later.",
                              comment: "Chromium engine install error: the downloaded file's checksum is wrong")
            case .notBzip2:
                return String(localized: "The Chromium download isn't a valid archive. Try again later.",
                              comment: "Chromium engine install error")
            case .extractionFailed(let reason):
                return String(localized: "Can't unpack the Chromium engine: \(reason)",
                              comment: "Chromium engine install error; %@ is the system's reason")
            case .missingFramework:
                return String(localized: "The Chromium download has no Chromium Embedded Framework.",
                              comment: "Chromium engine install error; Chromium Embedded Framework is a product name")
            }
        }
    }

    /// Lowercase hex SHA-256 of `file`, read in 1 MiB chunks.
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() } // Closing a read handle has nothing to report.
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Throws unless `file`'s SHA-256 is `expected`.
    static func verify(_ file: URL, sha256 expected: String) throws {
        let actual = try sha256(of: file)
        guard actual == expected.lowercased() else {
            throw Failure.checksumMismatch(expected: expected.lowercased(), actual: actual)
        }
    }

    /// Throws unless `archive` starts with bzip2's "BZh" magic.
    static func checkBzip2(_ archive: URL) throws {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() } // Closing a read handle has nothing to report.
        guard try handle.read(upToCount: 3) == Data("BZh".utf8) else { throw Failure.notBzip2 }
    }

    /// Unpacks the framework and license of the verified `archive` into `destination` (which must
    /// not exist yet) and writes the manifest last. `scratch` is an empty folder for tar's output.
    static func unpack(_ archive: URL, pin: ChromiumEnginePin, scratch: URL, into destination: URL) throws {
        try checkBzip2(archive)
        let root = pin.archiveRoot
        let framework = "\(root)/Release/\(frameworkName)"
        let license = "\(root)/LICENSE.txt"
        try runTar(["-xjof", archive.path, "-C", scratch.path, framework, license])

        let fileManager = FileManager.default
        let unpackedFramework = scratch.appending(path: framework, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: unpackedFramework.appending(path: frameworkBinary).path) else {
            throw Failure.missingFramework
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        try fileManager.moveItem(at: unpackedFramework, to: destination.appending(path: frameworkName))
        try fileManager.moveItem(at: scratch.appending(path: license), to: destination.appending(path: "LICENSE.txt"))
        let manifest = Manifest(version: pin.version, platform: pin.platform, sha256: pin.sha256)
        try JSONEncoder().encode(manifest).write(to: destination.appending(path: manifestName), options: .atomic)
    }

    private static func runTar(_ arguments: [String]) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        // -o: don't restore the archive's owner. Without -P, bsdtar refuses absolute paths, `..`
        // and writes through symlinks, so nothing leaves the scratch folder.
        process.arguments = arguments
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Clears Gatekeeper's quarantine flag from the verified archive only, before unpacking, so
    /// tar has no flag to copy onto the files. URLSession downloads are normally not flagged, so
    /// this is usually a no-op; nothing else is ever touched.
    static func removeQuarantine(fromVerified archive: URL) {
        let attribute = SteamCmdPackage.quarantineAttribute
        guard SteamCmdPackage.hasQuarantine(archive.path) else { return }
        if removexattr(archive.path, attribute, XATTR_NOFOLLOW) != 0 {
            OWELog.error(.web, "Can't clear the quarantine flag of \(archive.path): errno \(errno)")
        } else {
            OWELog.info(.web, "Cleared the quarantine flag of the verified Chromium archive")
        }
    }

    /// The manifest of the install in `folder`, nil when it isn't a complete install.
    static func manifest(in folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: folder.appending(path: manifestName)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              FileManager.default.fileExists(atPath: folder.appending(path: "\(frameworkName)/\(frameworkBinary)").path)
        else { return nil }
        return manifest
    }
}
