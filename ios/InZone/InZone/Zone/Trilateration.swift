import Foundation

enum Trilateration {

    static func estimatePosition(
        distances: [UInt8: Float],
        anchors: [AnchorPlacement]
    ) -> CGPoint? {
        var m: [(x: Float, y: Float, d: Float)] = []
        for anchor in anchors {
            if let d = distances[anchor.id], d > 0 {
                m.append((anchor.x, anchor.y, d))
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
        for (key, stats) in fingerprint {
            if let id = UInt8(key) {
                distances[id] = stats.mean
            }
        }
        return estimatePosition(distances: distances, anchors: anchors)
    }

    // MARK: - Internal

    private static func weightedCentroid(_ m: [(x: Float, y: Float, d: Float)]) -> CGPoint {
        var wx: Float = 0, wy: Float = 0, wt: Float = 0
        for a in m {
            let w: Float = 1.0 / max(a.d * a.d, 0.01)
            wx += a.x * w
            wy += a.y * w
            wt += w
        }
        return CGPoint(x: CGFloat(wx / wt), y: CGFloat(wy / wt))
    }

    private static func leastSquares(_ m: [(x: Float, y: Float, d: Float)]) -> CGPoint? {
        let ref = m[0]
        var ata00: Float = 0, ata01: Float = 0, ata11: Float = 0
        var atb0: Float = 0, atb1: Float = 0

        for i in 1..<m.count {
            let a = 2 * (m[i].x - ref.x)
            let b = 2 * (m[i].y - ref.y)
            let c = ref.d * ref.d - m[i].d * m[i].d
                    + m[i].x * m[i].x - ref.x * ref.x
                    + m[i].y * m[i].y - ref.y * ref.y

            ata00 += a * a
            ata01 += a * b
            ata11 += b * b
            atb0 += a * c
            atb1 += b * c
        }

        let det = ata00 * ata11 - ata01 * ata01
        guard abs(det) > 1e-6 else { return nil }

        let x = (ata11 * atb0 - ata01 * atb1) / det
        let y = (ata00 * atb1 - ata01 * atb0) / det
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}
