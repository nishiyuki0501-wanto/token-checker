import SwiftUI

struct ProgressBarView: View {
    let value: Double   // 0.0〜1.0
    var height: CGFloat = 6
    @AppStorage(CatCharacter.storageKey) private var cat: CatCharacter = .default

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.18))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * clamped)
                    .opacity(0.12)
                PawTrailBar(
                    value: clamped,
                    width: geo.size.width,
                    height: geo.size.height,
                    color: color
                )
                if clamped > 0.02 {
                    // 先頭を歩くのはユーザーが選んだ看板猫
                    CatMascot(character: cat, size: max(18, height + 12), mood: CatMood(utilization: value), tint: color)
                        .position(x: markerX(in: geo.size.width), y: geo.size.height / 2)
                }
            }
        }
        .frame(height: max(height, 14))
    }

    private var clamped: Double { min(max(value, 0), 1) }
    private func markerX(in width: CGFloat) -> CGFloat {
        let halfCat = max(18, height + 12) / 2
        return min(max(width * clamped, halfCat), width - halfCat)
    }

    private var color: Color {
        if value < 0.7 { return .green }
        if value < 0.85 { return .orange }
        return .red
    }
}

private struct PawTrailBar: View {
    let value: Double
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<pawCount, id: \.self) { index in
                Image(systemName: "pawprint.fill")
                    .font(.system(size: max(8, height + 2), weight: .bold))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -10 : 10))
                    .position(x: xPosition(for: index), y: height / 2)
            }
        }
    }

    private var pawCount: Int {
        guard value > 0.03, width > 0 else { return 0 }
        let availableWidth = max(0, width * value - catReserve)
        return max(1, Int(availableWidth / spacing))
    }

    private func xPosition(for index: Int) -> CGFloat {
        let x = (CGFloat(index) + 0.5) * spacing
        let maxX = max(height / 2, width * value - catReserve)
        return min(max(x, height / 2), maxX)
    }

    private var spacing: CGFloat {
        max(20, height * 2.9)
    }

    private var catReserve: CGFloat {
        max(18, height + 12) * 0.92
    }
}
