import SwiftUI
import Combine

struct PongGameView: View {
    @State private var ball = CGPoint(x: 500, y: 250)
    @State private var velocity = CGVector(dx: 7, dy: 7)
    @State private var paddleX: CGFloat = 500
    @State private var score = 0
    @State private var best = 0
    @State private var isPaused = false

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let paddleWidth: CGFloat = 180
    private let paddleHeight: CGFloat = 24
    private let ballSize: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    HStack {
                        Text("PONG")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                        Spacer()
                        Text("Score \(score)")
                            .font(.title2.bold())
                        Text("Best \(best)")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 55)
                    .padding(.top, 25)
                    Spacer()
                }

                Rectangle()
                    .fill(.white)
                    .frame(width: paddleWidth, height: paddleHeight)
                    .clipShape(Capsule())
                    .position(x: paddleX, y: max(100, size.height - 70))

                Circle()
                    .fill(.white)
                    .frame(width: ballSize, height: ballSize)
                    .position(ball)

                if isPaused {
                    pauseOverlay(title: "PAUSED")
                }
            }
            .focusable(true)
            .onAppear {
                reset(in: size, keepScore: true)
            }
            .onMoveCommand { direction in
                switch direction {
                case .left:
                    paddleX = max(paddleWidth / 2, paddleX - 70)
                case .right:
                    paddleX = min(size.width - paddleWidth / 2, paddleX + 70)
                default:
                    break
                }
            }
            .onPlayPauseCommand {
                isPaused.toggle()
            }
            .onReceive(timer) { _ in
                guard !isPaused else { return }
                tick(in: size)
            }
        }
        .navigationTitle("Pong")
    }

    private func tick(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        var next = CGPoint(x: ball.x + velocity.dx, y: ball.y + velocity.dy)
        let radius = ballSize / 2

        if next.x <= radius || next.x >= size.width - radius {
            velocity.dx *= -1
            next.x = min(max(next.x, radius), size.width - radius)
        }

        if next.y <= 80 + radius {
            velocity.dy = abs(velocity.dy)
            next.y = 80 + radius
        }

        let paddleY = max(100, size.height - 70)
        let horizontalHit = abs(next.x - paddleX) <= paddleWidth / 2 + radius
        let verticalHit = next.y + radius >= paddleY - paddleHeight / 2 &&
            next.y - radius <= paddleY + paddleHeight / 2

        if velocity.dy > 0 && horizontalHit && verticalHit {
            velocity.dy = -abs(velocity.dy) * 1.015
            let english = (next.x - paddleX) / (paddleWidth / 2)
            velocity.dx += english * 1.6
            score += 1
            best = max(best, score)
            next.y = paddleY - paddleHeight / 2 - radius - 1
        }

        if next.y > size.height + radius {
            score = 0
            reset(in: size, keepScore: true)
            return
        }

        ball = next
    }

    private func reset(in size: CGSize, keepScore: Bool) {
        if !keepScore { score = 0 }
        paddleX = size.width / 2
        ball = CGPoint(x: size.width / 2, y: max(180, size.height * 0.35))
        velocity = CGVector(dx: Bool.random() ? 7 : -7, dy: 7)
    }

    private func pauseOverlay(title: String) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 58, weight: .black, design: .rounded))
            Text("Press Play/Pause to continue")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}
