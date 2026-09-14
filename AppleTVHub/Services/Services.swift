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
            lastAttemptByLeague[league] = lastUpdatedByLeague[league]
            return
        } catch {
            apply(.failure(error), to: league)
        }
    }

    func recommendedRefreshInterval(for league: SportsLeague) -> TimeInterval {
        let events = eventsByLeague[league] ?? []
        let normalInterval = normalRefreshInterval(for: events)

        guard errorByLeague[league] != nil else { return normalInterval }

        let failures = max(failureCountByLeague[league] ?? 1, 1)
        let failureBackoff: TimeInterval
        switch failures {
        case 1: failureBackoff = 60
        case 2: failureBackoff = 120
        case 3: failureBackoff = 240
        default: failureBackoff = 300
        }

        if events.isEmpty { return failureBackoff }
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
        lastAttemptByLeague[league] ?? lastUpdatedByLeague[league]
    }

    private func normalRefreshInterval(for events: [SportsEvent]) -> TimeInterval {
        let now = Date()
        if events.contains(where: { $0.isLive }) { return 20 }

        let futureStarts = events.compactMap(\.startDate).filter { $0 > now }
        if let nextStart = futureStarts.min() {
            let seconds = nextStart.timeIntervalSince(now)
            if seconds <= 15 * 60 { return 60 }
            if seconds <= 3 * 60 * 60 { return 120 }
            if seconds <= 24 * 60 * 60 { return 300 }
        }

        if events.contains(where: { !$0.isFinal }) { return 300 }
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
            errorByLeague[league] = error.localizedDescription
            failureCountByLeague[league, default: 0] += 1
        }
    }
}

enum SportsService {
    private typealias JSON = [String: Any]

    // MARK: Scoreboards / schedules

