import SwiftUI

struct ArcadeView: View {
    @AppStorage("arcade.pong.best") private var pongBest = 0
    @AppStorage("arcade.snake.best") private var snakeBest = 0
    @AppStorage("arcade.breakout.best") private var breakoutBest = 0
    @AppStorage("arcade.reaction.best") private var reactionBest = 0
    @AppStorage("arcade.memory.best") private var memoryBest = 0

    private let columns = [
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.12, green: 0.02, blue: 0.17), Color(red: 0.24, green: 0.04, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        statsStrip

                        Text("CHOOSE A GAME")
                            .font(.title2.bold())

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            gameCard(
                                title: "Pong",
                                subtitle: "Classic paddle survival",
                                control: "Left / Right",
                                best: "Best \(pongBest)",
                                symbol: "circle.grid.cross.fill",
                                destination: PongGameView()
                            )

                            gameCard(
                                title: "Snake",
                                subtitle: "Grow without hitting the wall",
                                control: "D-pad",
                                best: "Best \(snakeBest)",
                                symbol: "scribble.variable",
                                destination: SnakeGameView()
                            )

                            gameCard(
                                title: "Breakout",
                                subtitle: "Clear the brick wall",
                                control: "Left / Right",
                                best: "Best \(breakoutBest)",
                                symbol: "square.grid.3x3.fill",
                                destination: BreakoutGameView()
                            )

                            gameCard(
                                title: "Reaction Rush",
                                subtitle: "Wait for green, then click fast",
                                control: "Select",
                                best: reactionBest > 0 ? "Best \(reactionBest) ms" : "No score yet",
                                symbol: "bolt.fill",
                                destination: ReactionRushGameView()
                            )

                            gameCard(
                                title: "Memory Match",
                                subtitle: "Find all eight matching pairs",
                                control: "D-pad + Select",
                                best: memoryBest > 0 ? "Best \(memoryBest) moves" : "No score yet",
                                symbol: "square.grid.4x3.fill",
                                destination: MemoryMatchGameView()
                            )
                        }

                        HStack(spacing: 14) {
                            Image(systemName: "info.circle.fill")
                            Text("Pong, Snake and Breakout support Play/Pause. Menu/Back returns here. All scores stay on this Apple TV.")
                        }
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .padding(.bottom, 48)
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 38)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 36, weight: .bold))
                    Text("APPLE TV ARCADE")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                }
                Text("Five native tvOS games built for the Siri Remote")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("OFFLINE READY", systemImage: "wifi.slash")
                .font(.caption.bold())
                .foregroundStyle(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.green.opacity(0.12), in: Capsule())
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 18) {
            stat(title: "Games", value: "5", symbol: "gamecontroller.fill")
            stat(title: "Internet Needed", value: "No", symbol: "wifi.slash")
            stat(title: "Local Bests", value: "Saved", symbol: "trophy.fill")
            stat(title: "Controller", value: "Siri Remote", symbol: "appletvremote.gen4.fill")
        }
    }

    private func stat(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .bold))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func gameCard<Destination: View>(
        title: String,
        subtitle: String,
        control: String,
        best: String,
        symbol: String,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 54))
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    Text("PLAY")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.10), in: Capsule())
                }

                Spacer()

                Text(title)
                    .font(.system(size: 30, weight: .black, design: .rounded))

                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Label(control, systemImage: "cursorarrow.click.2")
                    Spacer()
                    Label(best, systemImage: "trophy.fill")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reaction Rush

private struct ReactionRushGameView: View {
    private enum Phase {
        case idle
        case waiting
        case go
        case result
    }

