import SwiftUI

enum DaySpan: String, CaseIterable, Identifiable {
    case day = "D", week = "W", month = "M", sixMonths = "6M"
    var id: String { rawValue }

    /// The segment label in the app's language ("D" / "Z").
    var label: String {
        switch self {
        case .day: String(localized: "D", comment: "Range: one day")
        case .week: String(localized: "W", comment: "Range: one week")
        case .month: String(localized: "M", comment: "Range: one month")
        case .sixMonths: String(localized: "6M", comment: "Range: six months")
        }
    }
    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .sixMonths: 182
        }
    }
}

/// D / W / M picker with previous / next, shared by the detail views.
struct DayRangeHeader: View {
    @Binding var span: DaySpan
    @Binding var day: Date
    /// First loaded day, for the "1 Oct - 7 Oct" title.
    let firstDay: Date?
    /// Sleep has no 6M (one bar per night would be unreadable).
    var spans: [DaySpan] = DaySpan.allCases

    var body: some View {
        Picker("Range", selection: $span) {
            ForEach(spans) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(day))
        }
        .buttonStyle(.borderless)
    }

    private var title: String {
        let last = day.formatted(date: .abbreviated, time: .omitted)
        guard span != .day, let firstDay else { return last }
        return "\(firstDay.formatted(.dateTime.day().month())) - \(last)"
    }

    private func move(_ direction: Int) {
        let step = span == .day ? 1 : span.days
        if let next = Calendar.current.date(byAdding: .day, value: direction * step, to: day) {
            day = min(next, Calendar.current.startOfDay(for: .now))
        }
    }
}
