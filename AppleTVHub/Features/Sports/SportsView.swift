import SwiftUI

struct SportsView: View {
    let isActive: Bool

    private enum Section: String, CaseIterable, Identifiable {
        case scores = "Scores", schedule = "Schedule", standings = "Standings", teams = "Teams"
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

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", live = "Live", upcoming = "Upcoming", final = "Final", favorites = "Colorado"
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
    @AppStorage("sports.selectedLeague") private var leagueRaw = SportsLeague.nfl.rawValue
    @AppStorage("sports.section") private var sectionRaw = Section.scores.rawValue
    @AppStorage("sports.filter") private var filterRaw = Filter.all.rawValue

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

    private let threeColumns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    private var league: SportsLeague { SportsLeague(rawValue: leagueRaw) ?? .nfl }
    private var section: Section { Section(rawValue: sectionRaw) ?? .scores }
    private var filter: Filter { Filter(rawValue: filterRaw) ?? .all }
    private var events: [SportsEvent] { viewModel.eventsByLeague[league] ?? [] }

    private var visibleEvents: [SportsEvent] {
        let values: [SportsEvent]
        switch filter {
        case .all: values = events
        case .live: values = events.filter(\.isLive)
        case .upcoming: values = events.filter(\.isUpcoming)
        case .final: values = events.filter(\.isFinal)
        case .favorites: values = events.filter(isFavorite)
        }
        return values.sorted {
            if isFavorite($0) != isFavorite($1) { return isFavorite($0) }
            let a = $0.isLive ? 0 : ($0.isUpcoming ? 1 : 2)
            let b = $1.isLive ? 0 : ($1.isUpcoming ? 1 : 2)
            if a != b { return a < b }
            return ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, Color(red: 0.03, green: 0.08, blue: 0.16), Color(red: 0.08, green: 0.16, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        leaguePicker
                        sectionPicker
                        if section == .scores, let error = viewModel.errorByLeague[league], !events.isEmpty { staleBanner(error) }
                        content
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
            await refreshLoop(league)
        }
        .task(id: deepTaskID) {
            guard scenePhase == .active, isActive else { return }
            switch section {
            case .scores: break
            case .schedule: await loadSchedule()
            case .standings: await loadStandings()
            case .teams: await loadTeams()
            }
        }
    }

    private var scoreboardTaskID: String { "\(league.rawValue)-\(scenePhase)-\(isActive)" }
    private var deepTaskID: String { "\(league.rawValue)-\(section.rawValue)-\(Int(Calendar.current.startOfDay(for: scheduleDate).timeIntervalSince1970))-\(isActive)" }

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 14) {
                    Image(systemName: "sportscourt.fill").font(.system(size: 34, weight: .bold))
                    Text("SPORTS CENTER").font(.system(size: 50, weight: .black, design: .rounded))
                }
                Text("Scores → box scores → teams → rosters → player profiles and game logs")
                    .font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.refreshDescription(for: league)).font(.caption.bold())
                    .foregroundStyle(events.contains(where: \.isLive) ? Color.red : Color.secondary)
                if let date = viewModel.lastUpdatedByLeague[league] {
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    await viewModel.refresh(league, force: true)
                    if section == .schedule { await loadSchedule() }
                    if section == .standings { await loadStandings(force: true) }
                    if section == .teams { await loadTeams(force: true) }
                }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        }
    }

    private var leaguePicker: some View {
        HStack(spacing: 15) {
            ForEach(SportsLeague.allCases) { item in
                Button {
                    leagueRaw = item.rawValue
                    filterRaw = Filter.all.rawValue
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                        Text(item.rawValue).fontWeight(.bold)
                        if (viewModel.eventsByLeague[item] ?? []).contains(where: \.isLive) { Circle().fill(.red).frame(width: 9, height: 9) }
                    }
                    .frame(minWidth: 145)
                }
                .buttonStyle(.borderedProminent)
                .tint(league == item ? .white : .gray.opacity(0.28))
                .foregroundStyle(league == item ? .black : .white)
            }
            Spacer()
            Label(league.favoriteTeamName, systemImage: "star.fill").font(.caption.bold()).foregroundStyle(.yellow)
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 12) {
            ForEach(Section.allCases) { item in
                Button { sectionRaw = item.rawValue } label: {
                    Label(item.rawValue, systemImage: item.symbol).font(.headline).frame(minWidth: 170)
                }
                .buttonStyle(.borderedProminent)
                .tint(section == item ? .blue : .gray.opacity(0.24))
            }
            Spacer()
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .scores: scoresView
        case .schedule: scheduleView
        case .standings: standingsView
        case .teams: teamsView
        }
    }

    private var scoresView: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                SummaryTile(title: "Games", value: "\(events.count)", symbol: "list.number")
                SummaryTile(title: "Live", value: "\(events.filter(\.isLive).count)", symbol: "dot.radiowaves.left.and.right", accent: .red)
                SummaryTile(title: "Upcoming", value: "\(events.filter(\.isUpcoming).count)", symbol: "clock.fill")
                SummaryTile(title: "Final", value: "\(events.filter(\.isFinal).count)", symbol: "checkmark.circle.fill")
                SummaryTile(title: "Colorado", value: "\(events.filter(isFavorite).count)", symbol: "star.fill", accent: .yellow)
            }
            HStack(spacing: 12) {
                Text("SHOW").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Filter.allCases) { item in
                    Button { filterRaw = item.rawValue } label: { Label(item.rawValue, systemImage: item.symbol).font(.headline) }
                        .buttonStyle(.bordered).tint(filter == item ? .white : .gray.opacity(0.25))
                }
                Spacer()
                Text("\(visibleEvents.count) shown").font(.caption.bold()).foregroundStyle(.secondary)
            }
            if viewModel.isInitialLoading && viewModel.eventsByLeague.isEmpty {
                LoadingPanel(text: "Loading all scoreboards…")
            } else if visibleEvents.isEmpty {
                EmptyPanel(symbol: "sportscourt", title: "No games to show", detail: "Try another filter or refresh.")
            } else {
                LazyVGrid(columns: threeColumns, spacing: 20) {
                    ForEach(visibleEvents) { GameCard(event: $0, league: league, favorite: isFavorite($0)) }
                }
            }
        }
        .padding(.bottom, 50)
    }

    private var scheduleView: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "LEAGUE SCHEDULE", detail: "Pick a day; only that day is fetched.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(scheduleDates, id: \.self) { date in
                        Button { scheduleDate = date } label: {
                            VStack(spacing: 2) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption.bold())
                                Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.headline)
                                if Calendar.current.isDateInToday(date) { Text("TODAY").font(.caption2.bold()).foregroundStyle(.yellow) }
                            }.frame(width: 122, height: 68)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Calendar.current.isDate(date, inSameDayAs: scheduleDate) ? .blue : .gray.opacity(0.25))
                    }
                }.padding(.vertical, 8)
            }
            if scheduleLoading { LoadingPanel(text: "Loading \(league.rawValue) schedule…") }
            else if let scheduleError { EmptyPanel(symbol: "wifi.exclamationmark", title: "Schedule unavailable", detail: scheduleError) }
            else if scheduleEvents.isEmpty { EmptyPanel(symbol: "calendar.badge.minus", title: "No games this day", detail: "Choose another date.") }
            else {
                LazyVGrid(columns: threeColumns, spacing: 20) {
                    ForEach(scheduleEvents) { GameCard(event: $0, league: league, favorite: isFavorite($0)) }
                }
            }
        }.padding(.bottom, 50)
    }

    private var standingsView: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(title: "STANDINGS", detail: "Select a team to open its full profile.")
            if standingsLoading { LoadingPanel(text: "Loading standings…") }
            else if let standingsError { EmptyPanel(symbol: "wifi.exclamationmark", title: "Standings unavailable", detail: standingsError) }
            else if standings.isEmpty { EmptyPanel(symbol: "list.number", title: "No standings returned", detail: "Try Refresh.") }
            else {
                ForEach(standings) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.name.uppercased()).font(.title2.bold())
                        VStack(spacing: 1) {
                            StandingHeader()
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                NavigationLink {
                                    TeamProfileView(league: league, teamID: row.teamID, fallbackName: row.teamName)
                                } label: { StandingRowCard(index: index + 1, row: row) }
                                .buttonStyle(.plain)
                            }
                        }.padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }.padding(.bottom, 50)
    }

    private var teamsView: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(title: "TEAMS", detail: "Profiles include roster, venue, coach and team schedule/game log.")
            if teamsLoading { LoadingPanel(text: "Loading teams…") }
            else if let teamsError { EmptyPanel(symbol: "wifi.exclamationmark", title: "Teams unavailable", detail: teamsError) }
            else {
                LazyVGrid(columns: threeColumns, spacing: 20) {
                    ForEach(teams) { team in
                        NavigationLink {
                            TeamProfileView(league: league, teamID: team.id, fallbackName: team.displayName)
                        } label: { TeamCard(team: team, favorite: league.favoriteTeamAbbreviations.contains(team.abbreviation)) }
                        .buttonStyle(.plain)
                    }
                }
            }
        }.padding(.bottom, 50)
    }

    private var scheduleDates: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return (-7...14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private func isFavorite(_ event: SportsEvent) -> Bool {
        [event.homeTeam?.team.abbreviation, event.awayTeam?.team.abbreviation].compactMap { $0 }.contains { league.favoriteTeamAbbreviations.contains($0) }
    }

    private func staleBanner(_ error: String) -> some View {
        HStack { Image(systemName: "wifi.exclamationmark"); Text("Showing last successful scoreboard.").fontWeight(.semibold); Spacer(); Text(error).lineLimit(1).foregroundStyle(.secondary) }
            .font(.caption).padding(14).background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }

    private func loadSchedule() async {
        guard !scheduleLoading else { return }
        scheduleLoading = true; scheduleError = nil
        defer { scheduleLoading = false }
        do { scheduleEvents = try await SportsService.fetchScoreboard(for: league, date: scheduleDate) }
        catch is CancellationError { return }
        catch { scheduleEvents = []; scheduleError = error.localizedDescription }
    }

    private func loadStandings(force: Bool = false) async {
        if !force, standingsLeague == league, !standings.isEmpty { return }
        guard !standingsLoading else { return }
        standingsLoading = true; standingsError = nil
        defer { standingsLoading = false }
        do { standings = try await SportsService.fetchStandings(for: league); standingsLeague = league }
        catch is CancellationError { return }
        catch { standings = []; standingsError = error.localizedDescription }
    }

    private func loadTeams(force: Bool = false) async {
        if !force, teamsLeague == league, !teams.isEmpty { return }
        guard !teamsLoading else { return }
        teamsLoading = true; teamsError = nil
        defer { teamsLoading = false }
        do { teams = try await SportsService.fetchTeams(for: league); teamsLeague = league }
        catch is CancellationError { return }
        catch { teams = []; teamsError = error.localizedDescription }
    }

    private func refreshLoop(_ targetLeague: SportsLeague) async {
        while !Task.isCancelled {
            guard scenePhase == .active, isActive else { return }
            let interval = viewModel.recommendedRefreshInterval(for: targetLeague)
            let elapsed = viewModel.refreshReferenceDate(for: targetLeague).map { Date().timeIntervalSince($0) } ?? interval
            if elapsed >= interval { await viewModel.refresh(targetLeague, force: true) }
            let current = viewModel.recommendedRefreshInterval(for: targetLeague)
            let since = viewModel.refreshReferenceDate(for: targetLeague).map { Date().timeIntervalSince($0) } ?? 0
            do { try await Task.sleep(nanoseconds: UInt64(max(5, current - since) * 1_000_000_000)) } catch { return }
        }
    }
}

