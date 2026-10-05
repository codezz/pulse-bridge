import PulseKit
import SwiftUI

/// Daily step goal shown on the Steps card and charts.
let stepGoal = 10_000

/// Large rounded numbers at a design size that still follows Dynamic Type.
private struct NumberFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
    }
}

extension View {
    func numberFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        modifier(NumberFont(size: size, weight: weight))
    }
}

/// A ring filled to `progress` (0...1, more is shown full) with a label in the middle.
struct ProgressRing<Label: View>: View {
    let progress: Double
    let color: Color
    var size: CGFloat = 64
    @ViewBuilder let label: Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: size / 9)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

extension Metric {
    var title: String {
        switch self {
        case .heartRate: "Heart rate"
        case .restingHeartRate: "Resting heart rate"
        case .hrv: "HRV"
        case .spo2: "Blood oxygen"
        case .steps: "Steps"
        case .temperature: "Temperature"
        }
    }

    var unit: String {
        switch self {
        case .heartRate, .restingHeartRate: "bpm"
        case .hrv: "ms"
        case .spo2: "%"
        case .steps: "steps"
        case .temperature: "°C"
        }
    }

    var systemImage: String {
        switch self {
        case .heartRate: "heart.fill"
        case .restingHeartRate: "bed.double.fill"
        case .hrv: "waveform.path.ecg"
        case .spo2: "lungs.fill"
        case .steps: "figure.walk"
        case .temperature: "thermometer.medium"
        }
    }

    var color: Color {
        switch self {
        case .heartRate: Palette.heart
        case .restingHeartRate: Palette.resting
        case .hrv: Palette.hrv
        case .spo2: Palette.oxygen
        case .steps: Palette.steps
        case .temperature: Palette.temperature
        }
    }

    func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        return self == .temperature ? String(format: "%.1f", value) : Int(value.rounded()).formatted()
    }
}
