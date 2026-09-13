import SwiftUI

struct ArcadeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.18, green: 0.04, blue: 0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 34) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARCADE")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                        Text("Siri Remote games built directly for tvOS")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 30) {
                        gameCard(
                            title: "Pong",
                            subtitle: "Move the paddle with Left / Right",
                            symbol: "circle.grid.cross.fill",
                            destination: PongGameView()
                        )

                        gameCard(
                            title: "Snake",
                            subtitle: "Guide the snake with the D-pad",
                            symbol: "scribble.variable",
                            destination: SnakeGameView()
                        )

                        gameCard(
                            title: "Breakout",
                            subtitle: "Bounce the ball and clear the wall",
                            symbol: "square.grid.3x3.fill",
                            destination: BreakoutGameView()
                        )
                    }

                    Text("Tip: Play/Pause pauses or resumes each game. Menu/Back returns to the arcade.")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 45)
            }
        }
    }

    private func gameCard<Destination: View>(
        title: String,
        subtitle: String,
        symbol: String,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 70))
                    .symbolRenderingMode(.hierarchical)

                Spacer()

                Text(title)
                    .font(.system(size: 34, weight: .black, design: .rounded))

                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(30)
            .frame(width: 450, height: 330, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
