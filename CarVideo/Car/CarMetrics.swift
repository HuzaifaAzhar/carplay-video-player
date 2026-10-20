import SwiftUI

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T {
    min(max(value, low), high)
}

/// Sizes for the car screen, derived from the area the app gets. Car screens range from 800×480 (about
/// 400×240 pt) to ultra-wide 1920×720 and taller portrait units, so everything scales with the shorter side
/// and touch targets never go below 40 pt.
struct CarMetrics {
    let size: CGSize

    var short: CGFloat { max(1, min(size.width, size.height)) }
    var gap: CGFloat { clamp(short * 0.035, 6, 14) }
    var barHeight: CGFloat { clamp(short * 0.17, 40, 60) }
    var titleFont: CGFloat { clamp(short * 0.075, 15, 26) }
    var bodyFont: CGFloat { clamp(short * 0.058, 12, 19) }
    var captionFont: CGFloat { clamp(short * 0.047, 10, 15) }
    var button: CGFloat { clamp(short * 0.17, 40, 60) }
    var bigButton: CGFloat { clamp(short * 0.26, 52, 96) }
    var corner: CGFloat { clamp(short * 0.04, 6, 14) }

    /// Room for a tile's title and detail line under its thumbnail.
    var tileTextHeight: CGFloat { bodyFont * 1.3 + captionFont * 1.3 + 6 }

    /// The grid area under the top bar.
    var gridArea: CGSize {
        CGSize(width: max(0, size.width - gap * 2), height: max(0, size.height - gap * 3 - barHeight))
    }
}

/// How many video tiles fit on one page of the car screen. Pages turn with buttons (and swipes, where the
/// car supports them) because many head units only report taps, not drags.
struct CarGridLayout: Equatable {
    var columns: Int
    var rows: Int
    var tileWidth: CGFloat
    var thumbHeight: CGFloat
    var gap: CGFloat

    var perPage: Int { columns * rows }

    init(metrics: CarMetrics) {
        let area = metrics.gridArea
        let gap = metrics.gap
        let textHeight = metrics.tileTextHeight
        // Tiles and thumbnails big enough to read and hit at arm's length.
        let minThumb = max(56, metrics.short * 0.3)
        let minWidth = max(110, metrics.short * 0.45)
        var best: (columns: Int, rows: Int, width: CGFloat, thumb: CGFloat)?
        var largest = (columns: 2, rows: 1, width: CGFloat(100), thumb: CGFloat(0))
        for rows in 1...3 {
            for columns in 2...6 {
                let width = (area.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                let tileHeight = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                // Thumbnails may grow from 16:9 up to 4:3 to use the height the screen has.
                let thumb = min(width * 3 / 4, tileHeight - textHeight)
                guard width >= minWidth, thumb > 0 else { continue }
                if thumb > largest.thumb { largest = (columns, rows, width, thumb) }
                guard thumb >= minThumb else { continue }
                if let current = best {
                    let count = columns * rows, currentCount = current.columns * current.rows
                    if count > currentCount || (count == currentCount && thumb > current.thumb) {
                        best = (columns, rows, width, thumb)
                    }
                } else {
                    best = (columns, rows, width, thumb)
                }
            }
        }
        let chosen = best ?? largest
        columns = chosen.columns
        rows = chosen.rows
        tileWidth = chosen.width
        thumbHeight = max(chosen.thumb, 30)
        self.gap = gap
    }
}
