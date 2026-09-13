import SwiftUI

struct SportsView: View {
    @StateObject private var viewModel = SportsViewModel()
    @State private var selectedLeague: SportsLeague = .nfl

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

            VStack(alignment: .leading, spacing: 30) {
                header
                leaguePicker
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 70)
            .padding(.vertical, 45)
        }
        .task {
            if viewModel.lastUpdated == nil {
                await viewModel.refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SPORTS")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                Text("Live scores across NFL, NBA, NHL and MLB")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let updated = viewModel.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var leaguePicker: some View {
        HStack(spacing: 18) {
            ForEach(SportsLeague.allCases) { league in
                Button {
                    selectedLeague = league
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: league.symbol)
                        Text(league.rawValue)
                            .fontWeight(.bold)
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
        if viewModel.isLoading && viewModel.eventsByLeague.isEmpty {
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
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
}

private struct GameCard: View {
    let event: SportsEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(isLive ? .red : .secondary)
                Spacer()
                if isLive {
                    Circle()
                        .fill(.red)
                        .frame(width: 12, height: 12)
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

    private var isLive: Bool {
        event.status.type.state == "in"
    }

    private var statusText: String {
        if let detail = event.status.type.shortDetail, !detail.isEmpty {
            return detail
        }
        return event.status.type.description ?? "Scheduled"
    }
}
