import Foundation

/// Antigravity のモデル別残量を「Gemini Pro / Gemini Flash / Claude / GPT-OSS」の系統にまとめる。
///
/// Gemini CLI の個人向け無料枠は Google 側で打ち切られ Antigravity へ移行したため、
/// Gemini の使用状況は Antigravity から取る。残量はモデルごとに 5 時間で回復する。
struct GeminiUsageProvider: UsageProvider {
    let client: AntigravityClient

    init(client: AntigravityClient = .init()) {
        self.client = client
    }

    func fetch() async throws -> ServiceUsage {
        let (dto, planName) = try await client.fetchModels()
        let families = Self.families(from: dto)
        // 最も減っている系統をメニューバーの代表値にする
        let worst = families.max { $0.limit.utilization < $1.limit.utilization }
        return ServiceUsage(
            fiveHour: worst?.limit,
            weekly: nil,
            weeklySonnet: nil,
            details: families,
            planName: planName
        )
    }

    private static let familyOrder = ["Gemini Pro", "Gemini Flash", "Claude", "GPT-OSS"]

    static func families(from dto: AntigravityModelsDTO) -> [LabeledLimit] {
        let models = dto.models ?? [:]
        // エージェントで選べるモデル (Recommended) に絞る。無ければ全モデル。
        let recommended = Set(
            (dto.agentModelSorts ?? [])
                .flatMap { $0.groups ?? [] }
                .flatMap { $0.modelIds ?? [] }
        )
        let targets = recommended.isEmpty ? models : models.filter { recommended.contains($0.key) }

        var worstByFamily: [String: RateLimit] = [:]
        for (id, model) in targets {
            guard let quota = model.quotaInfo,
                  let resetString = quota.resetTime,
                  let resetsAt = ISO8601DateFormatter.standard.date(from: resetString)
                               ?? ISO8601DateFormatter.withFractional.date(from: resetString) else {
                continue
            }
            let remaining = min(max(quota.remainingFraction ?? 0, 0), 1)
            let limit = RateLimit(utilization: 1 - remaining, resetsAt: resetsAt)
            let family = family(id: id, model: model)
            if let current = worstByFamily[family], current.utilization >= limit.utilization { continue }
            worstByFamily[family] = limit
        }

        return worstByFamily
            .map { LabeledLimit(label: $0.key, limit: $0.value) }
            .sorted { lhs, rhs in
                let l = familyOrder.firstIndex(of: lhs.label) ?? familyOrder.count
                let r = familyOrder.firstIndex(of: rhs.label) ?? familyOrder.count
                return l != r ? l < r : lhs.label < rhs.label
            }
    }

    private static func family(id: String, model: AntigravityModelsDTO.Model) -> String {
        let name = (model.displayName ?? id).lowercased()
        switch model.modelProvider {
        case "MODEL_PROVIDER_ANTHROPIC":
            return "Claude"
        case "MODEL_PROVIDER_OPENAI":
            return "GPT-OSS"
        case "MODEL_PROVIDER_GOOGLE":
            return name.contains("pro") || id.contains("pro") ? "Gemini Pro" : "Gemini Flash"
        default:
            return model.displayName ?? id
        }
    }
}
