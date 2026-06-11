import Foundation

struct DistanceFilter {
    var alpha: Float = 0.3
    var maxJump: Float = 3.0

    private var smoothed: Float?
    private var lastTime: Date?

    mutating func update(_ raw: Float, at time: Date) -> Float {
        guard let prev = smoothed, let lastT = lastTime else {
            smoothed = raw
            lastTime = time
            return raw
        }

        let dt = Float(time.timeIntervalSince(lastT))
        let maxDelta = maxJump * max(dt, 0.01)

        if abs(raw - prev) > maxDelta {
            lastTime = time
            return prev
        }

        let filtered = alpha * raw + (1 - alpha) * prev
        smoothed = filtered
        lastTime = time
        return filtered
    }

    mutating func reset() {
        smoothed = nil
        lastTime = nil
    }
}
