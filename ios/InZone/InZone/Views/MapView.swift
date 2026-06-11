import SwiftUI

struct MapView: View {
    @EnvironmentObject var zoneStore: ZoneStore
    @EnvironmentObject var zoneEngine: ZoneEngine
    @EnvironmentObject var scheduler: RangingScheduler
    @EnvironmentObject var simulator: SimulatorService

    @State private var showRoomSetup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                zoneBanner
                    .animation(.easeInOut, value: zoneEngine.currentZone?.id)

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
