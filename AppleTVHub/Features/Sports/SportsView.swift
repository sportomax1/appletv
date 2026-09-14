import SwiftUI

struct SportsView: View {
    let isActive: Bool

    private enum SportsSection: String, CaseIterable, Identifiable {
        case scores = "Scores"
        case schedule = "Schedule"
        case standings = "Standings"
        case teams = "Teams"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .scores: return "sportscourt.fill"
            case .schedule: return "calendar"
            case .standings: return "list.number"
            case .teams: return "person.3.fill"
            }
        }
    }

    private enum SportsFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case live = "Live"
        case upcoming = "Upcoming"
        case final = "Final"
        case favorites = "Colorado"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all: return "rectangle.grid.2x2.fill"
            case .live: return "dot.radiowaves.left.and.right"
            case .upcoming: return "clock.fill"
            case .final: return "checkmark.circle.fill"
            case .favorites: return "star.fill"
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = SportsViewModel()
    @AppStorage("sports.selectedLeague") private var selectedLeagueRaw = SportsLeague.nfl.rawValue
    @AppStorage("sports.filter") private var selectedFilterRaw = SportsFilter.all.rawValue
    @AppStorage("sports.section") private var selectedSectionRaw = SportsSection.scores.rawValue

    @State private var scheduleDate = Date()
    @State private var scheduleEvents: [SportsEvent] = []
    @State private var scheduleLoading = false
    @State private var scheduleError: String?

    @State private var standings: [StandingGroup] = []
    @State private var standingsLeague: SportsLeague?
    @State private var standingsLoading = false
    @State private var standingsError: String?

    @State private var teams: [LeagueTeam] = []
    @State private var teamsLeague: SportsLeague?
    @State private var teamsLoading = false
    @State private var teamsError: String?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 22),
        GridItem(.flexible(), spacing: 22),
        GridItem(.flexible(), spacing: 22)
    ]

    private var selectedLeague: SportsLeague {
        SportsLeague(rawValue: selectedLeagueRaw) ?? .nfl
    }

    private var selectedFilter: SportsFilter {
        SportsFilter(rawValue: selectedFilterRaw) ?? .all
    }

    private var selectedSection: SportsSection {
        SportsSection(rawValue: selectedSectionRaw) ?? .scores
    }

    private var events: [SportsEvent] {
        viewModel.eventsByLeague[selectedLeague] ?? []
    }

    private var visibleEvents: [SportsEvent] {
        let filtered: [SportsEvent]
        switch selectedFilter {
        case .all: filtered = events
        case .live: filtered = events.filter(\.isLive)
        case .upcoming: filtered = events.filter(\.isUpcoming)
        case .final: filtered = events.filter(\.isFinal)
        case .favorites: filtered = events.filter(isFavorite)
        }

        return filtered.sorted { lhs, rhs in
            let lhsFavorite = isFavorite(lhs)
            let rhsFavorite = isFavorite(rhs)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            let lhsRank = eventRank(lhs)
            let rhsRank = eventRank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return (lhs.startDate ?? .distantFuture) < (rhs.startDate ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.03, green: 0.08, blue: 0.16), Color(red: 0.07, green: 0.15, blue: 0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        leaguePicker
                        sectionPicker

                        if selectedSection == .scores,
                           let error = viewModel.errorByLeague[selectedLeague], !events.isEmpty {
                            staleDataBanner(error)
                        }

                        sectionContent
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 36)
                }
            }
            .navigationBarHidden(true)
        }
        .task(id: scoreboardTaskID) {
            guard scenePhase == .active, isActive else { return }
            if !viewModel.hasAnyData { await viewModel.refreshAll() }
            guard !Task.isCancelled, scenePhase == .active, isActive else { return }
            await adaptiveRefreshLoop(for: selectedLeague)
        }
        .task(id: deepDataTaskID) {
            guard scenePhase == .active, isActive else { return }
            switch selectedSection {
            case .schedule: await loadSchedule()
            case .standings: await loadStandings()
            case .teams: await loadTeams()
            case .scores: break
            }
        }
    }

    private var scoreboardTaskID: String {
        "\(selectedLeague.rawValue)-\(scenePhase == .active ? "active" : "inactive")-\(isActive ? "visible" : "hidden")"
    }

    private var deepDataTaskID: String {
        let day = Calendar.current.startOfDay(for: scheduleDate).timeIntervalSince1970
        return "\(selectedLeague.rawValue)-\(selectedSection.rawValue)-\(Int(day))-\(isActive)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 14) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 34, weight: .bold))
                    Text("SPORTS CENTER")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                }
                Text("Scores → box scores → teams → rosters → player profiles and game logs")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.refreshDescription(for: selectedLeague))
                    .font(.caption.bold())
                    .foregroundStyle(events.contains(where: \.isLive) ? Color.red : Color.secondary)
                if let updated = viewModel.lastUpdatedByLeague[selectedLeague] {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    await viewModel.refresh(selectedLeague, force: true)
                    if selectedSection == .schedule { await loadSchedule(force: true) }
                    if selectedSection == .standings { await loadStandings(force: true) }
                    if selectedSection == .teams { await loadTeams(force: true) }
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.loadingLeagues.contains(selectedLeague))
        }
    }

    private var leaguePicker: some View {
        HStack(spacing: 16) {
            ForEach(SportsLeague.allCases) { league in
                Button {
                    selectedLeagueRaw = league.rawValue
                    selectedFilterRaw = SportsFilter.all.rawValue
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: league.symbol)
                        Text(league.rawValue).fontWeight(.bold)
                        if (viewModel.eventsByLeague[league] ?? []).contains(where: \.isLive) {
                            Circle().fill(.red).frame(width: 10, height: 10)
                        }
                    }
                    .frame(minWidth: 145)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedLeague == league ? .white : .gray.opacity(0.28))
                .foregroundStyle(selectedLeague == league ? .black : .white)
            }

            Spacer()
            Label(selectedLeague.favoriteTeamName, systemImage: "star.fill")
                .font(.caption.bold())
                .foregroundStyle(.yellow)
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 14) {
            ForEach(SportsSection.allCases) { section in
                Button {
                    selectedSectionRaw = section.rawValue
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(.headline)
                        .frame(minWidth: 170)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedSection == section ? .blue : .gray.opacity(0.24))
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .scores: scoresSection
        case .schedule: scheduleSection
        case .standings: standingsSection
        case .teams: teamsSection
        }
    }

    // MARK: Scores

    private var scoresSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            scoreboardSummary
            filterPicker

            if viewModel.isInitialLoading && viewModel.eventsByLeague.isEmpty {
                loadingState("Loading all scoreboards…")
            } else if events.isEmpty {
                emptyState(symbol: "sportscourt", title: "No \(selectedLeague.rawValue) games on the current scoreboard", detail: viewModel.errorByLeague[selectedLeague])
            } else if visibleEvents.isEmpty {
                emptyState(symbol: selectedFilter.symbol, title: "Nothing in \(selectedFilter.rawValue)", detail: "Try another filter.")
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 22) {
                    ForEach(visibleEvents) { event in
                        GameCard(event: event, league: selectedLeague, isFavorite: isFavorite(event))
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }

    private var scoreboardSummary: some View {
        HStack(spacing: 18) {
            summaryTile(title: "Games", value: "\(events.count)", symbol: "list.number")
            summaryTile(title: "Live", value: "\(events.filter(\.isLive).count)", symbol: "dot.radiowaves.left.and.right", accent: .red)
            summaryTile(title: "Upcoming", value: "\(events.filter(\.isUpcoming).count)", symbol: "clock.fill")
            summaryTile(title: "Final", value: "\(events.filter(\.isFinal).count)", symbol: "checkmark.circle.fill")
            summaryTile(title: "Colorado", value: "\(events.filter(isFavorite).count)", symbol: "star.fill", accent: .yellow)
        }
    }

    private var filterPicker: some View {
        HStack(spacing: 12) {
            Text("SHOW").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(SportsFilter.allCases) { filter in
                Button {
                    selectedFilterRaw = filter.rawValue
                } label: {
                    Label(filter.rawValue, systemImage: filter.symbol).font(.headline)
                }
                .buttonStyle(.bordered)
                .tint(selectedFilter == filter ? .white : .gray.opacity(0.25))
            }
            Spacer()
            Text("\(visibleEvents.count) shown").font(.caption.bold()).foregroundStyle(.secondary)
        }
    }

    // MARK: League schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("LEAGUE SCHEDULE", detail: "Pick a day. Only that day's scoreboard is fetched.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(scheduleDates, id: \.self) { date in
                        Button {
                            scheduleDate = date
                        } label: {
                            VStack(spacing: 3) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption.bold())
                                Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.headline)
                                if Calendar.current.isDateInToday(date) {
                                    Text("TODAY").font(.caption2.bold()).foregroundStyle(.yellow)
                                }
                            }
                            .frame(width: 125, height: 72)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Calendar.current.isDate(date, inSameDayAs: scheduleDate) ? .blue : .gray.opacity(0.25))
                    }
                }
                .padding(.vertical, 10)
            }

            if scheduleLoading {
                loadingState("Loading \(selectedLeague.rawValue) schedule…")
            } else if let scheduleError {
                emptyState(symbol: "wifi.exclamationmark", title: "Schedule unavailable", detail: scheduleError)
            } else if scheduleEvents.isEmpty {
                emptyState(symbol: "calendar.badge.minus", title: "No games this day", detail: "Choose another date.")
            } else {
                LazyVGrid(columns: gridColumns, spacing: 22) {
                    ForEach(scheduleEvents) { event in
                        GameCard(event: event, league: selectedLeague, isFavorite: isFavorite(event))
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }

    private var scheduleDates: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return (-7...14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: Standings

    private var standingsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle("STANDINGS", detail: "Open any team to drill into its profile, roster and full schedule.")

            if standingsLoading {
                loadingState("Loading standings…")
            } else if let standingsError {
                emptyState(symbol: "wifi.exclamationmark", title: "Standings unavailable", detail: standingsError)
            } else if standings.isEmpty {
                emptyState(symbol: "list.number", title: "No standings returned", detail: "Try Refresh.")
            } else {
                ForEach(standings) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.name.uppercased())
                            .font(.title2.bold())

                        VStack(spacing: 2) {
                            standingHeader
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                NavigationLink {
                                    TeamProfileView(league: selectedLeague, teamID: row.teamID, fallbackName: row.teamName)
                                } label: {
                                    StandingRowView(index: index + 1, row: row)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }

    private var standingHeader: some View {
        HStack(spacing: 14) {
            Text("#").frame(width: 50, alignment: .center)
            Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
            Text("RECORD").frame(width: 130)
            Text("STREAK").frame(width: 110)
            Text("GB").frame(width: 80)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Teams

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle("TEAMS", detail: "Team profiles include record, venue, coach, roster and complete team schedule.")

            if teamsLoading {
                loadingState("Loading teams…")
            } else if let teamsError {
                emptyState(symbol: "wifi.exclamationmark", title: "Teams unavailable", detail: teamsError)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 22) {
                    ForEach(teams) { team in
                        NavigationLink {
                            TeamProfileView(league: selectedLeague, teamID: team.id, fallbackName: team.displayName)
                        } label: {
                            TeamCard(team: team, isFavorite: selectedLeague.favoriteTeamAbbreviations.contains(team.abbreviation))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }

    // MARK: Shared

    private func summaryTile(title: String, value: String, symbol: String, accent: Color = .white) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func loadingState(_ text: String) -> some View {
        HStack(spacing: 18) {
            ProgressView()
            Text(text).font(.title2)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func emptyState(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            if let detail { Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func staleDataBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
            Text("Latest refresh failed. Showing the last successful scoreboard.").fontWeight(.semibold)
            Spacer()
            Text(error).lineLimit(1).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }

    private func isFavorite(_ event: SportsEvent) -> Bool {
        let favorites = selectedLeague.favoriteTeamAbbreviations
        return [event.homeTeam?.team.abbreviation, event.awayTeam?.team.abbreviation]
            .compactMap { $0 }
            .contains(where: favorites.contains)
    }

    private func eventRank(_ event: SportsEvent) -> Int {
        if event.isLive { return 0 }
        if event.isUpcoming { return 1 }
        return 2
    }

    private func loadSchedule(force: Bool = false) async {
        guard !scheduleLoading else { return }
        scheduleLoading = true
        scheduleError = nil
        defer { scheduleLoading = false }
        do {
            scheduleEvents = try await SportsService.fetchScoreboard(for: selectedLeague, date: scheduleDate)
        } catch is CancellationError {
            return
        } catch {
            scheduleEvents = []
            scheduleError = error.localizedDescription
        }
    }

    private func loadStandings(force: Bool = false) async {
        if !force, standingsLeague == selectedLeague, !standings.isEmpty { return }
        guard !standingsLoading else { return }
        standingsLoading = true
        standingsError = nil
        defer { standingsLoading = false }
        do {
            standings = try await SportsService.fetchStandings(for: selectedLeague)
            standingsLeague = selectedLeague
        } catch is CancellationError {
            return
        } catch {
            standings = []
            standingsError = error.localizedDescription
        }
    }

    private func loadTeams(force: Bool = false) async {
        if !force, teamsLeague == selectedLeague, !teams.isEmpty { return }
        guard !teamsLoading else { return }
        teamsLoading = true
        teamsError = nil
        defer { teamsLoading = false }
        do {
            teams = try await SportsService.fetchTeams(for: selectedLeague)
            teamsLeague = selectedLeague
        } catch is CancellationError {
            return
        } catch {
            teams = []
            teamsError = error.localizedDescription
        }
    }

    private func adaptiveRefreshLoop(for league: SportsLeague) async {
        while !Task.isCancelled {
            guard scenePhase == .active, isActive else { return }
            let interval = viewModel.recommendedRefreshInterval(for: league)
            let elapsed = viewModel.refreshReferenceDate(for: league).map { Date().timeIntervalSince($0) } ?? interval
            if elapsed >= interval { await viewModel.refresh(league, force: true) }
            guard !Task.isCancelled, scenePhase == .active, isActive else { return }
            let updatedInterval = viewModel.recommendedRefreshInterval(for: league)
            let updatedElapsed = viewModel.refreshReferenceDate(for: league).map { Date().timeIntervalSince($0) } ?? max(updatedInterval - 5, 0)
            let wait = max(5, updatedInterval - updatedElapsed)
            do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) } catch { return }
        }
    }
}

// MARK: - Score / team cards

private struct GameCard: View {
    let event: SportsEvent
    let league: SportsLeague
    let isFavorite: Bool

    var body: some View {
        NavigationLink {
            GameDetailView(league: league, event: event)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusBadge(event: event)
                    if isFavorite {
                        Label("COLORADO", systemImage: "star.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    if let network = event.network {
                        Text(network).font(.caption.bold()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                TeamScoreRow(competitor: event.awayTeam)
                Divider().opacity(0.25)
                TeamScoreRow(competitor: event.homeTeam)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    if let startDate = event.startDate, event.isUpcoming {
                        Label(startDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                    if let venue = event.venueText {
                        Label(venue, systemImage: "mappin.and.ellipse").lineLimit(1)
                    }
                    HStack {
                        Label("Box score & details", systemImage: "rectangle.and.text.magnifyingglass")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(.white)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 290, maxHeight: 290, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(isFavorite ? Color.yellow.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TeamScoreRow: View {
    let competitor: Competitor?

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: competitor?.team.logo, fallback: "shield.fill", size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(competitor?.team.displayName ?? "Team").font(.headline).lineLimit(1)
                if let record = competitor?.record { Text(record).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(competitor?.score ?? "–")
                .font(.system(size: 36, weight: .black, design: .rounded))
        }
    }
}

private struct StatusBadge: View {
    let event: SportsEvent

    var body: some View {
        HStack(spacing: 6) {
            if event.isLive { Circle().fill(.red).frame(width: 8, height: 8) }
            Text(statusText).lineLimit(1)
        }
        .font(.caption.bold())
        .foregroundStyle(event.isLive ? Color.red : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((event.isLive ? Color.red : Color.white).opacity(0.10), in: Capsule())
    }

    private var statusText: String {
        if let detail = event.status.type.shortDetail, !detail.isEmpty { return detail }
        return event.status.type.description ?? "Scheduled"
    }
}

private struct StandingRowView: View {
    let index: Int
    let row: StandingRow

    var body: some View {
        HStack(spacing: 14) {
            Text(row.rank ?? "\(index)").font(.headline).frame(width: 50)
            HStack(spacing: 12) {
                RemoteImage(urlString: row.logo, fallback: "shield.fill", size: 42)
                Text(row.teamName).font(.headline).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.record).font(.headline).frame(width: 130)
            Text(row.streak ?? "—").frame(width: 110)
            Text(row.gamesBehind ?? "—").frame(width: 80)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
    }
}

private struct TeamCard: View {
    let team: LeagueTeam
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                RemoteImage(urlString: team.logo, fallback: "shield.fill", size: 82)
                Spacer()
                if isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.title2) }
            }
            Spacer()
            Text(team.displayName).font(.title2.bold()).lineLimit(2)
            HStack {
                Text(team.abbreviation).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Label("Profile", systemImage: "chevron.right").font(.caption.bold())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 235)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(isFavorite ? Color.yellow.opacity(0.45) : Color.white.opacity(0.08), lineWidth: isFavorite ? 2 : 1)
        }
    }
}

// MARK: - Game detail / box score

private struct GameDetailView: View {
    let league: SportsLeague
    let event: SportsEvent

    private enum Section: String, CaseIterable, Identifiable {
        case box = "Box Score"
        case teamStats = "Team Stats"
        case players = "Players"
        case scoring = "Scoring"
        var id: String { rawValue }
    }

    @State private var section: Section = .box
    @State private var detail: GameDetailData?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.04, green: 0.10, blue: 0.18)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    gameHero
                    detailPicker

                    if loading {
                        HStack(spacing: 16) { ProgressView(); Text("Loading game package…").font(.title2) }
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else if let error, detail == nil {
                        messageState(symbol: "wifi.exclamationmark", title: "Game details unavailable", detail: error)
                    } else {
                        detailContent
                    }
                }
                .padding(.horizontal, 62)
                .padding(.vertical, 34)
            }
        }
        .navigationTitle(event.shortName ?? event.name)
        .task { await load() }
    }

    private var gameHero: some View {
        VStack(spacing: 20) {
            HStack {
                StatusBadge(event: event)
                if let network = event.network { Label(network, systemImage: "tv.fill").font(.headline).foregroundStyle(.secondary) }
                Spacer()
                if let date = event.startDate { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.headline) }
            }

            HStack(spacing: 40) {
                teamHero(event.awayTeam)
                VStack(spacing: 6) {
                    Text(event.isUpcoming ? "AT" : "")
                        .font(.headline).foregroundStyle(.secondary)
                    Text(event.isUpcoming ? "" : "–")
                        .font(.system(size: 34, weight: .black))
                }
                teamHero(event.homeTeam)
            }

            if let venue = event.venueText {
                Label(venue, systemImage: "mappin.and.ellipse").font(.headline).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private func teamHero(_ competitor: Competitor?) -> some View {
        NavigationLink {
            TeamProfileView(league: league, teamID: competitor?.team.id ?? "", fallbackName: competitor?.team.displayName ?? "Team")
        } label: {
            VStack(spacing: 10) {
                RemoteImage(urlString: competitor?.team.logo, fallback: "shield.fill", size: 100)
                Text(competitor?.team.displayName ?? "Team").font(.title2.bold()).lineLimit(1)
                Text(competitor?.score ?? "–").font(.system(size: 58, weight: .black, design: .rounded))
                if let record = competitor?.record { Text(record).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(competitor == nil)
    }

    private var detailPicker: some View {
        HStack(spacing: 12) {
            ForEach(Section.allCases) { item in
                Button(item.rawValue) { section = item }
                    .buttonStyle(.borderedProminent)
                    .tint(section == item ? .blue : .gray.opacity(0.25))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch section {
        case .box: boxScore
        case .teamStats: teamStats
        case .players: playerStats
        case .scoring: scoringPlays
        }
    }

    private var boxScore: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("BOX SCORE").font(.title2.bold())
            PeriodScoreTable(event: event)

            if let detail, !detail.facts.isEmpty {
                HStack(spacing: 16) {
                    ForEach(detail.facts) { fact in
                        StatPill(label: fact.label, value: fact.value)
                    }
                }
            }

            if let detail, !detail.teamStats.isEmpty {
                Text("TEAM SNAPSHOT").font(.headline).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 20) {
                    ForEach(detail.teamStats) { team in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { RemoteImage(urlString: team.logo, fallback: "shield.fill", size: 44); Text(team.teamName).font(.headline) }
                            ForEach(team.stats.prefix(6)) { stat in
                                HStack { Text(stat.label).foregroundStyle(.secondary); Spacer(); Text(stat.value).fontWeight(.bold) }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }

    private var teamStats: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TEAM STATS").font(.title2.bold())
            if let detail, !detail.teamStats.isEmpty {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(detail.teamStats) { team in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { RemoteImage(urlString: team.logo, fallback: "shield.fill", size: 50); Text(team.teamName).font(.title2.bold()) }
                            ForEach(team.stats) { stat in
                                HStack { Text(stat.label).foregroundStyle(.secondary); Spacer(); Text(stat.value).font(.headline) }
                                Divider().opacity(0.15)
                            }
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
            } else {
                messageState(symbol: "chart.bar", title: "No team stats yet", detail: "Stats populate as ESPN publishes the game package.")
            }
        }
        .padding(.bottom, 50)
    }

    private var playerStats: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("PLAYER BOX SCORE").font(.title2.bold())
            if let detail, !detail.playerGroups.isEmpty {
                ForEach(detail.playerGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(group.teamName).font(.headline); Text("·"); Text(group.category).font(.headline).foregroundStyle(.secondary) }
                        VStack(spacing: 2) {
                            ForEach(group.players) { row in
                                NavigationLink {
                                    PlayerProfileView(league: league, fallbackAthlete: row.athlete)
                                } label: {
                                    PlayerStatRow(row: row, labels: group.labels)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            } else {
                messageState(symbol: "person.text.rectangle", title: "No player box score yet", detail: "Player lines appear once ESPN publishes them for this game.")
            }
        }
        .padding(.bottom, 50)
    }

    private var scoringPlays: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SCORING PLAYS").font(.title2.bold())
            if let detail, !detail.scoringPlays.isEmpty {
                ForEach(detail.scoringPlays) { play in
                    HStack(spacing: 16) {
                        RemoteImage(urlString: play.teamLogo, fallback: "sportscourt.fill", size: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(play.text).font(.headline)
                            HStack {
                                if let period = play.period { Text("Period \(period)") }
                                if let clock = play.clock { Text(clock) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let away = play.awayScore, let home = play.homeScore {
                            Text("\(away) – \(home)").font(.title3.bold())
                        }
                    }
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            } else {
                messageState(symbol: "list.bullet.rectangle", title: "No scoring plays", detail: "Scoring timeline is available for supported games after scoring begins.")
            }
        }
        .padding(.bottom, 50)
    }

    private func messageState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 54)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do { detail = try await SportsService.fetchGameDetail(for: league, eventID: event.id) }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}

private struct PeriodScoreTable: View {
    let event: SportsEvent

    private var maxPeriods: Int {
        max(event.awayTeam?.linescores?.count ?? 0, event.homeTeam?.linescores?.count ?? 0)
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(1...max(maxPeriods, 1), id: \.self) { period in
                    Text(periodLabel(period)).frame(width: 68)
                }
                Text("T").frame(width: 72)
            }
            .font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 14)

            scoreRow(event.awayTeam)
            scoreRow(event.homeTeam)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func scoreRow(_ competitor: Competitor?) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                RemoteImage(urlString: competitor?.team.logo, fallback: "shield.fill", size: 38)
                Text(competitor?.team.abbreviation ?? "TEAM").font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(0..<max(maxPeriods, 1), id: \.self) { index in
                Text(lineScore(competitor, index: index)).frame(width: 68)
            }
            Text(competitor?.score ?? "–").font(.title3.bold()).frame(width: 72)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func lineScore(_ competitor: Competitor?, index: Int) -> String {
        guard let scores = competitor?.linescores, scores.indices.contains(index) else { return "–" }
        return scores[index].displayValue ?? scores[index].value.map { String(Int($0)) } ?? "–"
    }

    private func periodLabel(_ period: Int) -> String {
        switch event.season?.type {
        default: return "\(period)"
        }
    }
}

private struct PlayerStatRow: View {
    let row: GamePlayerStat
    let labels: [String]

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: row.athlete.headshot, fallback: "person.crop.circle.fill", size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.athlete.displayName).font(.headline)
                Text([row.athlete.position, row.athlete.jersey.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 260, alignment: .leading)

            ForEach(Array(row.stats.prefix(7).enumerated()), id: \.offset) { index, value in
                VStack(spacing: 2) {
                    Text(labels.indices.contains(index) ? labels[index] : "STAT").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(value).font(.headline).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - Team profile

private struct TeamProfileView: View {
    let league: SportsLeague
    let teamID: String
    let fallbackName: String

    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case roster = "Roster"
        case schedule = "Schedule"
        var id: String { rawValue }
    }

    @State private var profile: TeamProfileData?
    @State private var schedule: [SportsEvent] = []
    @State private var section: Section = .overview
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.10, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    teamHero
                    picker
                    if loading && profile == nil {
                        HStack(spacing: 16) { ProgressView(); Text("Loading team profile…").font(.title2) }.frame(maxWidth: .infinity, minHeight: 300)
                    } else if let error, profile == nil {
                        infoState("Team profile unavailable", detail: error)
                    } else {
                        content
                    }
                }
                .padding(.horizontal, 62)
                .padding(.vertical, 34)
            }
        }
        .navigationTitle(profile?.team.displayName ?? fallbackName)
        .task { await load() }
    }

    private var teamHero: some View {
        HStack(spacing: 28) {
            RemoteImage(urlString: profile?.team.logo, fallback: "shield.fill", size: 120)
            VStack(alignment: .leading, spacing: 7) {
                Text(profile?.team.displayName ?? fallbackName).font(.system(size: 46, weight: .black, design: .rounded))
                if let record = profile?.record { Text(record).font(.title2.bold()) }
                if let standing = profile?.standingSummary { Text(standing).font(.headline).foregroundStyle(.secondary) }
            }
            Spacer()
            if league.favoriteTeamAbbreviations.contains(profile?.team.abbreviation ?? "") {
                Label("COLORADO FAVORITE", systemImage: "star.fill").foregroundStyle(.yellow).font(.headline)
            }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private var picker: some View {
        HStack(spacing: 12) {
            ForEach(Section.allCases) { item in
                Button(item.rawValue) { section = item }
                    .buttonStyle(.borderedProminent)
                    .tint(section == item ? .blue : .gray.opacity(0.25))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview: overview
        case .roster: roster
        case .schedule: teamSchedule
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TEAM PROFILE").font(.title2.bold())
            if let profile {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(profile.facts) { fact in StatPill(label: fact.label, value: fact.value) }
                }

                HStack(spacing: 18) {
                    profile.roster.prefix(3).map { group in
                        StatPill(label: group.name, value: "\(group.athletes.count) players")
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("ROSTER").font(.title2.bold())
            if let profile, !profile.roster.isEmpty {
                ForEach(profile.roster) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.name.uppercased()).font(.headline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(group.athletes) { athlete in
                                NavigationLink {
                                    PlayerProfileView(league: league, fallbackAthlete: athlete)
                                } label: {
                                    AthleteCard(athlete: athlete)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                infoState("Roster unavailable", detail: "No roster data was returned for this team.")
            }
        }
        .padding(.bottom, 50)
    }

    private var teamSchedule: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TEAM SCHEDULE / GAME LOG").font(.title2.bold())
            if schedule.isEmpty {
                infoState("No schedule returned", detail: "Try again later or use the league Schedule screen.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(schedule) { event in
                        GameCard(event: event, league: league, isFavorite: league.favoriteTeamAbbreviations.contains(profile?.team.abbreviation ?? ""))
                    }
                }
            }
        }
        .padding(.bottom, 50)
    }

    private func infoState(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            profile = try await SportsService.fetchTeamProfile(for: league, teamID: teamID)
            schedule = (try? await SportsService.fetchTeamSchedule(for: league, teamID: teamID)) ?? []
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AthleteCard: View {
    let athlete: SportsAthlete

    var body: some View {
        HStack(spacing: 14) {
            RemoteImage(urlString: athlete.headshot, fallback: "person.crop.circle.fill", size: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(athlete.displayName).font(.headline).lineLimit(1)
                Text([athlete.position, athlete.jersey.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let status = athlete.status { Text(status).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Player profile

private struct PlayerProfileView: View {
    let league: SportsLeague
    let fallbackAthlete: SportsAthlete

    @State private var profile: PlayerProfileData?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.07, green: 0.08, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    playerHero
                    if loading && profile == nil {
                        HStack(spacing: 16) { ProgressView(); Text("Loading player profile…").font(.title2) }.frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        if let error {
                            Text("Some player data could not load: \(error)").font(.caption).foregroundStyle(.orange)
                        }
                        profileFacts
                        seasonStats
                        gameLog
                    }
                }
                .padding(.horizontal, 62)
                .padding(.vertical, 34)
            }
        }
        .navigationTitle(profile?.athlete.displayName ?? fallbackAthlete.displayName)
        .task { await load() }
    }

    private var athlete: SportsAthlete { profile?.athlete ?? fallbackAthlete }

    private var playerHero: some View {
        HStack(spacing: 28) {
            RemoteImage(urlString: athlete.headshot, fallback: "person.crop.circle.fill", size: 140)
            VStack(alignment: .leading, spacing: 7) {
                Text(athlete.displayName).font(.system(size: 48, weight: .black, design: .rounded))
                Text([athlete.position, athlete.jersey.map { "#\($0)" }, profile?.teamName].compactMap { $0 }.joined(separator: " · "))
                    .font(.title2).foregroundStyle(.secondary)
                if let status = athlete.status { Text(status.uppercased()).font(.caption.bold()).foregroundStyle(.green) }
            }
            Spacer()
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private var profileFacts: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            if let age = athlete.age { StatPill(label: "Age", value: "\(age)") }
            if let height = athlete.height { StatPill(label: "Height", value: height) }
            if let weight = athlete.weight { StatPill(label: "Weight", value: weight) }
            if let experience = athlete.experience { StatPill(label: "Experience", value: experience) }
            if let debut = profile?.debutYear { StatPill(label: "Debut", value: "\(debut)") }
            if let birthplace = profile?.birthplace { StatPill(label: "Birthplace", value: birthplace) }
        }
    }

    private var seasonStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SEASON SNAPSHOT").font(.title2.bold())
            if let profile, !profile.summaryStats.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(profile.summaryStats) { stat in StatPill(label: stat.label, value: stat.value) }
                }
            } else {
                Text("No season snapshot returned for this player.").foregroundStyle(.secondary)
            }
        }
    }

    private var gameLog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GAME LOG").font(.title2.bold())
            if let profile, !profile.gameLog.isEmpty {
                ForEach(profile.gameLog) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.opponent).font(.headline)
                                Text(row.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let result = row.result { Text(result).font(.headline) }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(row.stats.prefix(10)) { stat in
                                    VStack(spacing: 2) {
                                        Text(stat.label).font(.caption2).foregroundStyle(.secondary)
                                        Text(stat.value).font(.headline)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            } else {
                Text("No game-log rows were returned for this player/sport yet.").foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 50)
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do { profile = try await SportsService.fetchPlayerProfile(for: league, athleteID: fallbackAthlete.id) }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Reusable sports components

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.bold()).lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RemoteImage: View {
    let urlString: String?
    let fallback: String
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: fallback).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: fallback).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
