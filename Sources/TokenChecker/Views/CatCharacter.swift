import SwiftUI
import AppKit

/// RunCat の「ランナー選択」のように、ユーザーが選べる看板猫。
/// メニューバー・ヘッダー・プログレスバーの先頭に出る猫がこれで切り替わる。
/// 絵文字は使わず、SF Symbols と自前のベクター図形だけで描く。
enum CatCharacter: String, CaseIterable, Identifiable {
    case jump
    case kuro
    case maru
    case mood
    case paw
    case trail

    static let storageKey = "catCharacter"
    static let `default`: CatCharacter = .jump

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jump:  return "ぴょん"
        case .kuro:  return "くろ"
        case .maru:  return "まる"
        case .mood:  return "きぶん"
        case .paw:   return "肉球"
        case .trail: return "あしあと"
        }
    }
}

/// 選ばれた猫を描くビュー。
///
/// - `mood` は「きぶん」猫の表情に使う（それ以外の猫は無視）。
/// - `tint` は猫を描く単色。
/// - `useImage` が false のとき「ぴょん」は画像ではなくシルエットで描く（メニューバー用）。
struct CatMascot: View {
    let character: CatCharacter
    let size: CGFloat
    var mood: CatMood? = nil
    var tint: Color = .primary
    var useImage: Bool = true

    var body: some View {
        switch character {
        case .jump:
            if useImage {
                CatSilhouetteIcon(size: size, color: tint)
            } else if let silhouette = Self.menuBarSilhouette {
                // LeapingCat.png の猫だけを白抜きにしたもの。手描きの LeapingCatShape は
                // メニューバーの大きさだと細すぎて紐にしか見えないため、こちらを優先する。
                Image(nsImage: silhouette)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tint)
                    .frame(width: size * 1.15, height: size)
            } else {
                LeapingCatShape()
                    .fill(tint)
                    .frame(width: size * 1.3, height: size * 0.76)
                    .frame(width: size * 1.3, height: size)
            }
        case .kuro:
            symbol("cat.fill")
        case .maru:
            symbol("cat.circle.fill")
        case .mood:
            CatFaceView(mood: mood ?? .energetic, color: tint)
                .frame(width: size, height: size)
        case .paw:
            symbol("pawprint.fill")
        case .trail:
            ZStack {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .rotationEffect(.degrees(-14))
                    .offset(x: -size * 0.22, y: size * 0.16)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .rotationEffect(.degrees(14))
                    .offset(x: size * 0.22, y: -size * 0.16)
            }
            .foregroundStyle(tint)
            .frame(width: size, height: size)
        }
    }

    private static var menuBarSilhouette: NSImage? {
        Bundle.main.url(forResource: "LeapingCatSilhouette", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.82, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }
}

