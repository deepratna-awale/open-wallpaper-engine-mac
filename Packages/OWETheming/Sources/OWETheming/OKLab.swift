import Foundation

/// A colour in Björn Ottosson's OKLab space, where straight-line distance follows perceived
/// difference, so the nearest palette entry is the one that looks closest.
public struct OKLab: Equatable, Sendable {
    public var lightness: Double
    public var a: Double
    public var b: Double

    public init(lightness: Double, a: Double, b: Double) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }

    /// `color` (sRGB, gamma encoded) in OKLab.
    public init(_ color: ThemeColor) {
        let r = Self.linear(color.red), g = Self.linear(color.green), bl = Self.linear(color.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    /// Chroma: how far from grey.
    public var chroma: Double { (a * a + b * b).squareRoot() }

    public func distance(to other: OKLab) -> Double {
        let dl = lightness - other.lightness, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
