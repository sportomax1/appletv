import Foundation
import Combine

@MainActor
final class SportsViewModel: ObservableObject {
    @Published private(set) var eventsByLeague: [SportsLeague: [SportsEvent]] = [:]
    @Published private(set) var loadingLeagues: Set<SportsLeague> = []
    @Published private(set) var errorByLeague: [SportsLeague: String] = [:]
    @Published private(set) var lastUpdatedByLeague: [SportsLeague: Date] = [:]
    @Published private(set) var lastAttemptByLeague: [SportsLeague: Date] = [:]
    @Published private(set) var isInitialLoading = false

    private var failureCountByLeague: [SportsLeague: Int] = [:]

    var hasAnyData: Bool { !eventsByLeague.isEmpty }

    func refreshAll() async {
        guard !isInitialLoading else { return }
        isInitialLoading = true
        defer { isInitialLoading = false }

        await withTaskGroup(of: (SportsLeague, Result<[SportsEvent], Error>).self) { group in
            for league in SportsLeague.allCases {
                guard !loadingLeagues.contains(league) else { continue }
                loadingLeagues.insert(league)
                lastAttemptByLeague[league] = Date()

                group.addTask {
                    do {
                        return (league, .success(try await SportsService.fetchScoreboard(for: league)))
                    } catch {
                        return (league, .failure(error))
                    }
                }
            }

            for await (league, result) in group {
                loadingLeagues.remove(league)
                if case .failure(let error) = result, error is CancellationError {
                    // A hidden-tab/background cancellation is not a failed API attempt.
                    lastAttemptByLeague[league] = lastUpdatedByLeague[league]
                    continue
                }
                apply(result, to: league)
            }
        }
    }

    func refresh(_ league: SportsLeague, force: Bool = false) async {
        guard !loadingLeagues.contains(league) else { return }

        if let lastAttempt = lastAttemptByLeague[league] {
            let elapsed = Date().timeIntervalSince(lastAttempt)
            // Explicit refreshes are still debounced so remote-button mashing cannot hammer the endpoint.
            if elapsed < 5 { return }
            if !force && elapsed < minimumRefreshSpacing(for: league) { return }
        }

        loadingLeagues.insert(league)
        lastAttemptByLeague[league] = Date()
        defer { loadingLeagues.remove(league) }

        do {
            let events = try await SportsService.fetchScoreboard(for: league)
            apply(.success(events), to: league)
        } catch is CancellationError {
            // Restore the last successful timestamp so returning to the tab can refresh immediately when needed.
            lastAttemptByLeague[league] = lastUpdatedByLeague[league]
            return
        } catch {
            apply(.failure(error), to: league)
        }
    }

    func recommendedRefreshInterval(for league: SportsLeague) -> TimeInterval {
        let events = eventsByLeague[league] ?? []
        let normalInterval = normalRefreshInterval(for: events)

        guard errorByLeague[league] != nil else {
            return normalInterval
        }

        let failures = max(failureCountByLeague[league] ?? 1, 1)
        let failureBackoff: TimeInterval
        switch failures {
        case 1: failureBackoff = 60
        case 2: failureBackoff = 120
        case 3: failureBackoff = 240
        default: failureBackoff = 300
        }

        // If this league has never loaded, retry on the bounded failure cadence instead of
        // falling into either a five-second loop or a fifteen-minute wait.
        if events.isEmpty {
            return failureBackoff
        }

        return max(normalInterval, failureBackoff)
    }

    func refreshDescription(for league: SportsLeague) -> String {
        let seconds = recommendedRefreshInterval(for: league)

        if errorByLeague[league] != nil {
            return "Retrying · \(intervalLabel(seconds))"
        }

        switch seconds {
        case ...20: return "Live · ~20 sec"
        case ...60: return "Starting soon · ~1 min"
        case ...120: return "Upcoming · ~2 min"
        case ...300: return "Scheduled · ~5 min"
        default: return "Idle · ~15 min"
        }
    }

    func refreshReferenceDate(for league: SportsLeague) -> Date? {
        // Every network request records lastAttempt, including successful ones, so this is the
        // correct reference for normal cadence and failure backoff.
        lastAttemptByLeague[league] ?? lastUpdatedByLeague[league]
    }

