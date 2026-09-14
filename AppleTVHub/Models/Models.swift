import Foundation

// MARK: - Sports

enum SportsLeague: String, CaseIterable, Identifiable, Hashable {
    case nfl = "NFL"
    case nba = "NBA"
    case nhl = "NHL"
    case mlb = "MLB"

    var id: String { rawValue }

    var endpointPath: String {
        switch self {
        case .nfl: return "football/nfl"
        case .nba: return "basketball/nba"
        case .nhl: return "hockey/nhl"
        case .mlb: return "baseball/mlb"
        }
    }

    var symbol: String {
        switch self {
        case .nfl: return "football.fill"
        case .nba: return "basketball.fill"
        case .nhl: return "hockey.puck.fill"
        case .mlb: return "baseball.fill"
        }
    }

    var favoriteTeamAbbreviations: Set<String> {
        switch self {
        case .nfl, .nba: return ["DEN"]
        case .nhl, .mlb: return ["COL"]
        }
    }
}

struct ESPNScoreboardResponse: Decodable {
    let events: [SportsEvent]
}

struct SportsEvent: Decodable, Identifiable {
    let id: String
    let name: String
    let shortName: String?
    let date: String
    let status: EventStatus
    let competitions: [Competition]

    var competition: Competition? { competitions.first }
    var homeTeam: Competitor? { competition?.competitors.first(where: { $0.homeAway == "home" }) }
    var awayTeam: Competitor? { competition?.competitors.first(where: { $0.homeAway == "away" }) }
    var isLive: Bool { status.type.state == "in" }
    var isFinal: Bool { status.type.state == "post" }
    var isUpcoming: Bool { !isLive && !isFinal }

    var startDate: Date? {
        SportsDateParser.date(from: date)
    }

    var network: String? {
        competition?.broadcasts?
            .flatMap { $0.names ?? [] }
            .first
    }

    var venueText: String? {
        guard let venue = competition?.venue else { return nil }
        let location = [venue.address?.city, venue.address?.state]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if location.isEmpty { return venue.fullName }
        return "\(venue.fullName) · \(location)"
    }
}

struct Competition: Decodable {
    let competitors: [Competitor]
    let venue: SportsVenue?
    let broadcasts: [SportsBroadcast]?
}

struct SportsVenue: Decodable {
    let fullName: String
    let address: SportsAddress?
}

struct SportsAddress: Decodable {
    let city: String?
    let state: String?
}

struct SportsBroadcast: Decodable {
    let names: [String]?
}

struct Competitor: Decodable, Identifiable {
    let id: String
    let homeAway: String
    let score: String?
    let winner: Bool?
    let team: SportsTeam
    let records: [TeamRecord]?

    var record: String? { records?.first?.summary }
}

struct SportsTeam: Decodable {
    let id: String
    let displayName: String
    let abbreviation: String
    let logo: String?
}

struct TeamRecord: Decodable {
    let summary: String?
}

struct EventStatus: Decodable {
    let type: EventStatusType
}

struct EventStatusType: Decodable {
    let state: String?
    let description: String?
    let shortDetail: String?
}

private enum SportsDateParser {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        fractional.date(from: value) ?? standard.date(from: value)
    }
}

// MARK: - Weather

struct WeatherLocation: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    static let presets: [WeatherLocation] = [
        .init(id: "parker", name: "Parker", subtitle: "Colorado", latitude: 39.5186, longitude: -104.7614),
        .init(id: "denver", name: "Denver", subtitle: "Colorado", latitude: 39.7392, longitude: -104.9903),
        .init(id: "colorado-springs", name: "Colorado Springs", subtitle: "Colorado", latitude: 38.8339, longitude: -104.8214),
        .init(id: "fort-collins", name: "Fort Collins", subtitle: "Colorado", latitude: 40.5853, longitude: -105.0844),
        .init(id: "boulder", name: "Boulder", subtitle: "Colorado", latitude: 40.0150, longitude: -105.2705),
        .init(id: "park-city", name: "Park City", subtitle: "Utah", latitude: 40.6461, longitude: -111.4980)
    ]

    static func savedOrDefault() -> WeatherLocation {
        let savedID = UserDefaults.standard.string(forKey: "weather.locationID")
        return presets.first(where: { $0.id == savedID }) ?? presets[0]
    }
}

struct OpenMeteoResponse: Decodable {
    let timezone: String
    let current: WeatherCurrent
    let hourly: WeatherHourly
    let daily: WeatherDaily
}

struct WeatherCurrent: Decodable {
    let temperature2m: Double
    let apparentTemperature: Double
    let relativeHumidity2m: Int
    let weatherCode: Int
    let windSpeed10m: Double
    let windGusts10m: Double?
    let precipitation: Double?
    let cloudCover: Int?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity2m = "relative_humidity_2m"
        case weatherCode = "weather_code"
        case windSpeed10m = "wind_speed_10m"
        case windGusts10m = "wind_gusts_10m"
        case precipitation
        case cloudCover = "cloud_cover"
    }
}

struct WeatherHourly: Decodable {
    let time: [String]
    let temperature2m: [Double]
    let precipitationProbability: [Int]
    let weatherCode: [Int]
    let windSpeed10m: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case windSpeed10m = "wind_speed_10m"
    }
}

struct WeatherDaily: Decodable {
    let time: [String]
    let weatherCode: [Int]
    let temperature2mMax: [Double]
    let temperature2mMin: [Double]
    let precipitationProbabilityMax: [Int]
    let precipitationSum: [Double]?
    let windSpeed10mMax: [Double]?
    let uvIndexMax: [Double]?
    let sunrise: [String]?
    let sunset: [String]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case precipitationSum = "precipitation_sum"
        case windSpeed10mMax = "wind_speed_10m_max"
        case uvIndexMax = "uv_index_max"
        case sunrise
        case sunset
    }
}

enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95, 96, 99: return "Thunderstorms"
        default: return "Conditions"
        }
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 61, 63, 65, 80, 81, 82: return "cloud.rain.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
