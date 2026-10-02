import Foundation

/// Cursor の state DB のトークン → `GetCurrentPeriodUsage`。
/// Cursor は 5h / 週次ではなく月次の請求サイクルで上限が決まる。
struct CursorUsageProvider: UsageProvider {
    let client: CursorClient

    init(client: CursorClient = .init()) {
        self.client = client
    }

    func fetch() async throws -> ServiceUsage {
        let credentials = try client.readCredentials()
        let dto = try await client.fetch(accessToken: credentials.accessToken)

        guard let end = dto.billingCycleEnd?.value, let plan = dto.planUsage else {
            return ServiceUsage(fiveHour: nil, weekly: nil, weeklySonnet: nil,
                                planName: Self.planName(credentials.membershipType))
        }
        let resetsAt = Date(timeIntervalSince1970: end / 1000)

        var total: Double?
        if let percent = plan.totalPercentUsed {
            total = percent / 100
        } else if let limit = plan.limit, limit > 0, let remaining = plan.remaining {
            total = (limit - remaining) / limit
        }

        var details: [LabeledLimit] = []
        if let auto = plan.autoPercentUsed {
            details.append(LabeledLimit(label: "Auto", limit: RateLimit(utilization: max(0, auto / 100), resetsAt: resetsAt)))
        }
        if let api = plan.apiPercentUsed {
            details.append(LabeledLimit(label: "モデル指定", limit: RateLimit(utilization: max(0, api / 100), resetsAt: resetsAt)))
        }

        return ServiceUsage(
            fiveHour: nil,
            weekly: nil,
            weeklySonnet: nil,
            monthly: total.map { RateLimit(utilization: max(0, $0), resetsAt: resetsAt) },
            details: details,
            planName: Self.planName(credentials.membershipType)
        )
    }

    private static func planName(_ membership: String?) -> String? {
        guard let membership, !membership.isEmpty else { return nil }
        return "Cursor " + membership.prefix(1).uppercased() + membership.dropFirst()
    }
}
