import SwiftUI

struct ContentView: View {
    private enum RootTab: String, Hashable {
        case sports
        case weather
        case arcade
    }

    @AppStorage("app.selectedTab") private var selectedTabRaw = RootTab.sports.rawValue

    private var selectedTab: Binding<RootTab> {
        Binding(
            get: { RootTab(rawValue: selectedTabRaw) ?? .sports },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            SportsView(isActive: selectedTab.wrappedValue == .sports)
                .tabItem {
                    Label("Sports", systemImage: "sportscourt.fill")
                }
                .tag(RootTab.sports)

            WeatherView(isActive: selectedTab.wrappedValue == .weather)
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun.fill")
                }
                .tag(RootTab.weather)

            ArcadeView()
                .tabItem {
                    Label("Arcade", systemImage: "gamecontroller.fill")
                }
                .tag(RootTab.arcade)
        }
        .tint(.white)
    }
}
