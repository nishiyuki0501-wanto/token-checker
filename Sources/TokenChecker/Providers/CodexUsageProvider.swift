import Foundation

/// `codex app-server` を介して Codex の rate limit を取得。
/// アプリのライフタイム中 1 プロセスを共有する。失敗時は再起動を試みる。
final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    private let client: CodexAppServerClient
    private var lastAuthSignature: String?

    init(client: CodexAppServerClient = .init()) {
        self.client = client
    }

    func fetch() async throws -> ServiceUsage {
        // auth.json のシグネチャ（更新日時・サイズ・account_id）をチェックし、
        // アカウント切り替え（OAuth ログイン）があった場合は古いプロセスを停止して新アカウントで再起動
        let currentSignature = Self.readAuthSignature()
        if let last = lastAuthSignature, last != currentSignature {
            await client.stop()
        }
        lastAuthSignature = currentSignature

        do {
            try await client.start()
            let dto = try await client.readRateLimits()
            return ServiceUsage(
                fiveHour: dto.fiveHourRateLimit(),
                weekly: dto.weeklyRateLimit(),
                weeklySonnet: nil,
                planName: Self.displayPlanName(dto.planType)
            )
        } catch {
            // プロセス異常終了だけでなくタイムアウトやRPCエラー等でも、
            // 壊れたプロセスの残留を防ぐため一度プロセスを停止して再試行する
            await client.stop()
            do {
                try await client.start()
                let dto = try await client.readRateLimits()
                return ServiceUsage(
                    fiveHour: dto.fiveHourRateLimit(),
                    weekly: dto.weeklyRateLimit(),
                    weeklySonnet: nil,
                    planName: Self.displayPlanName(dto.planType)
                )
            } catch {
                // 再試行も失敗した場合はプロセスを停止状態にして次回ポーリングで新プロセスから再開
                await client.stop()
                throw error
            }
        }
    }

    func shutdown() async {
        await client.stop()
    }

    // MARK: - Auth File Monitoring

    private static func authFileURL() -> URL {
        let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".codex/auth.json")
    }

    /// auth.json の更新検知用シグネチャを生成。
    /// ファイルの mtime + サイズ + account_id（取得できれば）を組み合わせる。
    private static func readAuthSignature() -> String? {
        let url = authFileURL()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? UInt64) ?? 0

        var accountId = ""
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokens = obj["tokens"] as? [String: Any],
           let aid = tokens["account_id"] as? String {
            accountId = aid
        }
        return "\(mtime)_\(size)_\(accountId)"
    }

    /// プラン名の表示用整形（"plus" -> "Plus", "prolite" -> "Pro Lite", "pro" -> "Pro" など）
    private static func displayPlanName(_ raw: String?) -> String? {
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "prolite": return "Pro Lite"
        case "plus":    return "Plus"
        case "pro":     return "Pro"
        case "free":    return "Free"
        case "team":    return "Team"
        default:        return raw.capitalized
        }
    }
}