/// 気分で表情が変わる猫の顔。頭と耳を塗り、目と口は切り抜いて描く
/// （背景が透明なメニューバーでも表情が見えるように）。
struct CatFaceView: View {
    let mood: CatMood
    var color: Color = .primary

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: w * x, y: h * y) }

            // 頭と左右の耳は別々に塗る。1 つの Path にまとめると左右対称の耳の巻き方向が
            // 逆になり、頭と重なる部分が non-zero 規則で打ち消されて抜けてしまう。
            var head = Path()
            head.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.26, width: w * 0.84, height: h * 0.68))
            var leftEar = Path()
            leftEar.move(to: p(0.12, 0.52))
            leftEar.addLine(to: p(0.17, 0.06))
            leftEar.addLine(to: p(0.46, 0.30))
            leftEar.closeSubpath()
            var rightEar = Path()
            rightEar.move(to: p(0.88, 0.52))
            rightEar.addLine(to: p(0.83, 0.06))
            rightEar.addLine(to: p(0.54, 0.30))
            rightEar.closeSubpath()
            for part in [head, leftEar, rightEar] {
                ctx.fill(part, with: .color(color))
            }

            ctx.blendMode = .destinationOut
            let line = StrokeStyle(lineWidth: max(1, w * 0.075), lineCap: .round, lineJoin: .round)
            let eyeR = w * 0.075
            for cx in [0.34, 0.66] {
                let c = p(cx, 0.56)
                var eye = Path()
                switch mood {
                case .energetic:
                    // ^ ^ にっこり
                    eye.move(to: CGPoint(x: c.x - eyeR, y: c.y + eyeR * 0.4))
                    eye.addQuadCurve(to: CGPoint(x: c.x + eyeR, y: c.y + eyeR * 0.4),
                                     control: CGPoint(x: c.x, y: c.y - eyeR * 1.3))
                    ctx.stroke(eye, with: .color(.black), style: line)
                case .fine:
                    eye.addEllipse(in: CGRect(x: c.x - eyeR * 0.85, y: c.y - eyeR * 0.85,
                                              width: eyeR * 1.7, height: eyeR * 1.7))
                    ctx.fill(eye, with: .color(.black))
                case .tired:
                    // ー ー 半目
                    eye.move(to: CGPoint(x: c.x - eyeR, y: c.y))
                    eye.addLine(to: CGPoint(x: c.x + eyeR, y: c.y))
                    ctx.stroke(eye, with: .color(.black), style: line)
                case .exhausted:
                    // 見開いた目
                    eye.addEllipse(in: CGRect(x: c.x - eyeR * 1.3, y: c.y - eyeR * 1.3,
                                              width: eyeR * 2.6, height: eyeR * 2.6))
                    ctx.fill(eye, with: .color(.black))
                case .empty:
                    // しょんぼり
                    eye.move(to: CGPoint(x: c.x - eyeR, y: c.y - eyeR * 0.3))
                    eye.addQuadCurve(to: CGPoint(x: c.x + eyeR, y: c.y - eyeR * 0.3),
                                     control: CGPoint(x: c.x, y: c.y + eyeR * 1.1))
                    ctx.stroke(eye, with: .color(.black), style: line)
                }
            }

            var mouth = Path()
            if mood == .exhausted {
                mouth.addEllipse(in: CGRect(x: w * 0.45, y: h * 0.70, width: w * 0.10, height: h * 0.11))
                ctx.fill(mouth, with: .color(.black))
            } else {
                // ω
                mouth.move(to: p(0.40, 0.72))
                mouth.addQuadCurve(to: p(0.50, 0.73), control: p(0.45, 0.82))
                mouth.addQuadCurve(to: p(0.60, 0.72), control: p(0.55, 0.82))
                ctx.stroke(mouth, with: .color(.black), style: StrokeStyle(lineWidth: max(0.8, w * 0.055), lineCap: .round))
            }
        }
        // 切り抜き (destinationOut) を Canvas 内だけに閉じ込める
        .compositingGroup()
    }
}

/// ポップオーバーの設定欄に出す猫えらび。
struct CatPickerView: View {
    @Binding var selection: CatCharacter
    var mood: CatMood?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(CatCharacter.allCases) { character in
                let isSelected = character == selection
                Button {
                    selection = character
                } label: {
                    VStack(spacing: 3) {
                        CatMascot(character: character, size: 22, mood: mood, tint: Color(white: 0.3))
                            .frame(height: 24)
                        Text(character.displayName)
                            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    .frame(width: 40, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isSelected ? Color.accentColor.opacity(0.10) : Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isSelected ? Color.accentColor.opacity(0.8) : Theme.cardBorder, lineWidth: isSelected ? 1.5 : 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(character.displayName)
            }
        }
    }
}

/// 白ベースのポップオーバーで使う色。
enum Theme {
    static let background = Color.white
    static let card = Color(red: 0.972, green: 0.970, blue: 0.965)
    static let cardBorder = Color.black.opacity(0.05)
}
