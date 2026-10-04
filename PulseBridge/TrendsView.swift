import PulseKit
import SwiftUI

/// Week and month views of every metric.
struct TrendsView: View {
    let service: SummaryService

    var body: some View {
        NavigationStack {
            List {
                NavigationLink(value: SummaryRoute.sleep) { Label("Sleep", systemImage: "moon.zzz.fill").foregroundStyle(Palette.sleep) }
                ForEach([Metric.steps, .restingHeartRate, .hrv, .heartRate, .spo2], id: \.self) { metric in
                    NavigationLink(value: SummaryRoute.metric(metric)) {
                        Label(metric.title, systemImage: metric.systemImage).foregroundStyle(metric.color)
                    }
                }
            }
            .navigationTitle("Trends")
            .summaryDestinations(service: service)
        }
    }
}
