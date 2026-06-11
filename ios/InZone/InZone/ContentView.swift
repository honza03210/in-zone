import SwiftUI

struct ContentView: View {
    @EnvironmentObject var simulator: SimulatorService
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var scheduler: RangingScheduler

    var body: some View {
        TabView {
            AnchorsView()
                .tabItem {
                    Label("Anchors", systemImage: "antenna.radiowaves.left.and.right")
                }

            LiveView()
                .tabItem {
                    Label("Live", systemImage: "location.fill")
                }

            MapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            ZoneListView()
                .tabItem {
                    Label("Zones", systemImage: "square.grid.2x2")
                }
        }
        .onAppear {
            if SimulatorService.isSimulatorEnvironment && !simulator.isActive {
                simulator.activate(bleManager: bleManager, scheduler: scheduler)
            }
        }
    }
}
