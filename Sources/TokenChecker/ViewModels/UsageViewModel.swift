import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class UsageViewModel {
    // applicationWillTerminate から MainActor を経由せず shutdown を呼べるよう
    // nonisolated 化する。providers 自体は immutable なので Sendable 違反は起きない。
    private nonisolated let claudeProvider: UsageProvider
    private nonisolated let codexProvider: UsageProvider
    private nonisolated let geminiProvider: UsageProvider
    private nonisolated let cursorProvider: UsageProvider

    var snapshot: UsageSnapshot = .empty
    var isLoading: Bool = false
    var pollingInterval: PollingInterval {
        didSet { persistInterval() }
    }

    init(
        claudeProvider: UsageProvider = ClaudeUsageProvider(),
        codexProvider: UsageProvider = CodexUsageProvider(),
        geminiProvider: UsageProvider = GeminiUsageProvider(),
        cursorProvider: UsageProvider = CursorUsageProvider()
    ) {
        self.claudeProvider = claudeProvider
        self.codexProvider = codexProvider
        self.geminiProvider = geminiProvider
        self.cursorProvider = cursorProvider
        self.pollingInterval = Self.loadPersistedInterval()
    }

    /// `task(id: pollingInterval)` から駆動するメインループ。
    func runPollingLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(pollingInterval.seconds * 1_000_000_000))
            } catch {
                return
            }
            await refresh()
        }
    }

    /// アプリ終了時に子プロセスや永続接続を解放するためのクロージャを返す。
    ///
    /// `@MainActor` final class である自身を `@Sendable` クロージャがキャプチャできないため
    /// (Swift 6 strict-concurrency でエラー)、Sendable な providers だけを閉じ込めて公開する。
    /// AppDelegate.applicationWillTerminate からは MainActor を経由せず呼ばれる。
    nonisolated func makeShutdownHandler() -> @Sendable () async -> Void {
        let claude = claudeProvider
        let codex = codexProvider
        let gemini = geminiProvider
        let cursor = cursorProvider
        return {
            await claude.shutdown()
            await codex.shutdown()
            await gemini.shutdown()
            await cursor.shutdown()
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let claude = Self.fetch(claudeProvider, logger: .claude)
        async let codex = Self.fetch(codexProvider, logger: .codex)
        async let gemini = Self.fetch(geminiProvider, logger: .gemini)
        async let cursor = Self.fetch(cursorProvider, logger: .cursor)

        let (c, x, g, u) = await (claude, codex, gemini, cursor)
        snapshot = UsageSnapshot(claude: c, codex: x, gemini: g, cursor: u, fetchedAt: Date())
    }

    private nonisolated static func fetch(
        _ provider: UsageProvider,
        logger: Logger
    ) async -> Result<ServiceUsage, DomainError> {
        do {
            return .success(try await provider.fetch())
        } catch let err as DomainError {
            logger.error("fetch failed: \(err.localizedDescription)")
            return .failure(err)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - ログインボタン

    /// どのサービスを再ログインするかは enum 型で表現する。
    /// 任意文字列を AppleScript に渡せないようにしてインジェクションを「型として」不能にする。
    enum LoginTarget {
        case claude
        case codex
        case gemini

        var command: String {
            switch self {
            case .claude: return "claude login"
            case .codex:  return "codex login"
            // agy はログインサブコマンドを持たず、起動時に未ログインならブラウザ認証に進む
            case .gemini: return "agy"
            }
        }
    }

    func openClaudeLogin() { spawnLogin(.claude) }
    func openCodexLogin()  { spawnLogin(.codex) }
    func openGeminiLogin() { spawnLogin(.gemini) }

    /// Cursor は IDE 本体がトークンを持つので、ログイン = Cursor を開く。
    func openCursorLogin() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Cursor"]
        do { try process.run() } catch {
            Logger.ui.error("open Cursor failed: \(error.localizedDescription)")
        }
    }

    private func spawnLogin(_ target: LoginTarget) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(target.command)"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do { try process.run() } catch {
            Logger.ui.error("login spawn failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 永続化

    private static let intervalKey = "pollingInterval"

    private static func loadPersistedInterval() -> PollingInterval {
        let raw = UserDefaults.standard.integer(forKey: intervalKey)
        return PollingInterval(rawValue: raw) ?? .default
    }

    private func persistInterval() {
        UserDefaults.standard.set(pollingInterval.rawValue, forKey: Self.intervalKey)
    }
}
