#if DEBUG
import Foundation

/// Shared sample data for `#Preview` blocks and the README screenshot
/// generator (`ScreenshotGenTests`). DEBUG-only: never in release builds.
enum HeartRateKitSamples {
    /// A deterministic ~60s BPM trend for chart/sparkline previews.
    static var recent: [(t: Date, bpm: Int)] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<30).map { i in
            (t: base.addingTimeInterval(Double(i) * 2),
             bpm: 128 + Int((12.0 * sin(Double(i) / 4)).rounded()))
        }
    }
}
#endif
