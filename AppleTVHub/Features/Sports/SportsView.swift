import SwiftUI

struct SportsView: View {
    let isActive: Bool

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

    private var events: [SportsEvent] {
        viewModel.eventsByLeague[selectedLeague] ?? []
    }

    private var visibleEvents: [SportsEvent] {
        let filtered: [SportsEvent]
        switch selectedFilter {
        case .all:
            filtered = events
        case .live:
            filtered = events.filter(\.isLive)
        case .upcoming:
            filtered = events.filter(\.isUpcoming)
        case .final:
            filtered = events.filter(\.isFinal)
        case .favorites:
            filtered = events.filter(isFavorite)
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
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.03, green: 0.08, blue: 0.16), Color(red: 0.07, green: 0.15, blue: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    leaguePicker

                    if let error = viewModel.errorByLeague[selectedLeague], !events.isEmpty {
                        staleDataBanner(error)
                    }

                    scoreboardSummary
                    filterPicker
                    content
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 38)
            }
        }
        .task(id: refreshTaskID) {
            guard scenePhase == .active, isActive else { return }

            if !viewModel.hasAnyData {
                await viewModel.refreshAll()
            }

            guard !Task.isCancelled, scenePhase == .active, isActive else { return }
            await adaptiveRefreshLoop(for: selectedLeague)
        }
    }

    private var refreshTaskID: String {
        "\(selectedLeague.rawValue)-\(scenePhase == .active ? "active" : "inactive")-\(isActive ? "visible" : "hidden")"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 34, weight: .bold))
                    Text("SPORTS CENTER")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                }
                Text("Live scores, schedules, networks, venues and Colorado teams")
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
                Task { await viewModel.refresh(selectedLeague, force: true) }
            } label: {
                if viewModel.loadingLeagues.contains(selectedLeague) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Refreshing")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
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
                        Text(league.rawValue)
                            .fontWeight(.bold)
                        if (viewModel.eventsByLeague[league] ?? []).contains(where: \.isLive) {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .frame(minWidth: 150)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedLeague == league ? .white : .gray.opacity(0.28))
                .foregroundStyle(selectedLeague == league ? .black : .white)
            }

            Spacer()

            Text("Favorite: \(favoriteTeamLabel)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
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

    private func summaryTile(title: String, value: String, symbol: String, accent: Color = .white) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var filterPicker: some View {
        HStack(spacing: 14) {
            Text("SHOW")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(SportsFilter.allCases) { filter in
                Button {
                    selectedFilterRaw = filter.rawValue
                } label: {
                    Label(filter.rawValue, systemImage: filter.symbol)
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .tint(selectedFilter == filter ? .white : .gray.opacity(0.25))
            }

            Spacer()

            Text("\(visibleEvents.count) shown")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isInitialLoading && viewModel.eventsByLeague.isEmpty {
            HStack(spacing: 18) {
                ProgressView()
                Text("Loading all scoreboards…")
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, minHeight: 400)
        } else if events.isEmpty {
            emptyState(
                symbol: "sportscourt",
                title: "No \(selectedLeague.rawValue) games on the current scoreboard",
                detail: viewModel.errorByLeague[selectedLeague]
            )
        } else if visibleEvents.isEmpty {
            emptyState(
                symbol: selectedFilter.symbol,
                title: "Nothing in \(selectedFilter.rawValue)",
                detail: "Try another filter to see the rest of the \(selectedLeague.rawValue) scoreboard."
            )
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 22) {
                ForEach(visibleEvents) { event in
                    GameCard(event: event, isFavorite: isFavorite(event))
                }
            }
            .padding(.bottom, 50)
        }
    }

    private func emptyState(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 70))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Refresh") {
                Task { await viewModel.refresh(selectedLeague, force: true) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func staleDataBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
            Text("Latest refresh failed. Showing the last successful scoreboard.")
                .fontWeight(.semibold)
            Spacer()
            Text(error)
                .lineLimit(1)
                .foregroundStyle(.secondary)
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

    private var favoriteTeamLabel: String {
        switch selectedLeague {
        case .nfl: return "Broncos"
        case .nba: return "Nuggets"
        case .nhl: return "Avalanche"
        case .mlb: return "Rockies"
        }
    }

    private func adaptiveRefreshLoop(for league: SportsLeague) async {
        while !Task.isCancelled {
            guard scenePhase == .active, isActive else { return }

            let interval = viewModel.recommendedRefreshInterval(for: league)
            let elapsed = viewModel.refreshReferenceDate(for: league).map {
                Date().timeIntervalSince($0)
            } ?? interval

            if elapsed >= interval {
                await viewModel.refresh(league, force: true)
            }

            guard !Task.isCancelled, scenePhase == .active, isActive else { return }

            let updatedInterval = viewModel.recommendedRefreshInterval(for: league)
            let updatedElapsed = viewModel.refreshReferenceDate(for: league).map {
                Date().timeIntervalSince($0)
            } ?? max(updatedInterval - 5, 0)
            let wait = max(5, updatedInterval - updatedElapsed)

            do {
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            } catch {
                return
            }
        }
    }
}

private struct GameCard: View {
    let event: SportsEvent
    let isFavorite: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                statusBadge
                if isFavorite {
                    Label("COLORADO", systemImage: "star.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                }
                Spacer()
                if let network = event.network {
                    Text(network)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            teamRow(event.awayTeam)
            Divider().opacity(0.28)
            teamRow(event.homeTeam)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                if let startDate = event.startDate, event.isUpcoming {
                    Label(startDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .lineLimit(1)
                }
                if let venue = event.venueText {
                    Label(venue, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 286, maxHeight: 286, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isFavorite ? Color.yellow.opacity(isFocused ? 0.85 : 0.35) : Color.white.opacity(isFocused ? 0.55 : 0.09),
                    lineWidth: isFocused ? 3 : 1
                )
        }
        .scaleEffect(isFocused ? 1.025 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.38 : 0), radius: 18, y: 8)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .focusable()
        .focused($isFocused)
        .zIndex(isFocused ? 1 : 0)
        .accessibilityLabel("\(event.awayTeam?.team.displayName ?? "Away team") versus \(event.homeTeam?.team.displayName ?? "Home team"), \(statusText)")
    }

    private var statusBadge: some View {
        HStack(spacing: 7) {
            if event.isLive {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
            }
            Text(statusText)
                .lineLimit(1)
        }
        .font(.caption.bold())
        .foregroundStyle(event.isLive ? Color.red : Color.primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background((event.isLive ? Color.red : Color.white).opacity(0.10), in: Capsule())
    }

    private func teamRow(_ competitor: Competitor?) -> some View {
        HStack(spacing: 14) {
            if let logoString = competitor?.team.logo, let logoURL = URL(string: logoString) {
                AsyncImage(url: logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "shield.fill").foregroundStyle(.secondary)
                }
                .frame(width: 52, height: 52)
            } else {
                Image(systemName: "shield.fill")
                    .font(.system(size: 34))
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(competitor?.team.displayName ?? "Team")
                    .font(.headline.bold())
                    .lineLimit(1)
                if let record = competitor?.record {
                    Text(record)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(competitor?.score ?? "–")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(competitor?.winner == true ? Color.green : Color.primary)
        }
    }

    private var statusText: String {
        if let detail = event.status.type.shortDetail, !detail.isEmpty {
            return detail
        }
        return event.status.type.description ?? "Scheduled"
    }
}
