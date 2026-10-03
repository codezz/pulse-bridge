import PulseBLE
import SwiftUI

struct PairingView: View {
    let band: BandClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(band.discovered) { found in
                Button {
                    band.pair(found)
                    dismiss()
                } label: {
                    LabeledContent(found.name, value: "\(found.rssi) dBm")
                }
            }
            .overlay {
                if let problem = band.bluetoothProblem {
                    ContentUnavailableView(problem, systemImage: "exclamationmark.triangle")
                } else if band.discovered.isEmpty {
                    ContentUnavailableView(
                        "Looking for your band",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Keep the band close to the phone and make sure no other app is connected to it."))
                }
            }
            .navigationTitle("Pair band")
            .task { await band.startScan() }
            .onDisappear { band.stopScan() }
        }
    }
}