    static func fetchScoreboard(for league: SportsLeague, date: Date? = nil) async throws -> [SportsEvent] {
        var components = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/scoreboard")!
        var query = [URLQueryItem(name: "limit", value: "100")]
        if let date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyyMMdd"
            query.append(URLQueryItem(name: "dates", value: formatter.string(from: date)))
        }
        components.queryItems = query
        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await fetchData(url)
        return try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data).events
    }

    static func fetchTeamSchedule(for league: SportsLeague, teamID: String) async throws -> [SportsEvent] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/teams/\(teamID)/schedule") else {
            throw URLError(.badURL)
        }
        let data = try await fetchData(url)
        return try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data).events
    }

    // MARK: League teams / standings

    static func fetchTeams(for league: SportsLeague) async throws -> [LeagueTeam] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/teams") else {
            throw URLError(.badURL)
        }
        let root = try await fetchJSON(url)
        let sports = root["sports"] as? [JSON] ?? []
        let leagues = sports.first?["leagues"] as? [JSON] ?? []
        let wrappedTeams = leagues.first?["teams"] as? [JSON] ?? (root["teams"] as? [JSON] ?? [])

        return wrappedTeams.compactMap { wrapper in
            parseLeagueTeam((wrapper["team"] as? JSON) ?? wrapper)
        }
        .sorted { $0.displayName < $1.displayName }
    }

    static func fetchStandings(for league: SportsLeague) async throws -> [StandingGroup] {
        guard let url = URL(string: "https://site.api.espn.com/apis/v2/sports/\(league.endpointPath)/standings") else {
            throw URLError(.badURL)
        }
        let root = try await fetchJSON(url)
        var groups: [StandingGroup] = []
        collectStandingGroups(root, groups: &groups)

        if groups.isEmpty, let children = root["children"] as? [JSON] {
            for child in children { collectStandingGroups(child, groups: &groups) }
        }

        return groups
    }

    // MARK: Game detail / box score

    static func fetchGameDetail(for league: SportsLeague, eventID: String) async throws -> GameDetailData {
        var components = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/summary")!
        components.queryItems = [URLQueryItem(name: "event", value: eventID)]
        guard let url = components.url else { throw URLError(.badURL) }
        let root = try await fetchJSON(url)

        var teamStats: [GameTeamStats] = []
        var playerGroups: [GamePlayerGroup] = []

        if let boxscore = root["boxscore"] as? JSON {
            let teams = boxscore["teams"] as? [JSON] ?? []
            teamStats = teams.compactMap { item in
                guard let team = item["team"] as? JSON,
                      let teamID = string(team["id"]),
                      let name = string(team["displayName"]) else { return nil }

                let stats = (item["statistics"] as? [JSON] ?? []).compactMap { stat -> SportsKeyValue? in
                    guard let value = string(stat["displayValue"]) ?? string(stat["value"]), !value.isEmpty else { return nil }
                    let label = string(stat["label"]) ?? string(stat["displayName"]) ?? string(stat["name"]) ?? "Stat"
                    return SportsKeyValue(label: label, value: value)
                }

                return GameTeamStats(
                    id: teamID,
                    teamID: teamID,
                    teamName: name,
                    abbreviation: string(team["abbreviation"]) ?? "",
                    logo: logoURL(team),
                    stats: stats
                )
            }

            let players = boxscore["players"] as? [JSON] ?? []
            for teamBlock in players {
                let team = teamBlock["team"] as? JSON ?? [:]
                let teamID = string(team["id"]) ?? UUID().uuidString
                let teamName = string(team["displayName"]) ?? string(team["name"]) ?? "Team"
                let categories = teamBlock["statistics"] as? [JSON] ?? []

                for category in categories {
                    let categoryName = string(category["displayName"]) ?? string(category["name"]) ?? "Players"
                    let labels = (category["labels"] as? [Any] ?? []).compactMap(string)
                    let athletes = category["athletes"] as? [JSON] ?? []
                    let rows = athletes.compactMap { row -> GamePlayerStat? in
                        guard let athleteJSON = row["athlete"] as? JSON,
                              let athlete = parseAthlete(athleteJSON) else { return nil }
                        let stats = (row["stats"] as? [Any] ?? []).compactMap(string)
                        return GamePlayerStat(id: "\(teamID)-\(categoryName)-\(athlete.id)", athlete: athlete, stats: stats)
                    }

                    if !rows.isEmpty {
                        playerGroups.append(
                            GamePlayerGroup(
                                id: "\(teamID)-\(categoryName)",
                                teamID: teamID,
                                teamName: teamName,
                                category: categoryName,
                                labels: labels,
                                players: rows
                            )
                        )
                    }
                }
            }
        }

        let scoringPlays = (root["scoringPlays"] as? [JSON] ?? []).compactMap { play -> GameScoringPlay? in
            guard let text = string(play["text"]), !text.isEmpty else { return nil }
            let clock = (play["clock"] as? JSON).flatMap { string($0["displayValue"]) }
            let team = play["team"] as? JSON
            return GameScoringPlay(
                id: string(play["id"]) ?? UUID().uuidString,
                text: text,
                clock: clock,
                period: int(play["period"]),
                awayScore: string(play["awayScore"]),
                homeScore: string(play["homeScore"]),
                teamLogo: team.flatMap(logoURL)
            )
        }

        var facts: [SportsKeyValue] = []
        if let header = root["header"] as? JSON,
           let competition = (header["competitions"] as? [JSON])?.first {
            if let attendance = int(competition["attendance"]), attendance > 0 {
                facts.append(.init(label: "Attendance", value: NumberFormatter.localizedString(from: NSNumber(value: attendance), number: .decimal)))
            }
            if let venue = competition["venue"] as? JSON, let name = string(venue["fullName"]) {
                facts.append(.init(label: "Venue", value: name))
            }
            if let broadcasts = competition["broadcasts"] as? [JSON] {
                let names = broadcasts.flatMap { ($0["names"] as? [Any] ?? []).compactMap(string) }
                if !names.isEmpty { facts.append(.init(label: "TV", value: names.joined(separator: ", "))) }
            }
        }

        return GameDetailData(teamStats: teamStats, playerGroups: playerGroups, scoringPlays: scoringPlays, facts: facts)
    }

    // MARK: Team profile

    static func fetchTeamProfile(for league: SportsLeague, teamID: String) async throws -> TeamProfileData {
        guard let detailURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/teams/\(teamID)?enable=roster,stats") else {
            throw URLError(.badURL)
        }
        let root = try await fetchJSON(detailURL)
        guard let teamJSON = root["team"] as? JSON,
              let team = parseLeagueTeam(teamJSON) else { throw URLError(.cannotParseResponse) }

        let rosterRoot: JSON?
        if let rosterURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/teams/\(teamID)/roster") {
            rosterRoot = try? await fetchJSON(rosterURL)
        } else {
            rosterRoot = nil
        }

        let roster = parseRoster(rosterRoot ?? root)
        let standingSummary = string(teamJSON["standingSummary"])
        let record = parseTeamRecord(teamJSON)
        let venue = (teamJSON["venue"] as? JSON).flatMap { string($0["fullName"]) }
        let coach = parseCoach(root)

        var facts: [SportsKeyValue] = []
        if let location = string(teamJSON["location"]) { facts.append(.init(label: "Location", value: location)) }
        if let standingSummary { facts.append(.init(label: "Standing", value: standingSummary)) }
        if let record { facts.append(.init(label: "Record", value: record)) }
        if let venue { facts.append(.init(label: "Venue", value: venue)) }
        if let coach { facts.append(.init(label: "Coach", value: coach)) }

        return TeamProfileData(
            team: team,
            nickname: string(teamJSON["nickname"]) ?? string(teamJSON["name"]),
            standingSummary: standingSummary,
            record: record,
            venue: venue,
            coach: coach,
            facts: facts,
            roster: roster
        )
    }

    // MARK: Player profile / game log

    static func fetchPlayerProfile(for league: SportsLeague, athleteID: String) async throws -> PlayerProfileData {
        guard let profileURL = URL(string: "https://site.web.api.espn.com/apis/common/v3/sports/\(league.endpointPath)/athletes/\(athleteID)") else {
            throw URLError(.badURL)
        }
        let root = try await fetchJSON(profileURL)
        let athleteJSON = (root["athlete"] as? JSON) ?? root
        guard let athlete = parseAthlete(athleteJSON) else { throw URLError(.cannotParseResponse) }

        var summaryStats: [SportsKeyValue] = []
        if let overviewURL = URL(string: "https://site.web.api.espn.com/apis/common/v3/sports/\(league.endpointPath)/athletes/\(athleteID)/overview"),
           let overview = try? await fetchJSON(overviewURL) {
            collectDisplayStats(overview, output: &summaryStats, limit: 16)
        }

        var gameLog: [PlayerGameLogRow] = []
        if let gameLogURL = URL(string: "https://site.web.api.espn.com/apis/common/v3/sports/\(league.endpointPath)/athletes/\(athleteID)/gamelog"),
           let logRoot = try? await fetchJSON(gameLogURL) {
            var seen = Set<String>()
            collectGameLogRows(logRoot, labels: [], rows: &gameLog, seen: &seen)
        }

        let teamName = (athleteJSON["team"] as? JSON).flatMap { string($0["displayName"]) ?? string($0["name"]) }
        let birthplace = parseBirthplace(athleteJSON["birthPlace"] as? JSON)

        return PlayerProfileData(
            athlete: athlete,
            teamName: teamName,
            debutYear: int(athleteJSON["debutYear"]),
            birthplace: birthplace,
            summaryStats: Array(summaryStats.prefix(16)),
            gameLog: Array(gameLog.prefix(20))
        )
    }

    // MARK: Network

    private static func fetchJSON(_ url: URL) async throws -> JSON {
        let data = try await fetchData(url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? JSON else { throw URLError(.cannotParseResponse) }
        return root
    }

    private static func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let data = try await fetchWithOneRetry(request)
        try Task.checkCancellation()
        return data
    }

    private static func fetchWithOneRetry(_ request: URLRequest) async throws -> Data {
        var finalError: Error = URLError(.unknown)

        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if 200..<300 ~= http.statusCode { return data }
                if http.statusCode == 429 || http.statusCode >= 500 { throw URLError(.cannotLoadFromNetwork) }
                throw URLError(.badServerResponse)
            } catch {
                if isCancellation(error) { throw CancellationError() }
                finalError = error
                if attempt == 0 { try await Task.sleep(nanoseconds: 700_000_000) }
            }
        }

        throw finalError
    }

    private static func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    // MARK: JSON parsing helpers

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func logoURL(_ team: JSON) -> String? {
        if let logo = string(team["logo"]) { return logo }
        if let logos = team["logos"] as? [JSON] {
            return logos.compactMap { string($0["href"]) }.first
        }
        return nil
    }

    private static func parseLeagueTeam(_ team: JSON) -> LeagueTeam? {
        guard let id = string(team["id"]),
              let displayName = string(team["displayName"]) ?? string(team["name"]) else { return nil }
        return LeagueTeam(
            id: id,
            displayName: displayName,
            abbreviation: string(team["abbreviation"]) ?? "",
            logo: logoURL(team),
            location: string(team["location"]),
            color: string(team["color"]),
            alternateColor: string(team["alternateColor"])
        )
    }

    private static func collectStandingGroups(_ node: JSON, groups: inout [StandingGroup]) {
        if let standings = node["standings"] as? JSON,
           let entries = standings["entries"] as? [JSON], !entries.isEmpty {
            let name = string(node["name"]) ?? string(node["displayName"]) ?? string(standings["name"]) ?? "Standings"
            let rows = entries.compactMap(parseStandingRow)
            if !rows.isEmpty {
                groups.append(.init(id: string(node["id"]) ?? UUID().uuidString, name: name, rows: rows))
            }
        }

        if let children = node["children"] as? [JSON] {
            for child in children { collectStandingGroups(child, groups: &groups) }
        }
    }

    private static func parseStandingRow(_ entry: JSON) -> StandingRow? {
        guard let team = entry["team"] as? JSON,
              let teamID = string(team["id"]),
              let teamName = string(team["displayName"]) ?? string(team["name"]) else { return nil }

        let stats = entry["stats"] as? [JSON] ?? []
        func stat(_ names: [String]) -> String? {
            for candidate in stats {
                let keys = [string(candidate["name"]), string(candidate["type"]), string(candidate["abbreviation"]), string(candidate["shortDisplayName"])].compactMap { $0?.lowercased() }
                if keys.contains(where: { key in names.contains(where: { key == $0.lowercased() }) }) {
                    return string(candidate["displayValue"]) ?? string(candidate["value"])
                }
            }
            return nil
        }

        let wins = stat(["wins", "w"]) ?? "0"
        let losses = stat(["losses", "l"]) ?? "0"
        let ties = stat(["ties", "t"])
        let record = stat(["overall", "total"]) ?? (ties == nil || ties == "0" ? "\(wins)-\(losses)" : "\(wins)-\(losses)-\(ties!)")

        let preferred = ["winPercent", "gamesBehind", "streak", "pointDifferential", "points", "gamesPlayed"]
        var extra: [SportsKeyValue] = []
        for key in preferred {
            guard let item = stats.first(where: { (string($0["name"]) ?? "").caseInsensitiveCompare(key) == .orderedSame }),
                  let value = string(item["displayValue"]) ?? string(item["value"]) else { continue }
            let label = string(item["shortDisplayName"]) ?? string(item["abbreviation"]) ?? string(item["displayName"]) ?? key
            extra.append(.init(label: label, value: value))
        }

        return StandingRow(
            id: teamID,
            teamID: teamID,
            teamName: teamName,
            abbreviation: string(team["abbreviation"]) ?? "",
            logo: logoURL(team),
            record: record,
            rank: stat(["playoffSeed", "seed", "rank"]),
            streak: stat(["streak"]),
            gamesBehind: stat(["gamesBehind", "gb"]),
            extra: extra
        )
    }

    private static func parseTeamRecord(_ team: JSON) -> String? {
        if let record = team["record"] as? JSON {
            if let items = record["items"] as? [JSON] {
                return items.compactMap { string($0["summary"]) }.first
            }
            if let summary = string(record["summary"]) { return summary }
        }
        return nil
    }

    private static func parseCoach(_ root: JSON) -> String? {
        if let coaches = root["coach"] as? [JSON], let coach = coaches.first {
            if let full = string(coach["displayName"]) ?? string(coach["fullName"]) { return full }
            let parts = [string(coach["firstName"]), string(coach["lastName"])].compactMap { $0 }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        if let coach = root["coach"] as? JSON {
            return string(coach["displayName"]) ?? string(coach["fullName"])
        }
        return nil
    }

    private static func parseRoster(_ root: JSON) -> [RosterGroup] {
        let athleteBlocks = root["athletes"] as? [JSON] ?? ((root["team"] as? JSON)?["athletes"] as? [JSON] ?? [])
        var grouped: [RosterGroup] = []
        var loose: [SportsAthlete] = []

        for block in athleteBlocks {
            if let items = block["items"] as? [JSON] {
                let position = block["position"] as? JSON
                let name = position.flatMap { string($0["displayName"]) ?? string($0["name"]) } ?? string(block["name"]) ?? "Roster"
                let athletes = items.compactMap(parseAthlete)
                if !athletes.isEmpty { grouped.append(.init(id: name, name: name, athletes: athletes)) }
            } else if let athlete = parseAthlete(block) {
                loose.append(athlete)
            }
        }

        if !loose.isEmpty { grouped.insert(.init(id: "roster", name: "Roster", athletes: loose), at: 0) }
        return grouped
    }

    private static func parseAthlete(_ json: JSON) -> SportsAthlete? {
        guard let id = string(json["id"]),
              let name = string(json["displayName"]) ?? string(json["fullName"]) else { return nil }

        let positionJSON = json["position"] as? JSON
        let position = positionJSON.flatMap { string($0["abbreviation"]) ?? string($0["displayName"]) ?? string($0["name"]) }
        let headshot: String?
        if let direct = string(json["headshot"]) {
            headshot = direct
        } else if let object = json["headshot"] as? JSON {
            headshot = string(object["href"])
        } else {
            headshot = nil
        }
        let experience = (json["experience"] as? JSON).flatMap { exp -> String? in
            if let display = string(exp["displayValue"]) { return display }
            if let years = int(exp["years"]) { return years == 1 ? "1 year" : "\(years) years" }
            return nil
        }
        let status = (json["status"] as? JSON).flatMap { string($0["name"]) ?? string($0["type"]) }
        let height = string(json["displayHeight"]) ?? string(json["height"])
        let weight = string(json["displayWeight"]) ?? string(json["weight"])

        return SportsAthlete(
            id: id,
            displayName: name,
            shortName: string(json["shortName"]),
            jersey: string(json["jersey"]),
            position: position,
            headshot: headshot,
            age: int(json["age"]),
            height: height,
            weight: weight,
            experience: experience,
            status: status
        )
    }

    private static func parseBirthplace(_ json: JSON?) -> String? {
        guard let json else { return nil }
        let parts = [string(json["city"]), string(json["state"]), string(json["country"])].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func collectDisplayStats(_ value: Any, output: inout [SportsKeyValue], limit: Int) {
        guard output.count < limit else { return }
        if let object = value as? JSON {
            if let displayValue = string(object["displayValue"]) ?? string(object["value"]),
               let label = string(object["displayName"]) ?? string(object["label"]) ?? string(object["abbreviation"]),
               !displayValue.isEmpty, !label.isEmpty,
               !output.contains(where: { $0.label == label && $0.value == displayValue }) {
                output.append(.init(label: label, value: displayValue))
                if output.count >= limit { return }
            }
            for child in object.values {
                collectDisplayStats(child, output: &output, limit: limit)
                if output.count >= limit { return }
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectDisplayStats(child, output: &output, limit: limit)
                if output.count >= limit { return }
            }
        }
    }

    private static func collectGameLogRows(_ value: Any, labels: [String], rows: inout [PlayerGameLogRow], seen: inout Set<String>) {
        if let object = value as? JSON {
            let localLabels = (object["labels"] as? [Any] ?? object["names"] as? [Any] ?? []).compactMap(string)
            let activeLabels = localLabels.isEmpty ? labels : localLabels

            if let statsAny = object["stats"] as? [Any], !statsAny.isEmpty {
                let opponentObject = object["opponent"] as? JSON
                let opponent = opponentObject.flatMap { string($0["displayName"]) ?? string($0["name"]) ?? string($0["abbreviation"]) }
                    ?? string(object["opponentName"])
                    ?? string(object["opponent"])

                if let opponent, !opponent.isEmpty {
                    let id = string(object["eventId"]) ?? string(object["id"]) ?? UUID().uuidString
                    if !seen.contains(id) {
                        seen.insert(id)
                        let values = statsAny.compactMap(string)
                        let pairs = values.enumerated().map { index, value in
                            SportsKeyValue(label: activeLabels.indices.contains(index) ? activeLabels[index] : "Stat \(index + 1)", value: value)
                        }
                        rows.append(
                            .init(
                                id: id,
                                date: string(object["gameDate"]) ?? string(object["date"]) ?? "",
                                opponent: opponent,
                                result: string(object["gameResult"]) ?? string(object["result"]),
                                stats: pairs
                            )
                        )
                    }
                }
            }

            for child in object.values {
                collectGameLogRows(child, labels: activeLabels, rows: &rows, seen: &seen)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectGameLogRows(child, labels: labels, rows: &rows, seen: &seen)
            }
        }
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
            lastAttempt = lastUpdated
            return
        } catch {
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
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_gusts_10m,precipitation,cloud_cover"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,wind_speed_10m"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,uv_index_max,sunrise,sunset"),
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
                if isCancellation(error) { throw CancellationError() }
                finalError = error
                if attempt == 0 { try await Task.sleep(nanoseconds: 700_000_000) }
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
