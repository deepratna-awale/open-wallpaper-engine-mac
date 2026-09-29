import Foundation

/// The page buttons of the Installed tab: up to two pages either side of the current one.
/// Safe for any input, including an empty library, a current page past the last one (wallpapers
/// removed, a filter narrowed the list) and a current page below 1.
enum InstalledPageWindow {
    /// How many pages to show on each side of the current page.
    static let radius = 2

    /// `page` moved into `1...max(total, 1)`.
    static func clamp(_ page: Int, total: Int) -> Int {
        min(max(page, 1), max(total, 1))
    }

    /// The page numbers to show, in order. Empty when there are no pages, `[1]` for one page.
    static func pageNumbers(current: Int, total: Int) -> [Int] {
        guard total > 0 else { return [] }
        guard total > 1 else { return [1] }
        let page = clamp(current, total: total)
        let first = max(1, page - radius)
        let last = page >= total - radius ? total : page + radius
        return Array(first...last)
    }
}
