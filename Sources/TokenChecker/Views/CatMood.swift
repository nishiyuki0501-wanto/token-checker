import SwiftUI

/// 使用率から決まる「にゃんこの気分」。ポップオーバーとメニューバーで共通に使う。
/// 表情は絵文字ではなく CatFaceView で描く。
enum CatMood {
    case energetic
    case fine
    case tired
    case exhausted
    case empty

    init(utilization: Double) {
        switch utilization {
        case ..<0.5:  self = .energetic
        case ..<0.7:  self = .fine
        case ..<0.85: self = .tired
        case ..<1.0:  self = .exhausted
        default:      self = .empty
        }
    }

    /// サービス 1 つぶんの短い状態。
    var status: String {
        switch self {
        case .energetic: return "元気いっぱい"
        case .fine:      return "まだまだいける"
        case .tired:     return "ちょっとお疲れ"
        case .exhausted: return "もうすぐ限界"
        case .empty:     return "スタミナ切れ"
        }
    }

    /// ヘッダーに出す全体のひとこと。
    var headline: String {
        switch self {
        case .energetic: return "みんな元気いっぱいだにゃ"
        case .fine:      return "まだまだ遊べるにゃ"
        case .tired:     return "ちょっとお疲れだにゃ…"
        case .exhausted: return "そろそろ限界だにゃ…"
        case .empty:     return "スタミナ切れだにゃ… おひるねするにゃ"
        }
    }

    var color: Color {
        switch self {
        case .energetic, .fine: return .green
        case .tired:            return .orange
        case .exhausted, .empty: return .red
        }
    }
}
