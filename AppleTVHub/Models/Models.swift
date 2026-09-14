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

    var favoriteTeamName: String {
        switch self {
        case .nfl: return "Denver Broncos"
        case .nba: return "Denver Nuggets"
        case .nhl: return "Colorado Avalanche"
        case .mlb: return "Colorado Rockies"
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
    let season: SportsSeason?
    let week: SportsWeek?

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

struct SportsSeason: Decodable {
    let year: Int?
    let type: Int?
    let slug: String?
}

struct SportsWeek: Decodable {
    let number: Int?
}

struct Competition: Decodable {
    let id: String?
    let competitors: [Competitor]
    let venue: SportsVenue?
    let broadcasts: [SportsBroadcast]?
    let attendance: Int?
    let neutralSite: Bool?
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
    let linescores: [SportsLineScore]?

    var record: String? { records?.first?.summary }
}

struct SportsLineScore: Decodable, Identifiable {
    let value: Double?
    let displayValue: String?
    let period: Int?

    var id: String { "\(period ?? 0)-\(displayValue ?? "")" }
}

struct SportsTeam: Decodable {
    let id: String
    let displayName: String
    let abbreviation: String
    let logo: String?
    let location: String?
    let name: String?
    let shortDisplayName: String?
    let color: String?
    let alternateColor: String?
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

struct SportsKeyValue: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

struct LeagueTeam: Identifiable, Hashable {
    let id: String
    let displayName: String
    let abbreviation: String
    let logo: String?
    let location: String?
    let color: String?
    let alternateColor: String?
}

struct StandingGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let rows: [StandingRow]
}

struct StandingRow: Identifiable, Hashable {
    let id: String
    let teamID: String
    let teamName: String
    let abbreviation: String
    let logo: String?
    let record: String
    let rank: String?
    let streak: String?
    let gamesBehind: String?
    let extra: [SportsKeyValue]
}

struct GameDetailData {
    let teamStats: [GameTeamStats]
    let playerGroups: [GamePlayerGroup]
    let scoringPlays: [GameScoringPlay]
    let facts: [SportsKeyValue]
}

struct GameTeamStats: Identifiable {
    let id: String
    let teamID: String
    let teamName: String
    let abbreviation: String
    let logo: String?
    let stats: [SportsKeyValue]
}

struct GamePlayerGroup: Identifiable {
    let id: String
    let teamID: String
    let teamName: String
    let category: String
    let labels: [String]
    let players: [GamePlayerStat]
}

struct GamePlayerStat: Identifiable {
    let id: String
    let athlete: SportsAthlete
    let stats: [String]
}

struct GameScoringPlay: Identifiable {
    let id: String
    let text: String
    let clock: String?
    let period: Int?
    let awayScore: String?
    let homeScore: String?
    let teamLogo: String?
}

struct SportsAthlete: Identifiable, Hashable {
    let id: String
    let displayName: String
    let shortName: String?
    let jersey: String?
    let position: String?
    let headshot: String?
    let age: Int?
    let height: String?
    let weight: String?
    let experience: String?
    let status: String?
}

struct TeamProfileData {
    let team: LeagueTeam
    let nickname: String?
    let standingSummary: String?
    let record: String?
    let venue: String?
    let coach: String?
    let facts: [SportsKeyValue]
    let roster: [RosterGroup]
}

struct RosterGroup: Identifiable {
    let id: String
    let name: String
    let athletes: [SportsAthlete]
}

struct PlayerProfileData {
    let athlete: SportsAthlete
    let teamName: String?
    let debutYear: Int?
    let birthplace: String?
    let summaryStats: [SportsKeyValue]
    let gameLog: [PlayerGameLogRow]
}

struct PlayerGameLogRow: Identifiable {
    let id: String
    let date: String
    let opponent: String
    let result: String?
    let stats: [SportsKeyValue]
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
