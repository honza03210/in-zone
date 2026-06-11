import SwiftUI

struct AnchorsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var simulator: SimulatorService

    var body: some View {
        NavigationStack {
            List {
                if simulator.isActive {
                    Section {
                        Label(
                            "Simulator mode \u{2014} 4 virtual anchors pre-connected",
                            systemImage: "play.desktopcomputer"
                        )
                        .foregroundStyle(.orange)
                    }
                } else if bleManager.bluetoothState != .poweredOn {
                    Section {
                        Label(
                            "Bluetooth is \(bleManager.bluetoothStateText)",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                if sortedAnchors.isEmpty && !bleManager.isScanning && !simulator.isActive {
                    Section {
                        Text("Tap Scan to discover nearby anchors.")
                            .foregroundStyle(.secondary)
                    }
                }

                if bleManager.isScanning && sortedAnchors.isEmpty {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Scanning...")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    }
                }

                if !sortedAnchors.isEmpty {
                    Section("Anchors") {
                        ForEach(sortedAnchors) { anchor in
                            AnchorRow(anchor: anchor)
                        }
                    }
                }
            }
            .navigationTitle("Anchors")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(bleManager.isScanning ? "Stop" : "Scan") {
                        if bleManager.isScanning {
                            bleManager.stopScanning()
                        } else {
                            bleManager.startScanning()
                        }
                    }
                    .disabled(bleManager.bluetoothState != .poweredOn)
                }
            }
        }
    }

    private var sortedAnchors: [Anchor] {
        bleManager.anchors.values.sorted { a, b in
            if a.state != b.state { return a.state.sortOrder < b.state.sortOrder }
            return a.rssi > b.rssi
        }
    }
}

// MARK: - Anchor Row

private struct AnchorRow: View {
    let anchor: Anchor
    @EnvironmentObject var bleManager: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                Text(anchor.displayName)
                    .font(.headline)
                Spacer()
                Text("\(anchor.rssi) dBm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if anchor.anchorId != 0xFF {
                    Label("ID \(anchor.anchorId)", systemImage: "number")
                        .font(.caption)
                }
                if !anchor.firmwareVersion.isEmpty {
                    Label("v\(anchor.firmwareVersion)", systemImage: "gearshape")
                        .font(.caption)
                }
                Text(anchor.state.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let dist = anchor.distance {
                Text(String(format: "%.2f m", dist))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.blue)
            }

            HStack {
                if anchor.isConnected {
                    Button("Disconnect") {
                        bleManager.disconnect(anchor.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("Identify") {
                        bleManager.identify(anchor.id)
                    }
                    .buttonStyle(.bordered)
                } else if anchor.state == .connecting {
                    ProgressView()
                } else {
                    Button("Connect") {
                        bleManager.connect(anchor.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var stateIcon: String {
        switch anchor.state {
        case .ranging:    return "antenna.radiowaves.left.and.right"
        case .connected:  return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .discovered: return "circle"
        }
    }

    private var stateColor: Color {
        switch anchor.state {
        case .ranging:    return .green
        case .connected:  return .blue
        case .connecting: return .orange
        case .discovered: return .secondary
        }
    }
}
