import SwiftUI

struct LiveView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var scheduler: RangingScheduler
    @EnvironmentObject var zoneEngine: ZoneEngine
    @EnvironmentObject var zoneStore: ZoneStore
    @EnvironmentObject var simulator: SimulatorService

    @State private var showDebug = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                zoneBanner
                    .animation(.easeInOut, value: zoneEngine.currentZone?.id)

                if simulator.isActive || scheduler.isRunning {
                    RoomCanvasView(compact: true)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        rangingControls
                        anchorCards
                        if showDebug { debugSection }
                    }
                    .padding()
                }
            }
            .navigationTitle("Live")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(showDebug ? "Hide Debug" : "Debug") {
                        showDebug.toggle()
                    }
                }
            }
        }
    }

    // MARK: - Zone Banner

    @ViewBuilder
    private var zoneBanner: some View {
        if let zone = zoneEngine.currentZone {
            HStack {
                Circle()
                    .fill(Zone.color(for: zone.colorName))
                    .frame(width: 16, height: 16)
                Text(zone.name)
                    .font(.title2.bold())
                Spacer()
                Text(String(format: "%.0f%%", zoneEngine.zoneConfidence * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Zone.color(for: zone.colorName).opacity(0.15))
        } else if zoneEngine.isDetecting {
            HStack {
                Image(systemName: "questionmark.circle")
                Text("No zone detected")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Controls

    private var rangingControls: some View {
        VStack(spacing: 12) {
            HStack {
                if scheduler.isRunning {
                    Button(role: .destructive) {
                        if simulator.isActive {
                            simulator.stopRanging()
                        } else {
                            scheduler.stop()
                        }
                        zoneEngine.isDetecting = false
                    } label: {
                        Label("Stop Ranging", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        if simulator.isActive {
                            simulator.startRanging()
                        } else {
                            let ids = bleManager.connectedAnchorIds
                            guard !ids.isEmpty else { return }
                            scheduler.start(anchors: ids, bleManager: bleManager)
                        }
                    } label: {
                        Label("Start Ranging", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!simulator.isActive && bleManager.connectedAnchorIds.isEmpty)
                }
            }

            if scheduler.isRunning {
                Toggle("Zone Detection", isOn: $zoneEngine.isDetecting)
                    .disabled(zoneStore.zones.isEmpty)
            }
        }
    }

    // MARK: - Anchor Cards

    private var anchorCards: some View {
        let connected = bleManager.anchors.values
            .filter(\.isConnected)
            .sorted { $0.anchorId < $1.anchorId }

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(connected) { anchor in
                AnchorCard(anchor: anchor)
            }
        }
    }

    // MARK: - Debug

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug")
                .font(.headline)

            LabeledContent("Sweeps") {
                Text("\(scheduler.sweepCount)")
                    .monospacedDigit()
            }
            LabeledContent("Active Sessions") {
                Text("\(scheduler.currentDistances.count)")
            }
            LabeledContent("Zones Loaded") {
                Text("\(zoneStore.zones.count)")
            }

            if let zone = zoneEngine.currentZone {
                LabeledContent("Current Zone") { Text(zone.name) }
            }
            if zoneEngine.isDetecting {
                LabeledContent("Confidence") {
                    Text(String(format: "%.1f%%", zoneEngine.zoneConfidence * 100))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Anchor Card

private struct AnchorCard: View {
    let anchor: Anchor

    var body: some View {
        VStack(spacing: 8) {
            Text(anchor.displayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let dist = anchor.distance {
                Text(String(format: "%.2f", dist))
                    .font(.system(.title, design: .monospaced, weight: .semibold))
                Text("m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.title)
                    .foregroundStyle(.quaternary)
            }

            if anchor.state == .ranging {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