private struct SummaryTile: View {
    let title: String, value: String, symbol: String
    var accent: Color = .white
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .bold)).foregroundStyle(accent).frame(width: 40, height: 40).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) { Text(value).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct SectionHeader: View {
    let title: String, detail: String
    var body: some View { HStack { Text(title).font(.title2.bold()); Spacer(); Text(detail).font(.caption).foregroundStyle(.secondary) } }
}

private struct LoadingPanel: View {
    let text: String
    var body: some View { HStack(spacing: 16) { ProgressView(); Text(text).font(.title2) }.frame(maxWidth: .infinity, minHeight: 280) }
}

private struct EmptyPanel: View {
    let symbol: String, title: String, detail: String
    var body: some View {
        VStack(spacing: 14) { Image(systemName: symbol).font(.system(size: 58)).foregroundStyle(.secondary); Text(title).font(.title2.bold()); Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct GameCard: View {
    let event: SportsEvent, league: SportsLeague, favorite: Bool
    var body: some View {
        NavigationLink {
            GameDetailView(league: league, event: event)
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack { StatusBadge(event: event); if favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }; Spacer(); if let network = event.network { Text(network).font(.caption.bold()).foregroundStyle(.secondary) } }
                TeamScoreRow(competitor: event.awayTeam)
                Divider().opacity(0.25)
                TeamScoreRow(competitor: event.homeTeam)
                Spacer(minLength: 0)
                if let date = event.startDate, event.isUpcoming { Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar") }
                if let venue = event.venueText { Label(venue, systemImage: "mappin.and.ellipse").lineLimit(1) }
                HStack { Label("Box score & details", systemImage: "rectangle.and.text.magnifyingglass"); Spacer(); Image(systemName: "chevron.right") }.foregroundStyle(.white)
            }
            .font(.caption).padding(20).frame(maxWidth: .infinity, minHeight: 290, maxHeight: 290, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23))
            .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(favorite ? Color.yellow.opacity(0.4) : Color.white.opacity(0.08), lineWidth: favorite ? 2 : 1) }
        }.buttonStyle(.plain)
    }
}

private struct TeamScoreRow: View {
    let competitor: Competitor?
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: competitor?.team.logo, fallback: "shield.fill", size: 50)
            VStack(alignment: .leading, spacing: 2) { Text(competitor?.team.displayName ?? "Team").font(.headline).lineLimit(1); if let record = competitor?.record { Text(record).font(.caption).foregroundStyle(.secondary) } }
            Spacer(); Text(competitor?.score ?? "–").font(.system(size: 35, weight: .black, design: .rounded))
        }
    }
}

