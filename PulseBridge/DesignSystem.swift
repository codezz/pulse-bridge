import Charts
import SwiftUI

/// One colour per kind of data, used by cards, tiles, rings and charts.
enum Palette {
    static let sleep = Color.indigo
    static let steps = Color.green
    static let heart = Color.red
    static let resting = Color.pink
    static let hrv = Color.blue
    static let oxygen = Color.cyan
    static let challenge = Color.orange
    static let activity = Color.mint
    static let band = Color.gray
    static let temperature = Color(red: 1.0, green: 0.42, blue: 0.29)
}

extension View {
    /// The rounded background every card and tile shares.
    func cardBackground(cornerRadius: CGFloat = 20) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Shared card chrome, Health style: a coloured symbol and title, an optional caption (e.g. the
/// time of the latest value) and control on the right, then the content.
struct Card<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    var color: Color = .gray
    var caption: String?
    var chevron = false
    @ViewBuilder let content: Content
    @ViewBuilder var accessory: Accessory

    /// A literal title is looked up in the String Catalog.
    init(title: LocalizedStringResource, systemImage: String, color: Color = .gray, caption: String? = nil, chevron: Bool = false,
         @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.init(title: String(localized: title), systemImage: systemImage, color: color, caption: caption, chevron: chevron,
                  content: content, accessory: accessory)
    }

    /// Text that is already localized (or user data) is shown as is. Disfavored, so literals pick
    /// the catalog init above (as with `Text`).
    @_disfavoredOverload
    init<S: StringProtocol>(title: S, systemImage: String, color: Color = .gray, caption: String? = nil, chevron: Bool = false,
                            @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.title = String(title)
        self.systemImage = systemImage
        self.color = color
        self.caption = caption
        self.chevron = chevron
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
                Spacer()
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
                accessory
                if chevron {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }
}

extension Card where Accessory == EmptyView {
    init(title: LocalizedStringResource, systemImage: String, color: Color = .gray, caption: String? = nil, chevron: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.init(title: String(localized: title), systemImage: systemImage, color: color, caption: caption, chevron: chevron,
                  content: content, accessory: { EmptyView() })
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, systemImage: String, color: Color = .gray, caption: String? = nil, chevron: Bool = false,
                            @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, color: color, caption: caption, chevron: chevron,
                  content: content, accessory: { EmptyView() })
    }
}

/// Half-width tile for a 2-column grid: title, big number, one caption line, optional sparkline.
struct MetricTile: View {
    let title: String
    let systemImage: String
    let color: Color
    let value: String
    var unit: String = ""
    var caption: String?
    var sparkline: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(color)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).numberFont(26).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if sparkline.count > 1 {
                Sparkline(values: sparkline, color: color).frame(height: 28)
            }
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

/// A small line with a soft area under it, no axes.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("i", point.offset), y: .value("v", point.element))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("i", point.offset), y: .value("v", point.element))
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

/// Concentric Fitness-style rings, outermost first. Progress over 1 draws a second, darker lap.
struct ActivityRings: View {
    struct Ring: Identifiable {
        let id: String
        let progress: Double
        let color: Color
        /// What VoiceOver says for it, e.g. "score 82" or "8,240 steps".
        var spoken: String
    }

    let rings: [Ring]
    var size: CGFloat = 120
    @State private var shown = false

    var body: some View {
        let width = size / 9
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = CGFloat(index) * (width + 3)
                ZStack {
                    Circle().stroke(ring.color.opacity(0.18), lineWidth: width)
                    Circle()
                        .trim(from: 0, to: shown ? min(1, max(0, ring.progress)) : 0)
                        .stroke(LinearGradient(colors: [ring.color.opacity(0.75), ring.color], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if ring.progress > 1 {
                        Circle()
                            .trim(from: 0, to: shown ? min(1, ring.progress - 1) : 0)
                            .stroke(ring.color.mix(with: .black, by: 0.25), style: StrokeStyle(lineWidth: width, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
                .padding(inset)
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = true } }
        .animation(.easeOut(duration: 0.6), value: rings.map(\.progress))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rings.map { "\($0.id) \($0.spoken)" }.joined(separator: ", "))
        .accessibilityHidden(rings.isEmpty)
    }
}

/// Large bold section header, like Health's "Highlights".
struct SectionTitle: View {
    let title: String

    init(_ title: LocalizedStringResource) {
        self.title = String(localized: title)
    }

    var body: some View {
        Text(title).font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// A short sparkle burst and a success haptic when `done` changes to true while the view is on
/// screen and `context` stays the same (so loading data, picking another day or coming back from
/// another tab doesn't count as reaching the goal).
private struct Celebration<Context: Hashable>: ViewModifier {
    let done: Bool
    let context: Context
    @State private var burst = false
    @State private var fired = 0
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Snapshot: Equatable {
        let done: Bool
        let context: Context
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if burst && !reduceMotion {
                    ZStack {
                        ForEach(0..<8, id: \.self) { index in
                            Image(systemName: "sparkle")
                                .foregroundStyle(.yellow)
                                .offset(x: cos(Double(index) * .pi / 4) * 70, y: sin(Double(index) * .pi / 4) * 70)
                        }
                    }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .sensoryFeedback(.success, trigger: fired)
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onChange(of: Snapshot(done: done, context: context)) { old, new in
                guard visible, old.context == new.context, !old.done, new.done else { return }
                fired += 1
                withAnimation(.spring(duration: 0.5)) { burst = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(.easeOut(duration: 0.4)) { burst = false }
                }
            }
    }
}

extension View {
    func celebrates(_ done: Bool, context: some Hashable) -> some View { modifier(Celebration(done: done, context: context)) }
}
