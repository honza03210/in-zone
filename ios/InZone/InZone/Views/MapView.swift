import SwiftUI

struct MapView: View {
    @EnvironmentObject var zoneStore: ZoneStore
    @EnvironmentObject var zoneEngine: ZoneEngine
    @EnvironmentObject var scheduler: RangingScheduler
    @EnvironmentObject var simulator: SimulatorService
    @EnvironmentObject var roomStore: RoomStore

    @State private var showRoomSetup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                zoneBanner
                    .animation(.easeInOut, value: zoneEngine.currentZone?.id)

                if !roomStore.hasSavedLayout && !simulator.isActive {
                    roomSetupHint
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                RoomCanvasView()
                    .padding()

                if !zoneStore.zones.isEmpty {
                    zoneLegend
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                if simulator.isActive && simulator.isRanging {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.caption2)
                        Text("Drag on the map to move the phone")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("Map")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRoomSetup = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showRoomSetup) {
                RoomSetupView()
            }
        }
    }

    // MARK: - First-run hint

    private var roomSetupHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Room layout not set up")
                    .font(.caption.bold())
                Text("Positions on this map assume the default 5\u{00D7}4 m room. Set your real dimensions and anchor spots first.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set Up") { showRoomSetup = true }
                .font(.caption.bold())
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Zone banner

    @ViewBuilder
    private var zoneBanner: some View {
        if let zone = zoneEngine.currentZone {
            HStack {
                Circle()
                    .fill(Zone.color(for: zone.colorName))
                    .frame(width: 14, height: 14)
                Text(zone.name)
                    .font(.headline)
                Spacer()
                Text(String(format: "%.0f%%", zoneEngine.zoneConfidence * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Zone.color(for: zone.colorName).opacity(0.12))
        }
    }

    // MARK: - Legend

    private var zoneLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(zoneStore.zones) { zone in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Zone.color(for: zone.colorName))
                            .frame(width: 8, height: 8)
                        Text(zone.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
