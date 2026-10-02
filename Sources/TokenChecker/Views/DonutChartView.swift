import SwiftUI
import AppKit

/// 5h usage 1 本ぶんの円形プログレス。CCMeter の二重ドーナツから内側 7d を削除した版。
///
/// 中央にどのサービスかを示す SF Symbol を表示する（メニューバーで Claude / Codex を一目で区別）。
/// ドーナツ中央に何を描くかを表すモード。
enum DonutCenter {
    case none
    case sfSymbol(String, scale: CGFloat = 0.48)
    case paw(scale: CGFloat = 0.54)
    case catFace(scale: CGFloat = 0.62)
    case text(String, scale: CGFloat = 0.48)
}

struct DonutChartView: View {
    let value: Double   // 0.0 〜 1.0
    var size: CGFloat = 18
    var lineWidth: CGFloat = 4
    var center: DonutCenter = .none

    var body: some View {
        ZStack {
            // 背景のリング（未使用部分）
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: lineWidth)
                .frame(width: size - lineWidth, height: size - lineWidth)

            PawTrailArc(value: clamped, size: size, lineWidth: lineWidth, color: color)

            if clamped > 0.015 {
                CatSilhouetteIcon(size: max(11, size * 0.62), color: .white)
                    .offset(markerOffset)
            }

            centerContent
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var centerContent: some View {
        switch center {
        case .none:
            EmptyView()
        case .sfSymbol(let name, let scale):
            Image(systemName: name)
                .font(.system(size: size * scale, weight: .semibold))
                .foregroundStyle(.primary)
        case .paw(let scale):
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * scale, weight: .semibold))
                .foregroundStyle(.primary)
                .shadow(color: Color.primary.opacity(0.12), radius: 1.2)
        case .catFace(let scale):
            CatSilhouetteIcon(size: size * scale, color: .primary)
        case .text(let str, let scale):
            Text(str)
                .font(.system(size: size * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var clamped: Double { min(max(value, 0), 1) }
    private var markerOffset: CGSize {
        let angle = (-90 + clamped * 360) * .pi / 180
        let radius = (size - lineWidth) / 2
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    private var color: Color {
        if value < 0.7 { return .green }
        if value < 0.85 { return .orange }
        return .red
    }
}

private struct PawTrailArc: View {
    let value: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<pawCount, id: \.self) { index in
                Image(systemName: "pawprint.fill")
                    .font(.system(size: pawSize, weight: .bold))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(angle(for: index) + 90))
                    .offset(offset(for: index))
            }
        }
        .frame(width: size, height: size)
    }

    private var pawCount: Int {
        guard value > 0 else { return 0 }
        return min(13, max(1, Int((value * 12).rounded(.up))))
    }

    private var pawSize: CGFloat {
        max(4.5, lineWidth * 1.55)
    }

    private func angle(for index: Int) -> Double {
        let step = (Double(index) + 0.45) / Double(pawCount)
        return -90 + min(value * step, max(0, value - 0.02)) * 360
    }

    private func offset(for index: Int) -> CGSize {
        let radians = angle(for: index) * .pi / 180
        let radius = (size - lineWidth) / 2
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius)
    }
}

struct CatSilhouetteIcon: View {
    let size: CGFloat
    var color: Color = .white

    var body: some View {
        if let image = catImage {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.18), radius: 1.2, y: 0.6)
        } else {
            LeapingCatShape()
                .fill(color)
                .aspectRatio(1.72, contentMode: .fit)
                .frame(width: size * 1.72, height: size)
                .shadow(color: Color.black.opacity(0.22), radius: 1.2, y: 0.5)
        }
    }

    private var catImage: NSImage? {
        if let url = Bundle.main.url(forResource: "LeapingCat", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: "LeapingCat")
    }
}

struct LeapingCatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.07, y: h * 0.42))
        path.addQuadCurve(to: CGPoint(x: w * 0.24, y: h * 0.45), control: CGPoint(x: w * 0.14, y: h * 0.34))
        path.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.53), control: CGPoint(x: w * 0.29, y: h * 0.50))
        path.addQuadCurve(to: CGPoint(x: w * 0.57, y: h * 0.45), control: CGPoint(x: w * 0.45, y: h * 0.33))
        path.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.40), control: CGPoint(x: w * 0.64, y: h * 0.39))
        path.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.30), control: CGPoint(x: w * 0.77, y: h * 0.29))
        path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.17))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.31))
        path.addQuadCurve(to: CGPoint(x: w * 0.96, y: h * 0.34), control: CGPoint(x: w * 0.93, y: h * 0.29))
        path.addQuadCurve(to: CGPoint(x: w * 0.91, y: h * 0.44), control: CGPoint(x: w * 0.95, y: h * 0.42))
        path.addQuadCurve(to: CGPoint(x: w * 0.81, y: h * 0.45), control: CGPoint(x: w * 0.86, y: h * 0.47))
        path.addQuadCurve(to: CGPoint(x: w * 0.70, y: h * 0.53), control: CGPoint(x: w * 0.75, y: h * 0.49))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.70))
        path.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.76), control: CGPoint(x: w * 0.83, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.61))
        path.addQuadCurve(to: CGPoint(x: w * 0.46, y: h * 0.63), control: CGPoint(x: w * 0.54, y: h * 0.64))
        path.addLine(to: CGPoint(x: w * 0.34, y: h * 0.83))
        path.addQuadCurve(to: CGPoint(x: w * 0.27, y: h * 0.82), control: CGPoint(x: w * 0.29, y: h * 0.87))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.60))
        path.addQuadCurve(to: CGPoint(x: w * 0.23, y: h * 0.58), control: CGPoint(x: w * 0.29, y: h * 0.61))
        path.addLine(to: CGPoint(x: w * 0.07, y: h * 0.75))
        path.addQuadCurve(to: CGPoint(x: w * 0.02, y: h * 0.72), control: CGPoint(x: w * 0.02, y: h * 0.77))
        path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.52))
        path.addQuadCurve(to: CGPoint(x: w * 0.03, y: h * 0.47), control: CGPoint(x: w * 0.10, y: h * 0.51))
        path.addQuadCurve(to: CGPoint(x: w * 0.07, y: h * 0.42), control: CGPoint(x: w * 0.02, y: h * 0.41))
        path.closeSubpath()

        let pawRadius = min(w, h) * 0.045
        path.addEllipse(in: CGRect(x: w * 0.92, y: h * 0.14, width: pawRadius, height: pawRadius))
        path.addEllipse(in: CGRect(x: w * 0.96, y: h * 0.19, width: pawRadius, height: pawRadius))
        path.addEllipse(in: CGRect(x: w * 0.94, y: h * 0.25, width: pawRadius, height: pawRadius))

        return path
    }
}

private struct CatInnerEarShape: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch side {
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY))
        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

private struct CatMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        path.move(to: CGPoint(x: midX, y: rect.minY))
        path.addLine(to: CGPoint(x: midX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.width * 0.32, y: rect.maxY)
        )
        path.move(to: CGPoint(x: midX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.width * 0.68, y: rect.maxY)
        )
        return path
    }
}

private struct CatWhiskersShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y1 = rect.midY - rect.height * 0.22
        let y2 = rect.midY + rect.height * 0.18
        path.move(to: CGPoint(x: rect.minX, y: y1))
        path.addLine(to: CGPoint(x: rect.width * 0.34, y: rect.midY))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: y2))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.midY + rect.height * 0.08))
        path.move(to: CGPoint(x: rect.width * 0.66, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: y1))
        path.move(to: CGPoint(x: rect.width * 0.65, y: rect.midY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: y2))
        return path
    }
}
