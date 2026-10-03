import PulseKit
import SwiftUI

struct ProfileView: View {
    let coordinator: SyncCoordinator
    @State private var birthYear = 1985
    @State private var sex = Sex.male
    @State private var height = 175
    @State private var weight = 75
    @State private var hr: HeartRateProfile?

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        Form {
            Section("Profile") {
                Picker("Birth year", selection: $birthYear) {
                    ForEach((currentYear - 100...currentYear - 10).reversed(), id: \.self) { Text(String($0)).tag($0) }
                }
                Picker("Sex", selection: $sex) {
                    Text("Male").tag(Sex.male)
                    Text("Female").tag(Sex.female)
                }
                .pickerStyle(.segmented)
                Stepper("Height: \(height) cm", value: $height, in: 120...220)
                Stepper("Weight: \(weight) kg", value: $weight, in: 30...200)
                Button("Save") {
                    let step = coordinator.profile?.stepLengthCm ?? 70
                    Task {
                        await coordinator.saveProfile(UserProfile(birthYear: birthYear, sex: sex, heightCm: height,
                                                                  weightKg: weight, stepLengthCm: step))
                        hr = coordinator.heartRateProfile()
                    }
                }
            }
            if let hr {
                Section {
                    LabeledContent("Max heart rate", value: "\(hr.max) bpm")
                    Text(hr.maxSource == .measured ? "Highest heart rate held in the last 6 months."
                                                   : "From your age (208 - 0.7 x age); a harder effort will raise it.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Resting heart rate", value: "\(hr.resting) bpm")
                    Text(hr.restingIsDefault ? "Default until 3 nights of sleep data exist." : "Median of the last 14 nights.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("Heart rate")
                } footer: {
                    Text("Both update automatically from your band data.")
                }
                Section("Zones") {
                    ForEach(1...5, id: \.self) { zone in
                        let range = hr.zones.range(of: zone)
                        LabeledContent {
                            Text("\(range.lowerBound)-\(range.upperBound) bpm")
                        } label: {
                            Label { Text("Zone \(zone) · \(zoneName(zone))") } icon: { Circle().fill(zoneColor(zone)).frame(width: 10) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            if let p = coordinator.profile {
                birthYear = p.birthYear; sex = p.sex; height = p.heightCm; weight = p.weightKg
            }
            hr = coordinator.heartRateProfile()
        }
    }
}
