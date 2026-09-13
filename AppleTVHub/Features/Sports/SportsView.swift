import SwiftUI

struct SportsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = SportsViewModel()
    @AppStorage("sports.selectedLeague") private var selectedLeagueRaw = SportsLeague.nfl.rawValue

    private var selectedLeague: SportsLeague {
        SportsLeague(rawValue: selectedLeagueRaw) ?? .nfl
    }

    private var events: [SportsEvent] {
        viewModel.eventsByLeague[selectedLeague] ?? []
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.10, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                header
                leaguePicker

                if let error = viewModel.errorByLeague[selectedLeague], !events.isEmpty {
                    staleDataBanner(error)
                }

                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 70)
            .padding(.vertical, 45)
        }
        .task {
            if !viewModel.hasAnyData {
                await viewModel.refreshAll()
            }
        }
        .task(id: refreshTaskID) {
            guard scenePhase == .active else { return }
            await adaptiveRefreshLoop(for: selectedLeague)
        }
    }

    private var refreshTaskID: String {
        "\(selectedLeague.rawValue)-\(scenePhase == .active ? "active" : "inactive")"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SPORTS")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                Text("Live scores across NFL, NBA, NHL and MLB")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(viewModel.refreshDescription(for: selectedLeague))
                    .font(.caption.bold())
                    .foregroundStyle(events.contains(where: \.isLive) ? .red : .secondary)

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
        HStack(spacing: 18) {
            ForEach(SportsLeague.allCases) { league in
                Button {
                    selectedLeagueRaw = league.rawValue
                } label: {
                    HStack(spacing: 12) {
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
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedLeague == league ? .white : .gray.opacity(0.35))
                .foregroundStyle(selectedLeague == league ? .black : .white)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isInitialLoading && viewModel.eventsByLeague.isEmpty {
            HStack(spacing: 18) {
                ProgressView()
                Text("Loading scoreboards…")
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if events.isEmpty {
            VStack(spacing: 18) {
                Image(systemName: "sportscourt")
                    .font(.system(size: 70))
                    .foregroundStyle(.secondary)
                Text("No \(selectedLeague.rawValue) games on the current scoreboard")
                    .font(.title2)
                if let error = viewModel.errorByLeague[selectedLeague] {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await viewModel.refresh(selectedLeague, force: true) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(events) { event in
                        GameCard(event: event)
                    }
                }
                .padding(.vertical, 18)
            }
        }
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

    private func adaptiveRefreshLoop(for league: SportsLeague) async {
        while !Task.isCancelled {
            guard scenePhase == .active else { return }

            let interval = viewModel.recommendedRefreshInterval(for: league)
            let elapsed = viewModel.lastUpdatedByLeague[league].map {
                Date().timeIntervalSince($0)
            } ?? interval

            if elapsed >= interval {
                await viewModel.refresh(league, force: true)
            }

            let updatedInterval = viewModel.recommendedRefreshInterval(for: league)
            let updatedElapsed = viewModel.lastUpdatedByLeague[league].map {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(event.isLive ? .red : .secondary)
                Spacer()
                if event.isLive {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 12, height: 12)
                        Text("LIVE")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }
            }

            teamRow(event.awayTeam)
            Divider().opacity(0.35)
            teamRow(event.homeTeam)

            Spacer(minLength: 0)

            Text(event.shortName ?? event.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(28)
        .frame(width: 440, height: 330)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func teamRow(_ competitor: Competitor?) -> some View {
        HStack(spacing: 18) {
            if let logoString = competitor?.team.logo, let logoURL = URL(string: logoString) {
                AsyncImage(url: logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "shield.fill").foregroundStyle(.secondary)
                }
                .frame(width: 62, height: 62)
            } else {
                Image(systemName: "shield.fill")
                    .font(.system(size: 42))
                    .frame(width: 62, height: 62)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(competitor?.team.displayName ?? "Team")
                    .font(.title3.bold())
                    .lineLimit(1)
                if let record = competitor?.record {
                    Text(record)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(competitor?.score ?? "–")
                .font(.system(size: 42, weight: .black, design: .rounded))
        }
    }

    private var statusText: String {
        if let detail = event.status.type.shortDetail, !detail.isEmpty {
            return detail
        }
        return event.status.type.description ?? "Scheduled"
    }
}
