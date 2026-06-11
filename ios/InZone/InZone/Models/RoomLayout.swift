import Foundation
import os

struct AnchorPlacement: Identifiable, Codable, Equatable {
    var id: UInt8
    var x: Float
    var y: Float
    var label: String
}

struct RoomLayout: Codable, Equatable {
    var width: Float = 5.0
    var height: Float = 4.0
    var anchors: [AnchorPlacement] = Self.defaultAnchors

    static let defaultAnchors: [AnchorPlacement] = [
        AnchorPlacement(id: 0, x: 0, y: 0, label: "door"),
        AnchorPlacement(id: 1, x: 5, y: 0, label: "window"),
        AnchorPlacement(id: 2, x: 5, y: 4, label: "desk"),
        AnchorPlacement(id: 3, x: 0, y: 4, label: "bed"),
    ]

    func anchor(for id: UInt8) -> AnchorPlacement? {
        anchors.first { $0.id == id }
    }
}

class RoomStore: ObservableObject {
    @Published var layout: RoomLayout

    private let fileURL: URL
    private let log = Logger(subsystem: "com.inzone", category: "RoomStore")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("room_layout.json")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(RoomLayout.self, from: data) {
            layout = saved
            log.info("Loaded room layout: \(saved.width)×\(saved.height)m, \(saved.anchors.count) anchors")
        } else {
            layout = RoomLayout()
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(layout)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Save failed: \(error)")
        }
    }

    func resetToDefaults() {
        layout = RoomLayout()
        save()
    }
}
