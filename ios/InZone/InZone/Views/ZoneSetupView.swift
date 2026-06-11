import SwiftUI

struct ZoneSetupView: View {
    @EnvironmentObject var scheduler: RangingScheduler
    @EnvironmentObject var zoneStore: ZoneStore
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var selectedColor = "blue"
    @State private var isCapturing = false
    @State private var captureProgress: Double = 0
    @State private var samples: [UInt8: [Float]] = [:]
    @State private var capturedFingerprint: [String: DistanceStats]?

    private let captureDuration: TimeInterval = 2.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Zone Name") {
                    TextField("e.g. Desk, Bed, Window", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Zone.availableColors, id: \.self) { color in
                                Circle()
                                    .fill(Zone.color(for: color))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(.primary, lineWidth: selectedColor == color ? 2.5 : 0)
                                    )
                                    .onTapGesture { selectedColor = color }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Current Distances") {
                    if scheduler.currentDistances.isEmpty {
                        Text("Start ranging on the Live tab first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(
                            scheduler.currentDistances.sorted(by: { $0.key < $1.key }),
                            id: \.key
                        ) { aid, dist in
                            HStack {
                                Label("Anchor \(aid)", systemImage: "antenna.radiowaves.left.and.right")
                                Spacer()
                                Text(String(format: "%.2f m", dist))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section("Capture") {
                    if isCapturing {
                        VStack(spacing: 8) {
                            ProgressView(value: captureProgress)
                            Text("Hold still\u{2026}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let fp = capturedFingerprint {
                        ForEach(fp.sorted(by: { $0.key < $1.key }), id: \.key) { key, stats in
                            HStack {
                                Text("Anchor \(key)")
                                Spacer()
                                Text(String(
                                    format: "%.2f m (\u{00B1}%.2f, n=%d)",
                                    stats.mean, sqrt(stats.variance), stats.sampleCount
                                ))
                                .font(.caption.monospacedDigit())
                            }
                        }
                        Button("Recapture") { startCapture() }
                    } else {
                        Button("Capture Position") { startCapture() }
                            .disabled(!scheduler.isRunning || scheduler.currentDistances.isEmpty)
                    }
                }
            }
            .navigationTitle("New Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveZone() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || capturedFingerprint == nil)
                }
            }
            .interactiveDismissDisabled(isCapturing)
        }
    }

    // MARK: - Capture

    private func startCapture() {
        isCapturing = true
        captureProgress = 0
        samples = [:]
        capturedFingerprint = nil

        let startTime = Date()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            captureProgress = min(elapsed / captureDuration, 1.0)

            for (aid, dist) in scheduler.currentDistances {
                samples[aid, default: []].append(dist)
            }

            if elapsed >= captureDuration {
                timer.invalidate()
                isCapturing = false
                computeFingerprint()
            }
        }
    }

    private func computeFingerprint() {
        var fp: [String: DistanceStats] = [:]
        for (aid, dists) in samples where !dists.isEmpty {
            let mean = dists.reduce(0, +) / Float(dists.count)
            let variance = dists.map { ($0 - mean) * ($0 - mean) }
                .reduce(0, +) / Float(dists.count)
            fp[String(aid)] = DistanceStats(
                mean: mean, variance: variance, sampleCount: dists.count
            )
        }
        capturedFingerprint = fp
    }

    private func saveZone() {
        guard let fp = capturedFingerprint else { return }
        let zone = Zone(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            fingerprint: fp,
            capturedAt: Date(),
            colorName: selectedColor
        )
        zoneStore.add(zone)
        dismiss()
    }
}