private struct StatusBadge: View {
    let event: SportsEvent
    var body: some View {
        HStack(spacing: 6) { if event.isLive { Circle().fill(.red).frame(width: 8, height: 8) }; Text(event.status.type.shortDetail ?? event.status.type.description ?? "Scheduled").lineLimit(1) }
            .font(.caption.bold()).foregroundStyle(event.isLive ? Color.red : Color.primary).padding(.horizontal, 10).padding(.vertical, 6)
            .background((event.isLive ? Color.red : Color.white).opacity(0.10), in: Capsule())
    }
}

private struct StandingHeader: View {
    var body: some View {
        HStack(spacing: 12) { Text("#").frame(width: 48); Text("TEAM").frame(maxWidth: .infinity, alignment: .leading); Text("RECORD").frame(width: 125); Text("STRK").frame(width: 90); Text("GB").frame(width: 70) }
            .font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
    }
}

private struct StandingRowCard: View {
    let index: Int, row: StandingRow
    var body: some View {
        HStack(spacing: 12) {
            Text(row.rank ?? "\(index)").font(.headline).frame(width: 48)
            HStack(spacing: 10) { RemoteImage(urlString: row.logo, fallback: "shield.fill", size: 40); Text(row.teamName).font(.headline).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
            Text(row.record).font(.headline).frame(width: 125); Text(row.streak ?? "—").frame(width: 90); Text(row.gamesBehind ?? "—").frame(width: 70); Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding(.horizontal, 12).padding(.vertical, 12).background(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
    }
}

private struct TeamCard: View {
    let team: LeagueTeam, favorite: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { RemoteImage(urlString: team.logo, fallback: "shield.fill", size: 78); Spacer(); if favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.title2) } }
            Spacer(); Text(team.displayName).font(.title2.bold()).lineLimit(2)
            HStack { Text(team.abbreviation).foregroundStyle(.secondary); Spacer(); Label("Profile", systemImage: "chevron.right").font(.caption.bold()) }
        }.padding(22).frame(maxWidth: .infinity, minHeight: 225).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23))
            .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(favorite ? Color.yellow.opacity(0.45) : Color.white.opacity(0.08), lineWidth: favorite ? 2 : 1) }
    }
}

