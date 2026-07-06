import SwiftUI

/// Small pixel-style audio waveform. Shared by the history list card and the
/// voice chat bubble so bar rendering lives in exactly one place.
struct WaveformView: View {
    let bars: [CGFloat]
    var color: Color = Bocil.cardBorder
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2
    var height: CGFloat = 26

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                Rectangle()
                    .fill(color)
                    .frame(width: barWidth, height: min(h, height))
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

extension WaveformView {
    /// Deterministic mock waveform derived from a seed (e.g. a message id hash)
    /// so bars stay stable across redraws. Used until real audio analysis exists.
    static func mockBars(seed: Int, count: Int = 18, in range: ClosedRange<CGFloat> = 6...24) -> [CGFloat] {
        var value = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15
        return (0..<count).map { _ in
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let unit = CGFloat(value >> 33) / CGFloat(UInt32.max)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }
}
