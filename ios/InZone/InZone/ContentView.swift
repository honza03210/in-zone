import SwiftUI

struct ContentView: View {
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

            ZoneListView()
                .tabItem {
                    Label("Zones", systemImage: "square.grid.2x2")
                }
        }
    }
}