private struct GameDetailView: View {
    let league: SportsLeague, event: SportsEvent
    private enum Section: String, CaseIterable, Identifiable { case box = "Box Score", team = "Team Stats", players = "Players", scoring = "Scoring"; var id: String { rawValue } }
    @State private var section: Section = .box
    @State private var detail: GameDetailData?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.04, green: 0.10, blue: 0.18)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    HStack(spacing: 12) { ForEach(Section.allCases) { item in Button(item.rawValue) { section = item }.buttonStyle(.borderedProminent).tint(section == item ? .blue : .gray.opacity(0.25)) }; Spacer() }
                    if loading { LoadingPanel(text: "Loading game package…") }
                    else if let error, detail == nil { EmptyPanel(symbol: "wifi.exclamationmark", title: "Game details unavailable", detail: error) }
                    else { sectionContent }
                }.padding(.horizontal, 62).padding(.vertical, 34)
            }
        }.navigationTitle(event.shortName ?? event.name).task { await load() }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            HStack { StatusBadge(event: event); if let network = event.network { Label(network, systemImage: "tv.fill").foregroundStyle(.secondary) }; Spacer(); if let date = event.startDate { Text(date.formatted(date: .abbreviated, time: .shortened)) } }
            HStack(spacing: 32) { teamHero(event.awayTeam); Text(event.isUpcoming ? "AT" : "").font(.title2.bold()).foregroundStyle(.secondary); teamHero(event.homeTeam) }
            if let venue = event.venueText { Label(venue, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
        }.padding(26).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27))
    }

    private func teamHero(_ competitor: Competitor?) -> some View {
        NavigationLink {
            TeamProfileView(league: league, teamID: competitor?.team.id ?? "", fallbackName: competitor?.team.displayName ?? "Team")
        } label: {
            VStack(spacing: 8) { RemoteImage(urlString: competitor?.team.logo, fallback: "shield.fill", size: 92); Text(competitor?.team.displayName ?? "Team").font(.title2.bold()).lineLimit(1); Text(competitor?.score ?? "–").font(.system(size: 54, weight: .black)); if let r = competitor?.record { Text(r).foregroundStyle(.secondary) } }
                .frame(maxWidth: .infinity)
        }.buttonStyle(.plain).disabled(competitor == nil)
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .box: boxScore
        case .team: teamStats
        case .players: playerStats
        case .scoring: scoring
        }
    }

    private var boxScore: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("BOX SCORE").font(.title2.bold()); PeriodScoreTable(event: event)
            if let detail {
                if !detail.facts.isEmpty { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(detail.facts) { StatPill(label: $0.label, value: $0.value) } } }
                if !detail.teamStats.isEmpty { Text("TEAM SNAPSHOT").font(.headline).foregroundStyle(.secondary); teamStatColumns(detail.teamStats, limit: 6) }
            }
        }.padding(.bottom, 50)
    }

    private var teamStats: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TEAM STATS").font(.title2.bold())
            if let detail, !detail.teamStats.isEmpty { teamStatColumns(detail.teamStats, limit: nil) }
            else { EmptyPanel(symbol: "chart.bar", title: "No team stats yet", detail: "Stats appear as ESPN publishes the game package.") }
        }.padding(.bottom, 50)
    }

    private func teamStatColumns(_ teams: [GameTeamStats], limit: Int?) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(teams) { team in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { RemoteImage(urlString: team.logo, fallback: "shield.fill", size: 44); Text(team.teamName).font(.headline) }
                    ForEach(Array((limit == nil ? team.stats : Array(team.stats.prefix(limit!))))) { stat in HStack { Text(stat.label).foregroundStyle(.secondary); Spacer(); Text(stat.value).fontWeight(.bold) }; Divider().opacity(0.12) }
                }.padding(18).frame(maxWidth: .infinity).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var playerStats: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("PLAYER BOX SCORE").font(.title2.bold())
            if let detail, !detail.playerGroups.isEmpty {
                ForEach(detail.playerGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.teamName) · \(group.category)").font(.headline)
                        VStack(spacing: 1) {
                            ForEach(group.players) { row in
                                NavigationLink { PlayerProfileView(league: league, fallbackAthlete: row.athlete) } label: { PlayerStatRow(row: row, labels: group.labels) }.buttonStyle(.plain)
                            }
                        }.padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            } else { EmptyPanel(symbol: "person.text.rectangle", title: "No player box score yet", detail: "Player lines appear when ESPN publishes them.") }
        }.padding(.bottom, 50)
    }

    private var scoring: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SCORING PLAYS").font(.title2.bold())
            if let detail, !detail.scoringPlays.isEmpty {
                ForEach(detail.scoringPlays) { play in
                    HStack(spacing: 14) { RemoteImage(urlString: play.teamLogo, fallback: "sportscourt.fill", size: 44); VStack(alignment: .leading) { Text(play.text).font(.headline); Text([play.period.map { "Period \($0)" }, play.clock].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let a = play.awayScore, let h = play.homeScore { Text("\(a) – \(h)").font(.title3.bold()) } }
                        .padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                }
            } else { EmptyPanel(symbol: "list.bullet.rectangle", title: "No scoring plays", detail: "The scoring timeline appears after scoring begins.") }
        }.padding(.bottom, 50)
    }

    private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        do { detail = try await SportsService.fetchGameDetail(for: league, eventID: event.id) }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}

