import SwiftUI

// Live 24-bar waveform driven by a single smoothed 0...1 level. New samples
// enter from the right and scroll left; bars flatten toward zero as the level
// drops so silence reads as a near-flat line.
struct WaveformView: View {
    var level: CGFloat
    var color: Color

    private static let barCount = 24
    @State private var bars: [CGFloat] = Array(repeating: 0.04, count: WaveformView.barCount)

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2.5
            let totalSpacing = spacing * CGFloat(Self.barCount - 1)
            let barWidth = max(1.5, (geo.size.width - totalSpacing) / CGFloat(Self.barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(2, bars[index] * geo.size.height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .onChange(of: level) { _, newValue in
            advance(with: newValue)
        }
    }

    private func advance(with newLevel: CGFloat) {
        let clamped = min(1, max(0, newLevel))
        let value: CGFloat
        if clamped <= 0.03 {
            value = CGFloat.random(in: 0.02...0.06)
        } else {
            value = min(1, clamped * CGFloat.random(in: 0.65...1.0))
        }
        var next = bars
        next.removeFirst()
        next.append(value)
        withAnimation(.easeOut(duration: 0.08)) {
            bars = next
        }
    }
}
