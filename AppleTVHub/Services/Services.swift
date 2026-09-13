import Foundation
import Combine

@MainActor
final class SportsViewModel: ObservableObject {
    @Published var eventsByLeague: [SportsLeague: [SportsEvent]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    func refresh() async {
        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: (SportsLeague, Result<[SportsEvent], Error>).self) { group in
            for league in SportsLeague.allCases {
                group.addTask {
                    do {
                        return (league, .success(try await SportsService.fetchScoreboard(for: league)))
                    } catch {
                        return (league, .failure(error))
                    }
                }
            }

            var failures: [String] = []
            for await (league, result) in group {
                switch result {
                case .success(let events):
                    eventsByLeague[league] = events
                case .failure(let error):
                    failures.append("\(league.rawValue): \(error.localizedDescription)")
                }
            }

            if !failures.isEmpty {
                errorMessage = failures.joined(separator: " • ")
            }
        }

        lastUpdated = Date()
        isLoading = false
    }
}

enum SportsService {
    static func fetchScoreboard(for league: SportsLeague) async throws -> [SportsEvent] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/scoreboard") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data).events
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var location = WeatherLocation.presets[0]
    @Published var weather: OpenMeteoResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    func select(_ newLocation: WeatherLocation) async {
        location = newLocation
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            weather = try await WeatherService.fetchWeather(for: location)
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

enum WeatherService {
    static func fetchWeather(for location: WeatherLocation) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(location.latitude)),
            .init(name: "longitude", value: String(location.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "wind_speed_unit", value: "mph"),
            .init(name: "precipitation_unit", value: "inch"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }
}

extension DateFormatter {
    static let weekdayShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
