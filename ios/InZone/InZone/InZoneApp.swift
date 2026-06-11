import SwiftUI

@main
struct InZoneApp: App {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var scheduler = RangingScheduler()
    @StateObject private var zoneEngine = ZoneEngine()
    @StateObject private var zoneStore = ZoneStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(scheduler)
                .environmentObject(zoneEngine)
                .environmentObject(zoneStore)
        }
    }
}
