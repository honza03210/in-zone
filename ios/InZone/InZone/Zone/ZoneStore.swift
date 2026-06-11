import Foundation
import os

class ZoneStore: ObservableObject {
    @Published var zones: [Zone] = []

    private let fileURL: URL
    private let log = Logger(subsystem: "com.inzone", category: "ZoneStore")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("zones.json")
        load()
    }

    func add(_ zone: Zone) {
        zones.append(zone)
        save()
    }

    func remove(at offsets: IndexSet) {
        zones.remove(atOffsets: offsets)
        save()
    }

    func remove(id: UUID) {
        zones.removeAll { $0.id == id }
        save()
    }

    func update(_ zone: Zone) {
        if let idx = zones.firstIndex(where: { $0.id == zone.id }) {
            zones[idx] = zone
            save()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(zones)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            zones = try JSONDecoder().decode([Zone].self, from: data)
            log.info("Loaded \(self.zones.count) zones")
        } catch {
            log.error("Load failed: \(error)")
        }
    }
}
