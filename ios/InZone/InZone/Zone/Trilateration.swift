import Foundation

enum Trilateration {

    /// Estimates a 2D position from anchor distances. Measurements with a
    /// known variance are down-weighted proportionally; live readings
    /// without one are treated as equally reliable.
    static func estimatePosition(
        distances: [UInt8: Float],
        anchors: [AnchorPlacement],
        variances: [UInt8: Float] = [:]
    ) -> CGPoint? {
        var m: [Measurement] = []
        for anchor in anchors {
            if let d = distances[anchor.id], d > 0 {
                m.append(Measurement(x: anchor.x, y: anchor.y, d: d,
                                     v: max(variances[anchor.id] ?? 0, 0)))
            }
        }
        guard m.count >= 2 else { return nil }
        if m.count == 2 { return weightedCentroid(m) }
        return leastSquares(m) ?? weightedCentroid(m)
    }

    static func estimateFromFingerprint(
        _ fingerprint: [String: DistanceStats],
        anchors: [AnchorPlacement]
    ) -> CGPoint? {
        var distances: [UInt8: Float] = [:]
        var variances: [UInt8: Float] = [:]
        for (key, stats) in fingerprint {
            if let id = UInt8(key) {
                distances[id] = stats.mean
                variances[id] = stats.variance
            }
        }
        return estimatePosition(distances: distances, anchors: anchors,
                                variances: variances)
    }

    // MARK: - Internal

    private struct Measurement {
        let x: Float
        let y: Float
        let d: Float
        let v: Float
    }

    // ε keeps zero-variance weights finite
    private static let varianceFloor: Float = 0.01

    private static func weightedCentroid(_ m: [Measurement]) -> CGPoint {
        var wx: Float = 0, wy: Float = 0, wt: Float = 0
        for a in m {
            let w: Float = 1.0 / ((a.v + varianceFloor) * max(a.d * a.d, 0.01))
            wx += a.x * w
            wy += a.y * w
            wt += w
        }
        return CGPoint(x: CGFloat(wx / wt), y: CGFloat(wy / wt))
    }

    private static func leastSquares(_ m: [Measurement]) -> CGPoint? {
        // The most reliable measurement anchors the linearization
        guard let refIdx = m.indices.min(by: { m[$0].v < m[$1].v }) else { return nil }
        let ref = m[refIdx]

        var ata00: Float = 0, ata01: Float = 0, ata11: Float = 0
        var atb0: Float = 0, atb1: Float = 0

        for i in m.indices where i != refIdx {
            let w = 1.0 / (m[i].v + ref.v + varianceFloor)
            let a = 2 * (m[i].x - ref.x)
            let b = 2 * (m[i].y - ref.y)
            let c = ref.d * ref.d - m[i].d * m[i].d
                    + m[i].x * m[i].x - ref.x * ref.x
                    + m[i].y * m[i].y - ref.y * ref.y

            ata00 += w * a * a
            ata01 += w * a * b
            ata11 += w * b * b
            atb0 += w * a * c
            atb1 += w * b * c
        }

        let det = ata00 * ata11 - ata01 * ata01
        guard abs(det) > 1e-6 else { return nil }

        let x = (ata11 * atb0 - ata01 * atb1) / det
        let y = (ata00 * atb1 - ata01 * atb0) / det
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}
