import Cocoa
import MetalKit
import CryptoKit
import os

enum SceneFontRegistry {
    private static let fonts = OSAllocatedUnfairLock(initialState: [String: String]())

    static func register(_ font: CGFont, names: [String]) {
        guard let postScriptName = CTFontCopyPostScriptName(CTFontCreateWithGraphicsFont(font, 0, nil, nil)) as String? else { return }
        register(postScriptName: postScriptName, names: names)
    }

    /// An installed font under the names a scene gives it (`systemfont_cambria` → Times New Roman,
    /// `SceneFontResolver.weSystemFonts`), so a user's per-layer font seeded with that name finds it.
    static func register(postScriptName: String, names: [String]) {
        fonts.withLock { fonts in
            for name in names where !name.isEmpty { fonts[name] = postScriptName }
        }
    }

    static func font(named name: String, size: CGFloat) -> NSFont? {
        let fontName = fonts.withLock { $0[name] }
        guard let fontName else { return nil }
        return NSFont(name: fontName, size: size)
    }
}