private struct PeriodScoreTable: View {
    let event: SportsEvent
    private var periods: Int { max(event.awayTeam?.linescores?.count ?? 0, event.homeTeam?.linescores?.count ?? 0, 1) }
    var body: some View {
        VStack(spacing: 2) {
            HStack { Text("TEAM").frame(maxWidth: .infinity, alignment: .leading); ForEach(1...periods, id: \.self) { Text("\($0)").frame(width: 64) }; Text("T").frame(width: 68) }.font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 12)
            row(event.awayTeam); row(event.homeTeam)
        }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 19))
    }
    private func row(_ c: Competitor?) -> some View {
        HStack { HStack(spacing: 9) { RemoteImage(urlString: c?.team.logo, fallback: "shield.fill", size: 36); Text(c?.team.abbreviation ?? "TEAM").font(.headline) }.frame(maxWidth: .infinity, alignment: .leading); ForEach(0..<periods, id: \.self) { i in Text(score(c, i)).frame(width: 64) }; Text(c?.score ?? "–").font(.title3.bold()).frame(width: 68) }.padding(.horizontal, 12).padding(.vertical, 9)
    }
    private func score(_ c: Competitor?, _ index: Int) -> String { guard let scores = c?.linescores, scores.indices.contains(index) else { return "–" }; return scores[index].displayValue ?? scores[index].value.map { String(Int($0)) } ?? "–" }
}

