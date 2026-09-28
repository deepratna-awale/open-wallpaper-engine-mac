import Foundation

/// A release version as the tags spell it: `X.Y.Z` or `X.Y.Z-(alpha|beta|rc).N`.
/// `Scripts/release-version.sh` applies the same rules to tags in the release workflow.
struct ReleaseVersion: Equatable {
    enum Stage: String { case alpha, beta, rc }

    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: (stage: Stage, number: Int)?

    init?(_ text: String) {
        let trimmed: Substring = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts: [Substring] = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers: [Int] = parts[0].split(separator: ".", omittingEmptySubsequences: false).compactMap { part in
            part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) && !part.isEmpty ? Int(part) : nil
        }
        guard numbers.count == 3, parts[0].split(separator: ".", omittingEmptySubsequences: false).count == 3 else {
            return nil
        }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
        if parts.count == 2 {
            let suffix: [Substring] = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard suffix.count == 2, let stage = Stage(rawValue: String(suffix[0])),
                  !suffix[1].isEmpty, suffix[1].allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(suffix[1]) else { return nil }
            prerelease = (stage, number)
        } else {
            prerelease = nil
        }
    }

    /// `X.Y.Z`, the bundle's `CFBundleShortVersionString`.
    var marketingVersion: String { "\(major).\(minor).\(patch)" }

    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.marketingVersion == rhs.marketingVersion
            && lhs.prerelease?.stage == rhs.prerelease?.stage
            && lhs.prerelease?.number == rhs.prerelease?.number
    }
}