    private func normalRefreshInterval(for events: [SportsEvent]) -> TimeInterval {
        let now = Date()

        if events.contains(where: { $0.isLive }) {
            return 20
        }

        let futureStarts = events.compactMap(\.startDate).filter { $0 > now }
        if let nextStart = futureStarts.min() {
            let seconds = nextStart.timeIntervalSince(now)
            if seconds <= 15 * 60 { return 60 }
            if seconds <= 3 * 60 * 60 { return 120 }
            if seconds <= 24 * 60 * 60 { return 300 }
        }

        if events.contains(where: { !$0.isFinal }) {
            return 300
        }

        return 900
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "~\(Int(seconds)) sec"
        case ..<120: return "~1 min"
        default: return "~\(Int((seconds / 60).rounded())) min"
        }
    }

    private func minimumRefreshSpacing(for league: SportsLeague) -> TimeInterval {
        min(recommendedRefreshInterval(for: league) * 0.75, 15)
    }

    private func apply(_ result: Result<[SportsEvent], Error>, to league: SportsLeague) {
        switch result {
        case .success(let events):
            eventsByLeague[league] = events
            errorByLeague[league] = nil
            failureCountByLeague[league] = 0
            lastUpdatedByLeague[league] = Date()
        case .failure(let error):
            // Preserve the last successful scoreboard instead of blanking the screen.
            errorByLeague[league] = error.localizedDescription
            failureCountByLeague[league, default: 0] += 1
        }
    }
}

enum SportsService {
    static func fetchScoreboard(for league: SportsLeague) async throws -> [SportsEvent] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/scoreboard") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let data = try await fetchWithOneRetry(request)
        try Task.checkCancellation()
        return try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data).events
    }

    private static func fetchWithOneRetry(_ request: URLRequest) async throws -> Data {
        var finalError: Error = URLError(.unknown)

        for attempt in 0..<2 {
            try Task.checkCancellation()

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if 200..<300 ~= http.statusCode {
                    return data
                }

                if http.statusCode == 429 || http.statusCode >= 500 {
                    throw URLError(.cannotLoadFromNetwork)
                }

                throw URLError(.badServerResponse)
            } catch {
                if isCancellation(error) {
                    throw CancellationError()
                }

                finalError = error
                if attempt == 0 {
                    try await Task.sleep(nanoseconds: 700_000_000)
                }
            }
        }

        throw finalError
    }

    private static func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published private(set) var location: WeatherLocation
    @Published private(set) var weather: OpenMeteoResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastAttempt: Date?

    init() {
        location = WeatherLocation.savedOrDefault()
    }

    func select(_ newLocation: WeatherLocation) async {
        guard newLocation != location else { return }
        location = newLocation
        UserDefaults.standard.set(newLocation.id, forKey: "weather.locationID")
        await refresh(force: true)
    }

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }

        if let lastAttempt {
            let elapsed = Date().timeIntervalSince(lastAttempt)
            if elapsed < 10 { return }
        }

        if !force,
           let lastUpdated,
           Date().timeIntervalSince(lastUpdated) < 10 * 60 {
            return
        }

        isLoading = true
        lastAttempt = Date()
        defer { isLoading = false }
        errorMessage = nil

        do {
            weather = try await WeatherService.fetchWeather(for: location)
            lastUpdated = Date()
        } catch is CancellationError {
            // Canceled hidden-tab work should not delay the next visible refresh.
            lastAttempt = lastUpdated
            return
        } catch {
            // Keep the previous successful forecast visible if a refresh fails.
            errorMessage = error.localizedDescription
        }
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
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        var finalError: Error = URLError(.unknown)
        for attempt in 0..<2 {
            try Task.checkCancellation()

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                try Task.checkCancellation()
                return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            } catch {
                if isCancellation(error) {
                    throw CancellationError()
                }

                finalError = error
                if attempt == 0 {
                    try await Task.sleep(nanoseconds: 700_000_000)
                }
            }
        }

        throw finalError
    }

    private static func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

extension DateFormatter {
    static let weekdayShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