private struct PlayerStatRow: View {
    let row: GamePlayerStat, labels: [String]
    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(urlString: row.athlete.headshot, fallback: "person.crop.circle.fill", size: 44)
            VStack(alignment: .leading, spacing: 2) { Text(row.athlete.displayName).font(.headline); Text([row.athlete.position, row.athlete.jersey.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }.frame(width: 250, alignment: .leading)
            ForEach(Array(row.stats.prefix(7).enumerated()), id: \.offset) { i, value in VStack(spacing: 2) { Text(labels.indices.contains(i) ? labels[i] : "STAT").font(.caption2).foregroundStyle(.secondary).lineLimit(1); Text(value).font(.headline).lineLimit(1) }.frame(maxWidth: .infinity) }
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding(11)
    }
}

private struct TeamProfileView: View {
    let league: SportsLeague, teamID: String, fallbackName: String
    private enum Section: String, CaseIterable, Identifiable { case overview = "Overview", roster = "Roster", schedule = "Schedule"; var id: String { rawValue } }
    @State private var profile: TeamProfileData?
    @State private var schedule: [SportsEvent] = []
    @State private var section: Section = .overview
    @State private var loading = false
    @State private var error: String?
    private let three = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.05, green: 0.10, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    HStack(spacing: 12) { ForEach(Section.allCases) { item in Button(item.rawValue) { section = item }.buttonStyle(.borderedProminent).tint(section == item ? .blue : .gray.opacity(0.25)) }; Spacer() }
                    if loading && profile == nil { LoadingPanel(text: "Loading team profile…") }
                    else if let error, profile == nil { EmptyPanel(symbol: "wifi.exclamationmark", title: "Team profile unavailable", detail: error) }
                    else { sectionContent }
                }.padding(.horizontal, 62).padding(.vertical, 34)
            }
        }.navigationTitle(profile?.team.displayName ?? fallbackName).task { await load() }
    }

    private var hero: some View {
        HStack(spacing: 26) {
            RemoteImage(urlString: profile?.team.logo, fallback: "shield.fill", size: 112)
            VStack(alignment: .leading, spacing: 6) { Text(profile?.team.displayName ?? fallbackName).font(.system(size: 44, weight: .black, design: .rounded)); if let r = profile?.record { Text(r).font(.title2.bold()) }; if let s = profile?.standingSummary { Text(s).foregroundStyle(.secondary) } }
            Spacer(); if league.favoriteTeamAbbreviations.contains(profile?.team.abbreviation ?? "") { Label("COLORADO FAVORITE", systemImage: "star.fill").foregroundStyle(.yellow).font(.headline) }
        }.padding(26).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27))
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .overview: overview
        case .roster: roster
        case .schedule: scheduleView
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("TEAM PROFILE").font(.title2.bold())
            if let profile {
                LazyVGrid(columns: three, spacing: 14) { ForEach(profile.facts) { StatPill(label: $0.label, value: $0.value) } }
                HStack(spacing: 14) { ForEach(Array(profile.roster.prefix(3))) { group in StatPill(label: group.name, value: "\(group.athletes.count) players") } }
            }
        }.padding(.bottom, 50)
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ROSTER").font(.title2.bold())
            if let profile, !profile.roster.isEmpty {
                ForEach(profile.roster) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(group.name.uppercased()).font(.headline).foregroundStyle(.secondary)
                        LazyVGrid(columns: three, spacing: 12) {
                            ForEach(group.athletes) { athlete in NavigationLink { PlayerProfileView(league: league, fallbackAthlete: athlete) } label: { AthleteCard(athlete: athlete) }.buttonStyle(.plain) }
                        }
                    }
                }
            } else { EmptyPanel(symbol: "person.3", title: "Roster unavailable", detail: "No roster data was returned.") }
        }.padding(.bottom, 50)
    }

    private var scheduleView: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("TEAM SCHEDULE / GAME LOG").font(.title2.bold())
            if schedule.isEmpty { EmptyPanel(symbol: "calendar", title: "No schedule returned", detail: "Use the league Schedule screen or try again later.") }
            else { LazyVGrid(columns: three, spacing: 18) { ForEach(schedule) { GameCard(event: $0, league: league, favorite: league.favoriteTeamAbbreviations.contains(profile?.team.abbreviation ?? "")) } } }
        }.padding(.bottom, 50)
    }

    private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        do { profile = try await SportsService.fetchTeamProfile(for: league, teamID: teamID); schedule = (try? await SportsService.fetchTeamSchedule(for: league, teamID: teamID)) ?? [] }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}