    @State private var phase: Phase = .idle
    @State private var message = "Press Start, then wait for green."
    @State private var startedAt: Date?
    @State private var roundID = UUID()
    @AppStorage("arcade.reaction.best") private var best = 0

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 34) {
                HStack {
                    Text("REACTION RUSH")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                    Spacer()
                    Text(best > 0 ? "Best \(best) ms" : "No best yet")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: phase == .go ? "bolt.fill" : "hand.tap.fill")
                    .font(.system(size: 130, weight: .black))
                    .foregroundStyle(phase == .go ? Color.green : Color.white)

                Text(message)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Button(action: handlePress) {
                    Text(buttonTitle)
                        .font(.title.bold())
                        .frame(minWidth: 330)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(phase == .go ? .green : .white)
                .foregroundStyle(phase == .go ? .black : .black)

                Spacer()

                Text("Goal: the lowest reaction time wins. Clicking before green counts as a false start.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(60)
        }
        .navigationTitle("Reaction Rush")
    }

    private var backgroundColor: Color {
        switch phase {
        case .go: return Color.green.opacity(0.20)
        case .waiting: return Color.red.opacity(0.14)
        default: return Color.black
        }
    }

    private var buttonTitle: String {
        switch phase {
        case .idle, .result: return "START ROUND"
        case .waiting: return "WAIT…"
        case .go: return "TAP NOW!"
        }
    }

    private func handlePress() {
        switch phase {
        case .idle, .result:
            startRound()
        case .waiting:
            roundID = UUID()
            phase = .result
            message = "Too soon! False start."
        case .go:
            guard let startedAt else { return }
            let milliseconds = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            if best == 0 || milliseconds < best {
                best = milliseconds
                message = "\(milliseconds) ms — NEW BEST!"
            } else {
                message = "\(milliseconds) ms"
            }
            phase = .result
        }
    }

    private func startRound() {
        let id = UUID()
        roundID = id
        phase = .waiting
        startedAt = nil
        message = "Wait for green…"

        let delay = Double.random(in: 1.8...4.2)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, roundID == id, phase == .waiting else { return }
            startedAt = Date()
            phase = .go
            message = "GO!"
        }
    }
}

// MARK: - Memory Match

private struct MemoryMatchGameView: View {
    private let symbols = ["🏈", "🏀", "🏒", "⚾️", "🎮", "⭐️", "🔥", "🏆"]

    @State private var deck: [Int] = []
    @State private var revealed: Set<Int> = []
    @State private var matched: Set<Int> = []
    @State private var selections: [Int] = []
    @State private var moves = 0
    @State private var locked = false
    @AppStorage("arcade.memory.best") private var best = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 4)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.10, blue: 0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text("MEMORY MATCH")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                    Spacer()
                    Text("Moves \(moves)")
                        .font(.title2.bold())
                    Text(best > 0 ? "Best \(best)" : "Best —")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Button("New Game") { newGame() }
                }

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(deck.indices, id: \.self) { index in
                        Button {
                            flip(index)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(cardFill(index))
                                Text(cardText(index))
                                    .font(.system(size: 54))
                            }
                            .frame(height: 145)
                        }
                        .buttonStyle(.plain)
                        .disabled(locked || matched.contains(index))
                    }
                }

                if !deck.isEmpty && matched.count == deck.count {
                    HStack(spacing: 14) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                        Text("Board cleared in \(moves) moves!")
                            .font(.title2.bold())
                    }
                } else {
                    Text("Use the D-pad to choose a card and Select to flip it. Match all eight pairs.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(55)
        }
        .onAppear {
            if deck.isEmpty { newGame() }
        }
        .navigationTitle("Memory Match")
    }

    private func cardText(_ index: Int) -> String {
        guard deck.indices.contains(index) else { return "" }
        if revealed.contains(index) || matched.contains(index) {
            return symbols[deck[index]]
        }
        return "?"
    }

    private func cardFill(_ index: Int) -> Color {
        if matched.contains(index) { return .green.opacity(0.28) }
        if revealed.contains(index) { return .white.opacity(0.20) }
        return .white.opacity(0.08)
    }

    private func flip(_ index: Int) {
        guard !locked,
              deck.indices.contains(index),
              !matched.contains(index),
              !revealed.contains(index),
              selections.count < 2 else { return }

        revealed.insert(index)
        selections.append(index)

        guard selections.count == 2 else { return }
        moves += 1
        let first = selections[0]
        let second = selections[1]

        if deck[first] == deck[second] {
            matched.insert(first)
            matched.insert(second)
            selections.removeAll()

            if matched.count == deck.count, best == 0 || moves < best {
                best = moves
            }
        } else {
            locked = true
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run {
                    revealed.remove(first)
                    revealed.remove(second)
                    selections.removeAll()
                    locked = false
                }
            }
        }
    }

    private func newGame() {
        deck = (Array(0..<symbols.count) + Array(0..<symbols.count)).shuffled()
        revealed.removeAll()
        matched.removeAll()
        selections.removeAll()
        moves = 0
        locked = false
    }
}
