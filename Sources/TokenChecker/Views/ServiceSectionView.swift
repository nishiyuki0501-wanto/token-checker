import SwiftUI

/// 1 サービスぶんの詳細セクション。
/// どのブランドのセクションかを表す。
enum ServiceBrand {
    case claude
    case codex
    case gemini
    case cursor
}

struct ServiceSectionView: View {
    let title: String
    let brand: ServiceBrand
    let result: Result<ServiceUsage, DomainError>?
    let loginAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                brandMark
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if case .success(let usage) = result, let plan = usage.planName {
                    Text(plan)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let mood {
                    HStack(spacing: 3) {
                        CatFaceView(mood: mood, color: mood.color)
                            .frame(width: 13, height: 13)
                        Text(mood.status)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(mood.color)
                    }
                }
                Button {
                    loginAction()
                } label: {
                    Image(systemName: "person.badge.key")
                }
                .buttonStyle(.borderless)
                .help(brand == .cursor ? "Cursor を開く" : "\(title) にログイン")
            }

            switch result {
            case .none:
                Text("くんくん… ようすを見てるにゃ")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .some(.success(let usage)):
                usageBlock(usage)
            case .some(.failure(let err)):
                errorBlock(err)
            }
        }
    }

    private var mood: CatMood? {
        guard case .success(let usage) = result, let headline = usage.headline else { return nil }
        return CatMood(utilization: headline.utilization)
    }

    @ViewBuilder
    private func usageBlock(_ usage: ServiceUsage) -> some View {
        // メインは 5h → 週次 → 月次 の最初に存在するもの (ServiceUsage.headline と同じ順)。
        // Codex の一部プラン (prolite 等) は 5h が無く週次のみ、Cursor は月次のみ。
        if let five = usage.fiveHour {
            limitRow(label: "5時間", limit: five)
            if let weekly = usage.weekly {
                secondaryRow(label: "週次", limit: weekly)
            }
        } else if let weekly = usage.weekly {
            limitRow(label: "週次", limit: weekly)
        } else if let monthly = usage.monthly {
            limitRow(label: "今月", limit: monthly)
        } else {
            Text("使用率のデータがないにゃ")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        if let sonnet = usage.weeklySonnet {
            secondaryRow(label: "週次 (Sonnet)", limit: sonnet)
        }
        ForEach(usage.details, id: \.label) { detail in
            secondaryRow(label: detail.label, limit: detail.limit)
        }
    }

    private func limitRow(label: String, limit: RateLimit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(limit.percent)%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color(for: limit.utilization))
            }
            ProgressBarView(value: limit.utilization, height: 8)
            Text(resetLabel(limit.resetsAt))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func secondaryRow(label: String, limit: RateLimit) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(limit.percent)%")
                .font(.system(size: 11))
                .foregroundStyle(color(for: limit.utilization))
        }
    }

    private func errorBlock(_ err: DomainError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("うまく取れなかったにゃ…")
                    .font(.system(size: 12, weight: .medium))
            }
            Text(err.errorDescription ?? "原因不明")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var brandMark: some View {
        switch brand {
        case .claude:
            Image(systemName: "pawprint.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        case .codex:
            CatSilhouetteIcon(size: 10, color: .primary)
        case .gemini:
            Image(systemName: "cat.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        case .cursor:
            Image(systemName: "fish.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func color(for value: Double) -> Color {
        if value < 0.7 { return .green }
        if value < 0.85 { return .orange }
        return .red
    }

    private func resetLabel(_ date: Date) -> String {
        let now = Date()
        if date <= now { return "もうすぐ回復するにゃ" }
        let f = DateComponentsFormatter()
        // 週次・月次のウィンドウもあるので日単位まで出し、上位 2 単位に絞る
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 2
        f.unitsStyle = .abbreviated
        let rel = f.string(from: now, to: date) ?? "—"
        let sameDay = Calendar.current.isDate(date, inSameDayAs: now)
        let absolute = DateFormatter.localizedString(from: date, dateStyle: sameDay ? .none : .short, timeStyle: .short)
        return "あと \(rel) で回復にゃ (\(absolute))"
    }
}