private struct AthleteCard: View {
    let athlete: SportsAthlete
    var body: some View {
        HStack(spacing: 12) { RemoteImage(urlString: athlete.headshot, fallback: "person.crop.circle.fill", size: 58); VStack(alignment: .leading, spacing: 2) { Text(athlete.displayName).font(.headline).lineLimit(1); Text([athlete.position, athlete.jersey.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary); if let status = athlete.status { Text(status).font(.caption2).foregroundStyle(.secondary) } }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
            .padding(14).frame(maxWidth: .infinity, minHeight: 86).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct PlayerProfileView: View {
    let league: SportsLeague, fallbackAthlete: SportsAthlete
    @State private var profile: PlayerProfileData?
    @State private var loading = false
    @State private var error: String?
    private let four = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var athlete: SportsAthlete { profile?.athlete ?? fallbackAthlete }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.07, green: 0.08, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if loading && profile == nil { LoadingPanel(text: "Loading player profile…") }
                    else {
                        if let error { Text("Some player data could not load: \(error)").font(.caption).foregroundStyle(.orange) }
                        facts
                        stats
                        gameLog
                    }
                }.padding(.horizontal, 62).padding(.vertical, 34)
            }
        }.navigationTitle(athlete.displayName).task { await load() }
    }

    private var hero: some View {
        HStack(spacing: 26) { RemoteImage(urlString: athlete.headshot, fallback: "person.crop.circle.fill", size: 132); VStack(alignment: .leading, spacing: 6) { Text(athlete.displayName).font(.system(size: 46, weight: .black, design: .rounded)); Text([athlete.position, athlete.jersey.map { "#\($0)" }, profile?.teamName].compactMap { $0 }.joined(separator: " · ")).font(.title2).foregroundStyle(.secondary); if let status = athlete.status { Text(status.uppercased()).font(.caption.bold()).foregroundStyle(.green) } }; Spacer() }
            .padding(26).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27))
    }

    private var facts: some View {
        LazyVGrid(columns: four, spacing: 12) {
            if let age = athlete.age { StatPill(label: "Age", value: "\(age)") }
            if let height = athlete.height { StatPill(label: "Height", value: height) }
            if let weight = athlete.weight { StatPill(label: "Weight", value: weight) }
            if let exp = athlete.experience { StatPill(label: "Experience", value: exp) }
            if let debut = profile?.debutYear { StatPill(label: "Debut", value: "\(debut)") }
            if let birthplace = profile?.birthplace { StatPill(label: "Birthplace", value: birthplace) }
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SEASON SNAPSHOT").font(.title2.bold())
            if let profile, !profile.summaryStats.isEmpty { LazyVGrid(columns: four, spacing: 12) { ForEach(profile.summaryStats) { StatPill(label: $0.label, value: $0.value) } } }
            else { Text("No season snapshot returned for this player.").foregroundStyle(.secondary) }
        }
    }

    private var gameLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GAME LOG").font(.title2.bold())
            if let profile, !profile.gameLog.isEmpty {
                ForEach(profile.gameLog) { row in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { VStack(alignment: .leading) { Text(row.opponent).font(.headline); Text(row.date).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let result = row.result { Text(result).font(.headline) } }
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 9) { ForEach(Array(row.stats.prefix(10))) { StatPill(label: $0.label, value: $0.value).frame(width: 150) } } }
                    }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                }
            } else { Text("No game-log rows were returned for this player/sport yet.").foregroundStyle(.secondary) }
        }.padding(.bottom, 50)
    }

    private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        do { profile = try await SportsService.fetchPlayerProfile(for: league, athleteID: fallbackAthlete.id) }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}

private struct StatPill: View {
    let label: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary).lineLimit(1); Text(value).font(.title3.bold()).lineLimit(2) }.padding(15).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15)) }
}

private struct RemoteImage: View {
    let urlString: String?, fallback: String, size: CGFloat
    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: fallback).foregroundStyle(.secondary) } }
            else { Image(systemName: fallback).foregroundStyle(.secondary) }
        }.frame(width: size, height: size)
    }
}
