import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SportsView()
                .tabItem {
                    Label("Sports", systemImage: "sportscourt.fill")
                }

            WeatherView()
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun.fill")
                }

            ArcadeView()
                .tabItem {
                    Label("Arcade", systemImage: "gamecontroller.fill")
                }
        }
        .tint(.white)
    }
}
