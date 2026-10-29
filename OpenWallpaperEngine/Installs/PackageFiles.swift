import Foundation

/// File helpers for packages the app downloads and unpacks (the Chromium engine, depth-map plugins):
/// the quarantine flag and the size on disk.
enum PackageFiles {
    static let quarantineAttribute = "com.apple.quarantine"

    /// Removes Gatekeeper's quarantine flag from every file under `directory`, so the shell script
    /// and the binaries it starts run without a prompt. Files the app downloads itself are normally
    /// not flagged; this covers a copy that was.
    static func removeQuarantine(under directory: URL) {
        let paths = [directory.path] + (FileManager.default.enumerator(atPath: directory.path)?
            .compactMap { ($0 as? String).map { directory.appending(path: $0).path } } ?? [])
        for path in paths where hasQuarantine(path) {
            if removexattr(path, quarantineAttribute, XATTR_NOFOLLOW) != 0 {
                OWELog.error(.workshop, "Can't clear the quarantine flag of \(path): errno \(errno)")
            }
        }
    }

    static func hasQuarantine(_ path: String) -> Bool {
        getxattr(path, quarantineAttribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// The bytes `directory` takes on disk.
    static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            // A file that vanished while counting just doesn't count.
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
