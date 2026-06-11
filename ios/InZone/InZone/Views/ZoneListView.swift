import SwiftUI

struct ZoneListView: View {
    @EnvironmentObject var zoneStore: ZoneStore
    @EnvironmentObject var scheduler: RangingScheduler
    @State private var showingSetup = false

    var body: some View {
        NavigationStack {
            List {
                if zoneStore.zones.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No zones captured yet.")
                                .font(.headline)
                            Text("Start ranging on the Live tab, then come back here and tap + to capture a zone.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    ForEach(zoneStore.zones) { zone in
                        ZoneRow(zone: zone)
                    }
                    .onDelete { offsets in
                        zoneStore.remove(at: offsets)
                    }
                }
            }
            .navigationTitle("Zones")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSetup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!scheduler.isRunning)
                }
            }
            .sheet(isPresented: $showingSetup) {
                ZoneSetupView()
            }
        }
    }
}

// MARK: - Zone Row

private struct ZoneRow: View {
    let zone: Zone

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Zone.color(for: zone.colorName))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("\(zone.fingerprint.count) anchors")
                    Text(zone.capturedAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                ForEach(
                    zone.fingerprint.sorted(by: { $0.key < $1.key }),
                    id: \.key
                ) { key, stats in
                    Text(String(format: "A%@: %.1fm", key, stats.mean))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
