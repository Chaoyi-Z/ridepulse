import SwiftUI

enum AppTab: Hashable {
    case ride, routes, devices, history, settings
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .ride

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Ride", systemImage: "bicycle")
                }
                .tag(AppTab.ride)
            RoutesView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Routes", systemImage: "map")
                }
                .tag(AppTab.routes)
            DevicesView()
                .tabItem {
                    Label("Devices", systemImage: "bluetooth")
                }
                .tag(AppTab.devices)
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.history)
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
    }
}
