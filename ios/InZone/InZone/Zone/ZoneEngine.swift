import Foundation
import os

class ZoneEngine: ObservableObject {
    @Published var currentZone: Zone?
    @Published var zoneConfidence: Float = 0
    @Published var isDetecting = false

    var hysteresisMargin: Float = 0.5
    var dwellTime: TimeInterval = 1.0
    var maxZoneRadius: Float = 3.0

    private var candidateZone: Zone?
    private var candidateEntryTime: Date?
    private let log = Logger(subsystem: "com.inzone", category: "Zone")

    func update(distances: [UInt8: Float], zones: [Zone]) {
        guard isDetecting, !zones.isEmpty, !distances.isEmpty else { return }

        var bestZone: Zone?
        var bestScore: Float = .infinity
        var secondBest: Float = .infinity

        for zone in zones {
            let score = fingerprintDistance(current: distances, reference: zone.fingerprint)
            if score < bestScore {
                secondBest = bestScore
                bestScore = score
                bestZone = zone
            } else if score < secondBest {
                secondBest = score
            }
        }

        guard let candidate = bestZone, bestScore < maxZoneRadius else {
            candidateZone = nil
            candidateEntryTime = nil
            if currentZone != nil {
                currentZone = nil
                zoneConfidence = 0
            }
            return
        }

        let margin = secondBest.isFinite ? secondBest - bestScore : maxZoneRadius
        zoneConfidence = min(1, margin / max(hysteresisMargin, 0.01))

        if candidate.id == currentZone?.id {
            return
        }

        guard margin >= hysteresisMargin else { return }

        if candidateZone?.id == candidate.id {
            if let entry = candidateEntryTime,
               Date().timeIntervalSince(entry) >= dwellTime {
                log.info("Zone changed to \(candidate.name)")
                currentZone = candidate
                candidateZone = nil
                candidateEntryTime = nil
            }
        } else {
            candidateZone = candidate
            candidateEntryTime = Date()
        }
    }

    private func fingerprintDistance(current: [UInt8: Float],
                                     reference: [String: DistanceStats]) -> Float {
        var sumSq: Float = 0
        var count: Float = 0

        for (key, stats) in reference {
            guard let anchorId = UInt8(key),
                  let dist = current[anchorId] else { continue }
            let diff = dist - stats.mean
            sumSq += diff * diff
            count += 1
        }

        guard count > 0 else { return .infinity }
        return sqrt(sumSq / count)
    }
}
