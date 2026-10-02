import SwiftUI

struct PuyoDropView: View {
    @StateObject private var game = GameStore()
    private let timer = Timer.publish(every: 0.58, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            gameBackground

            VStack(spacing: 14) {
                topBar

                HStack(alignment: .top, spacing: 20) {
                    BoardView(game: game)
                        .frame(width: 330, height: 660)

                    sidePanel
                        .frame(width: 230)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 660, idealWidth: 720, minHeight: 760, idealHeight: 800)
        .background(KeyboardCaptureView { command in
            game.handle(command)
        })
        .onReceive(timer) { _ in
            game.tick()
        }
    }

    private var gameBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.11),
                Color(red: 0.19, green: 0.13, blue: 0.18),
                Color(red: 0.09, green: 0.18, blue: 0.16),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PuyoDrop")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("4つ以上つなげて消す落ちものパズル")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            Button {
                game.handle(.pause)
            } label: {
                Image(systemName: game.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(GameIconButtonStyle())
            .help(game.isPaused ? "再開" : "一時停止")

            Button {
                game.handle(.restart)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(GameIconButtonStyle())
            .help("リスタート")
        }
    }

    private var sidePanel: some View {
        VStack(spacing: 14) {
            statsPanel
            nextPanel
            controlsPanel
            statusPanel
        }
    }

    private var statsPanel: some View {
        VStack(spacing: 10) {
            StatRow(title: "SCORE", value: "\(game.score)")
            StatRow(title: "CHAIN", value: "\(game.chains)")
            StatRow(title: "BEST", value: "\(game.bestChain)")
            StatRow(title: "POPPED", value: "\(game.poppedTotal)")
        }
        .padding(14)
        .background(PanelBackground())
    }

    private var nextPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEXT")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 12) {
                BlobView(color: game.nextPair.0, isGhost: false)
                    .frame(width: 54, height: 54)
                BlobView(color: game.nextPair.1, isGhost: false)
                    .frame(width: 54, height: 54)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(PanelBackground())
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("KEYS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))

            ControlHint(icon: "arrow.left.and.right", text: "移動")
            ControlHint(icon: "arrow.down", text: "落下")
            ControlHint(icon: "rotate.right", text: "回転")
            ControlHint(icon: "return", text: "一気に落とす")
            ControlHint(icon: "pause.fill", text: "Pで一時停止")
        }
        .padding(14)
        .background(PanelBackground())
    }

    @ViewBuilder
    private var statusPanel: some View {
        if game.isGameOver {
            VStack(spacing: 12) {
                Text("GAME OVER")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.52, blue: 0.42))

                Button {
                    game.handle(.restart)
                } label: {
                    Label("もう一回", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.72, blue: 0.42))
            }
            .padding(14)
            .background(PanelBackground())
        } else if game.isPaused {
            Text("PAUSED")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.98, green: 0.79, blue: 0.20))
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(PanelBackground())
        }
    }
}

private struct BoardView: View {
    @ObservedObject var game: GameStore

    var body: some View {
        GeometryReader { proxy in
            let cellSpacing: CGFloat = 5
            let cellSize = min(
                (proxy.size.width - cellSpacing * CGFloat(GameStore.width - 1)) / CGFloat(GameStore.width),
                (proxy.size.height - cellSpacing * CGFloat(GameStore.height - 1)) / CGFloat(GameStore.height)
            )
            let ghostCells = game.ghostCells()

            VStack(spacing: cellSpacing) {
                ForEach(0..<GameStore.height, id: \.self) { row in
                    HStack(spacing: cellSpacing) {
                        ForEach(0..<GameStore.width, id: \.self) { column in
                            let point = GridPoint(row: row, column: column)
                            CellSlotView(
                                color: game.colorAt(row: row, column: column),
                                showsGhost: ghostCells.contains(point) && game.colorAt(row: row, column: column) == nil
                            )
                            .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.04, green: 0.05, blue: 0.05).opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
            )
        }
        .aspectRatio(CGFloat(GameStore.width) / CGFloat(GameStore.height), contentMode: .fit)
    }
}

private struct CellSlotView: View {
    let color: BlobColor?
    let showsGhost: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.055), lineWidth: 1)
                )

            if showsGhost {
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 3)
                    .padding(8)
            }

            if let color {
                BlobView(color: color, isGhost: false)
                    .padding(3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.18, dampingFraction: 0.78), value: color?.rawValue)
    }
}

private struct BlobView: View {
    let color: BlobColor
    let isGhost: Bool

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .white.opacity(isGhost ? 0.28 : 0.62),
                        color.baseColor.opacity(isGhost ? 0.35 : 1.0),
                        color.baseColor.opacity(isGhost ? 0.18 : 0.72),
                    ],
                    center: .topLeading,
                    startRadius: 2,
                    endRadius: 45
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(isGhost ? 0.25 : 0.48))
                    .frame(width: 12, height: 12)
                    .padding(12)
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(isGhost ? 0.15 : 0.32), lineWidth: 2)
            }
            .shadow(color: color.baseColor.opacity(isGhost ? 0 : 0.42), radius: 7, y: 3)
            .accessibilityLabel(color.displayName)
    }
}

private struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.65)
        }
    }
}

private struct ControlHint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.12))
                )

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct PanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct GameIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? .white.opacity(0.24) : .white.opacity(0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
    }
}
