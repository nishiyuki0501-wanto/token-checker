import Foundation

/// 1 つのレート制限ウィンドウ。
struct RateLimit: Equatable, Sendable {
    /// 0.0 〜 1.0+。1.0 で 100% 使用。たまに 1.0 を超えることがある（API 側仕様）。
    let utilization: Double
    /// ウィンドウがリセットされる時刻。
    let resetsAt: Date

    var percent: Int { Int((utilization * 100).rounded()) }
}

/// ラベル付きの補助ウィンドウ（Antigravity のモデル系統別、Cursor の Auto/API 内訳など）。
struct LabeledLimit: Equatable, Sendable {
    let label: String
    let limit: RateLimit
}

/// 1 サービスの使用状況。
struct ServiceUsage: Equatable, Sendable {
    let fiveHour: RateLimit?
    let weekly: RateLimit?
    /// Claude のみ。Sonnet 専用 7d ウィンドウ。
    let weeklySonnet: RateLimit?
    /// Cursor の請求サイクル（月次）。
    var monthly: RateLimit? = nil
    /// ポップオーバーに追加で並べる内訳。
    var details: [LabeledLimit] = []
    /// プラン名（"Google AI Pro" など）。分かるときだけ。
    var planName: String? = nil

    /// メニューバーに出す代表値。5h → 週次 → 月次 の順に、最初に存在するもの。
    /// Codex の一部プラン (prolite 等) は 5h ウィンドウを返さず週次のみになる。
    var headline: RateLimit? { fiveHour ?? weekly ?? monthly }
}

/// 取得結果。1 サービスが失敗しても他は表示できるよう個別に保持。
struct UsageSnapshot: Equatable, Sendable {
    let claude: Result<ServiceUsage, DomainError>?
    let codex: Result<ServiceUsage, DomainError>?
    let gemini: Result<ServiceUsage, DomainError>?
    let cursor: Result<ServiceUsage, DomainError>?
    let fetchedAt: Date

    static let empty = UsageSnapshot(claude: nil, codex: nil, gemini: nil, cursor: nil, fetchedAt: .distantPast)

    /// メニューバーに数字を出すサービス。並びはポップオーバーと同じで、
    /// 未インストール・未ログインのサービスは除く。
    var menuBarEntries: [(name: String, result: Result<ServiceUsage, DomainError>?)] {
        [
            ("Claude", claude),
            ("Codex", codex),
            ("Gemini", gemini),
            ("Cursor", cursor),
        ].filter { _, result in
            if case .failure(let err) = result, err.isNotConfigured { return false }
            return true
        }
    }

    /// 取得できた全サービスのうち最も逼迫している使用率。ヘッダーの気分表示に使う。
    var worstUtilization: Double? {
        [claude, codex, gemini, cursor]
            .compactMap { result -> Double? in
                guard case .success(let usage) = result else { return nil }
                return usage.headline?.utilization
            }
            .max()
    }
}
