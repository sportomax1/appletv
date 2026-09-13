import SwiftUI
import Combine

struct BreakoutGameView: View {
    private struct Brick: Identifiable, Hashable {
        let id = UUID()
        let row: Int
        let column: Int
    }

    @State private var ball = CGPoint(x: 500, y: 500)
    @State private var velocity = CGVector(dx: 6, dy: -7)
    @State private var paddleX: CGFloat = 500
    @State private var bricks: [Brick] = BreakoutGameView.makeBricks()
    @State private var score = 0
    @AppStorage("arcade.breakout.best") private var best = 0
    @State private var lives = 3
    @State private var isPaused = false
    @State private var lastTickAt: Date?
    @FocusState private var restartFocused: Bool

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let paddleWidth: CGFloat = 190
    private let paddleHeight: CGFloat = 24
    private let ballSize: CGFloat = 24
    private let brickColumns = 10

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    HStack {
                        Text("BREAKOUT")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                        Spacer()
                        Text("Score \(score)")
                            .font(.title2.bold())
                        Text("Best \(best)")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Lives \(lives)")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 55)
                    .padding(.top, 25)
                    Spacer()
                }

                Canvas { context, canvasSize in
                    let layout = brickLayout(in: canvasSize)
                    for brick in bricks {
                        let rect = brickRect(brick, layout: layout).insetBy(dx: 4, dy: 4)
                        let color: Color = [.red, .orange, .yellow, .green, .blue][brick.row % 5]
                        context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(color))
                    }
                }

                Rectangle()
                    .fill(.white)
                    .frame(width: paddleWidth, height: paddleHeight)
                    .clipShape(Capsule())
                    .position(x: paddleX, y: max(120, size.height - 70))

                Circle()
                    .fill(.white)
                    .frame(width: ballSize, height: ballSize)
                    .position(ball)

                if isPaused {
                    pauseOverlay
                } else if lives <= 0 || bricks.isEmpty {
                    endOverlay(in: size)
                }
            }
            .focusable(lives > 0 && !bricks.isEmpty)
            .onAppear {
                resetBall(in: size)
            }
            .onMoveCommand { direction in
                guard lives > 0, !bricks.isEmpty, !isPaused else { return }
                switch direction {
                case .left:
                    paddleX = max(paddleWidth / 2, paddleX - 75)
                case .right:
                    paddleX = min(size.width - paddleWidth / 2, paddleX + 75)
                default:
                    break
                }
            }
            .onPlayPauseCommand {
                guard lives > 0, !bricks.isEmpty else { return }
                isPaused.toggle()
                lastTickAt = nil
            }
            .onReceive(timer) { now in
                guard !isPaused, lives > 0, !bricks.isEmpty else { return }
                tick(in: size, now: now)
            }
            .onChange(of: lives) { newValue in
                if newValue <= 0 {
                    restartFocused = true
                }
            }
            .onChange(of: bricks.isEmpty) { isEmpty in
                if isEmpty {
                    restartFocused = true
                }
            }
        }
        .navigationTitle("Breakout")
    }

    private func tick(in size: CGSize, now: Date) {
        guard size.width > 0, size.height > 0 else { return }
        guard let previousTick = lastTickAt else {
            lastTickAt = now
            return
        }

        let delta = min(max(now.timeIntervalSince(previousTick), 1.0 / 120.0), 1.0 / 30.0)
        lastTickAt = now
        let frameScale = CGFloat(delta * 60)

        let previousBall = ball
        let radius = ballSize / 2
        var next = CGPoint(
            x: ball.x + velocity.dx * frameScale,
            y: ball.y + velocity.dy * frameScale
        )

        if next.x <= radius || next.x >= size.width - radius {
            velocity.dx *= -1
            next.x = min(max(next.x, radius), size.width - radius)
        }

        if next.y <= 80 + radius {
            velocity.dy = abs(velocity.dy)
            next.y = 80 + radius
        }

        let paddleY = max(120, size.height - 70)
        let paddleHit = velocity.dy > 0 &&
            abs(next.x - paddleX) <= paddleWidth / 2 + radius &&
            next.y + radius >= paddleY - paddleHeight / 2 &&
            next.y - radius <= paddleY + paddleHeight / 2

        if paddleHit {
            velocity.dy = -abs(velocity.dy)
            velocity.dx = min(max(
                velocity.dx + ((next.x - paddleX) / (paddleWidth / 2)) * 1.4,
                -13
            ), 13)
            next.y = paddleY - paddleHeight / 2 - radius - 1
        }

        let layout = brickLayout(in: size)
        if let hit = bricks.first(where: {
            brickRect($0, layout: layout).insetBy(dx: -radius, dy: -radius).contains(next)
        }) {
            let rect = brickRect(hit, layout: layout)
            bricks.removeAll { $0.id == hit.id }
            score += 10
            best = max(best, score)

            let cameFromVertical = previousBall.y + radius <= rect.minY ||
                previousBall.y - radius >= rect.maxY
            if cameFromVertical {
                velocity.dy *= -1
            } else {
                velocity.dx *= -1
            }
        }

        if next.y > size.height + radius {
            lives -= 1
            best = max(best, score)
            if lives > 0 {
                resetBall(in: size)
            } else {
                lastTickAt = nil
            }
            return
        }

        if bricks.isEmpty {
            best = max(best, score)
            lastTickAt = nil
        }

        ball = next
    }

    private func resetBall(in size: CGSize) {
        paddleX = size.width / 2
        ball = CGPoint(x: size.width / 2, y: max(300, size.height * 0.62))
        velocity = CGVector(dx: Bool.random() ? 6 : -6, dy: -7)
        lastTickAt = nil
    }

    private func restart(in size: CGSize) {
        bricks = Self.makeBricks()
        score = 0
        lives = 3
        isPaused = false
        restartFocused = false
        resetBall(in: size)
    }

    private static func makeBricks() -> [Brick] {
        (0..<5).flatMap { row in
            (0..<10).map { Brick(row: row, column: $0) }
        }
    }

    private func brickLayout(in size: CGSize) -> (originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat, gap: CGFloat) {
        let gap: CGFloat = 8
        let totalWidth = min(size.width - 150, 1450)
        let brickWidth = (totalWidth - gap * CGFloat(brickColumns - 1)) / CGFloat(brickColumns)
        let originX = (size.width - totalWidth) / 2
        return (originX, 150, brickWidth, 54, gap)
    }

    private func brickRect(_ brick: Brick, layout: (originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat, gap: CGFloat)) -> CGRect {
        CGRect(
            x: layout.originX + CGFloat(brick.column) * (layout.width + layout.gap),
            y: layout.originY + CGFloat(brick.row) * (layout.height + layout.gap),
            width: layout.width,
            height: layout.height
        )
    }

    private var pauseOverlay: some View {
        VStack(spacing: 14) {
            Text("PAUSED")
                .font(.system(size: 58, weight: .black, design: .rounded))
            Text("Press Play/Pause to continue")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private func endOverlay(in size: CGSize) -> some View {
        VStack(spacing: 18) {
            Text(bricks.isEmpty ? "YOU WIN" : "GAME OVER")
                .font(.system(size: 58, weight: .black, design: .rounded))
            Text("Score \(score) · Best \(best)")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Play Again") {
                restart(in: size)
            }
            .buttonStyle(.borderedProminent)
            .focused($restartFocused)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}
