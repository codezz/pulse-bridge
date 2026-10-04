import Charts
import SwiftUI

/// A point a chart can be read at: where to put the rule, and what the bubble says.
struct ScrubPoint: Equatable {
    let date: Date
    let label: String

    /// A reading at a time: "72 bpm · 14:32".
    static func time(_ date: Date, _ value: String) -> ScrubPoint {
        ScrubPoint(date: date, label: "\(value) · \(date.formatted(date: .omitted, time: .shortened))")
    }

    /// An hourly bar: rule in the middle of the hour, "820 steps · 14:00".
    static func hour(_ hour: Date, _ value: String) -> ScrubPoint {
        ScrubPoint(date: hour.addingTimeInterval(1800), label: "\(value) · \(hour.formatted(date: .omitted, time: .shortened))")
    }

    /// A daily bar: rule in the middle of the day, "7h 12m · Fri 3 Oct".
    static func day(_ day: Date, _ value: String) -> ScrubPoint {
        ScrubPoint(date: day.addingTimeInterval(43200), label: "\(value) · \(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
    }
}

extension View {
    /// Press and drag on a chart to see the nearest point's value under a vertical rule.
    func chartScrub(_ points: [ScrubPoint]) -> some View {
        modifier(ChartScrub(points: points))
    }
}

private struct ChartScrub: ViewModifier {
    let points: [ScrubPoint]
    @State private var selected: Date?
    @State private var bubbleWidth: CGFloat = 0

    private var nearest: ScrubPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $selected)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let point = nearest, let plot = proxy.plotFrame, let x = proxy.position(forX: point.date) {
                        let frame = geo[plot]
                        let xPos = frame.minX + x
                        let half = bubbleWidth / 2
                        // Keep the bubble inside the plot; center it when the plot is narrower.
                        let bubbleX = frame.width <= bubbleWidth ? frame.midX : min(max(xPos, frame.minX + half), frame.maxX - half)
                        Rectangle()
                            .fill(Color.secondary)
                            .frame(width: 1, height: frame.height)
                            .position(x: xPos, y: frame.midY)
                        Text(point.label)
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { bubbleWidth = $0 }
                            .opacity(bubbleWidth == 0 ? 0 : 1)   // hidden until measured, so it doesn't jump
                            .position(x: bubbleX, y: frame.minY + 10)
                    }
                }
                .allowsHitTesting(false)
            }
            // A tick per point, none when the finger lifts.
            .sensoryFeedback(trigger: nearest?.date) { _, new in new == nil ? nil : .selection }
    }
}
