import Foundation
import SwiftUI

struct DistanceStats: Codable {
    var mean: Float
    var variance: Float
    var sampleCount: Int
}

struct Zone: Identifiable, Codable {
    let id: UUID
    var name: String
    var fingerprint: [String: DistanceStats]
    var capturedAt: Date
    var colorName: String

    static let availableColors = [
        "blue", "purple", "green", "orange", "red", "pink", "yellow", "teal"
    ]

    func stats(for anchorId: UInt8) -> DistanceStats? {
        fingerprint[String(anchorId)]
    }

    static func color(for name: String) -> Color {
        switch name {
        case "blue":    return .blue
        case "purple":  return .purple
        case "green":   return .green
        case "orange":  return .orange
        case "red":     return .red
        case "pink":    return .pink
        case "yellow":  return .yellow
        case "teal":    return .teal
        default:        return .gray
        }
    }
}
