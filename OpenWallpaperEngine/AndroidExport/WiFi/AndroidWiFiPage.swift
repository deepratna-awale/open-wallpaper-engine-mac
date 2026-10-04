import Foundation

/// The one page the phone opens: every package of the batch with its preview, title, type and
/// size, a Download button each and "Download All", which starts them one after another, and how
/// to import them. Inline CSS and script, no outside resources; the script runs under the
/// response's CSP nonce (`noncePlaceholder`, replaced per response).
enum AndroidWiFiPage {
    static let noncePlaceholder = "{{OWE_NONCE}}"
    /// The pause between "Download All"'s downloads, so the browser keeps up.
    static let downloadAllInterval = 1500

    static func html(files: [AndroidWiFiFile], token: String) -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let direction = Locale.Language(identifier: language).characterDirection == .rightToLeft ? "rtl" : "ltr"
        let items = files.map { item(for: $0, token: token) }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="\(escape(language))" dir="\(direction)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <title>\(escape(String(localized: "Wallpapers for Wallpaper Engine")))</title>
        <style>
        :root { color-scheme: light dark; --bg: #f4f4f6; --card: #fff; --text: #1c1c1e; --muted: #6c6c70; --accent: #0a84ff; --line: #d9d9de; }
        @media (prefers-color-scheme: dark) { :root { --bg: #000; --card: #1c1c1e; --text: #f2f2f7; --muted: #a1a1a6; --line: #38383a; } }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 16px; background: var(--bg); color: var(--text); font: 16px/1.4 system-ui, -apple-system, Roboto, sans-serif; }
        main { max-width: 720px; margin: 0 auto; }
        h1 { font-size: 1.4rem; margin: 4px 0 12px; }
        p { margin: 0 0 10px; color: var(--muted); }
        ol { margin: 0 0 14px; padding-inline-start: 22px; color: var(--muted); }
        ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
        ul li { display: flex; gap: 12px; align-items: center; background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 10px; }
        img, .noimg { width: 72px; height: 72px; flex: none; border-radius: 10px; object-fit: cover; background: var(--line); }
        .info { flex: 1; min-width: 0; }
        .title { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .meta { color: var(--muted); font-size: 0.875rem; }
        a.button, button { display: inline-block; flex: none; border: 0; border-radius: 999px; padding: 10px 16px; background: var(--accent); color: #fff; font: inherit; font-weight: 600; text-decoration: none; cursor: pointer; }
        button { width: 100%; margin: 4px 0 14px; padding: 14px; }
        button:disabled { opacity: 0.6; }
        </style>
        </head>
        <body>
        <main>
        <h1>\(escape(String(localized: "Wallpapers for Wallpaper Engine")))</h1>
        <ol>
        <li>\(escape(String(localized: "Download the files to this device.")))</li>
        <li>\(escape(String(localized: "Open the Wallpaper Engine app, then import each file from your device's storage.")))</li>
        </ol>
        <button id="all" type="button">\(escape(String(localized: "Download All")))</button>
        <p>\(escape(String(localized: "Your browser may ask once to allow downloading multiple files: allow it, then wait for every download to finish.")))</p>
        <ul>
        \(items)
        </ul>
        <p>\(escape(String(localized: "This page stops working when the Send over Wi-Fi window on the Mac closes, or after 15 minutes.")))</p>
        </main>
        <script nonce="\(noncePlaceholder)">
        document.getElementById("all").addEventListener("click", function () {
          var button = this, links = Array.prototype.slice.call(document.querySelectorAll("a.download")), next = 0;
          button.disabled = true;
          (function start() {
            if (next >= links.length) { button.disabled = false; return; }
            var link = document.createElement("a");
            link.href = links[next++].href;
            link.download = "";
            document.body.appendChild(link);
            link.click();
            link.remove();
            setTimeout(start, \(downloadAllInterval));
          })();
        });
        </script>
        </body>
        </html>
        """
    }

    private static func item(for file: AndroidWiFiFile, token: String) -> String {
        let picture = file.previewURL == nil
            ? #"<div class="noimg"></div>"#
            : #"<img src="/\#(token)/preview/\#(file.index)" alt="" loading="lazy">"#
        let meta = "\(label(file.kind)) · \(file.size.formatted(.byteCount(style: .file)))"
        return """
        <li>\(picture)<div class="info"><div class="title">\(escape(file.title))</div><div class="meta">\(escape(meta))</div></div>\
        <a class="button download" href="/\(token)/file/\(file.index)" download="\(escape(file.downloadName))">\(escape(String(localized: "Download")))</a></li>
        """
    }

    /// The page's and the Mac's name for a package's type.
    static func label(_ kind: AndroidWiFiFile.Kind) -> String {
        switch kind {
        case .sceneDynamic: return String(localized: "Scene (Dynamic)")
        case .scenePreRendered: return String(localized: "Scene (Pre-Rendered)")
        case .video: return LocalizedLabels.wallpaperType("video")
        }
    }

    /// Text and attribute values with `& < > " '` escaped.
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
