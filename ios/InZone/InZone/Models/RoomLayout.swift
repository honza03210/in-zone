import Foundation
import os

struct AnchorPlacement: Identifiable, Codable, Equatable {
    var id: UInt8
    var x: Float
    var y: Float
    var label: String
}

struct RoomLayout: Codable, Equatable {
    var width: Float
    var height: Float
    var anchors: [AnchorPlacement]

    init(width: Float = 6.0, height: Float = 5.0, anchors: [AnchorPlacement]? = nil) {
        self.width = width
        self.height = height
        self.anchors = anchors ?? Self.defaultAnchors(width: width, height: height)
    }

    /// Default placement: anchors set slightly IN from the walls, not jammed
    /// into the geometric corners — real anchors are mounted within the room.
    /// The user drags them to their actual spots in Room Setup.
    static func defaultAnchors(width: Float, height: Float) -> [AnchorPlacement] {
        let mx = min(0.5, width * 0.1)
        let my = min(0.5, height * 0.1)
        return [
            AnchorPlacement(id: 0, x: mx,          y: my,          label: "A0"),
            AnchorPlacement(id: 1, x: width - mx,  y: my,          label: "A1"),
            AnchorPlacement(id: 2, x: width - mx,  y: height - my, label: "A2"),
            AnchorPlacement(id: 3, x: mx,          y: height - my, label: "A3"),
        ]
    }

    func anchor(for id: UInt8) -> AnchorPlacement? {
        anchors.first { $0.id == id }
    }
}

class RoomStore: ObservableObject {
    @Published var layout: RoomLayout
    /// False until the user saves a layout — drives the first-run hint
    @Published private(set) var hasSavedLayout: Bool

    private let fileURL: URL
    private let log = Logger(subsystem: "com.inzone", category: "RoomStore")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("room_layout.json")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(RoomLayout.self, from: data) {
            layout = saved
            hasSavedLayout = true
            log.info("Loaded room layout: \(saved.width)×\(saved.height)m, \(saved.anchors.count) anchors")
        } else {
            layout = RoomLayout()
            hasSavedLayout = false
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(layout)
            try data.write(to: fileURL, options: .atomic)
            hasSavedLayout = true
        } catch {
            log.error("Save failed: \(error)")
        }
    }

    func resetToDefaults() {
        layout = RoomLayout()
        save()
    }
}
