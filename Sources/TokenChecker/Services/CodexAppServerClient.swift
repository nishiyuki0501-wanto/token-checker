@preconcurrency import Foundation

/// `codex app-server` を spawn して JSON-RPC で会話する actor。
///
/// 大まかな流れ:
///   1. `start()` で Process を spawn → `initialize` → `initialized` の handshake
///   2. `readRateLimits()` で `account/rateLimits/read` を叩く
///   3. アプリ終了時に `stop()` で Process を終了
actor CodexAppServerClient {
    private let candidates: [String]
    private let requestTimeout: TimeInterval

    private var nextId = 1
    private var pending: [Int: CheckedContinuation<RPCInbound, Error>] = [:]
    private var process: Process?
    private var stdin: Pipe?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var lineBuffer = JSONRPCLineBuffer()

    init(
        candidates: [String]? = nil,
        requestTimeout: TimeInterval = 8
    ) {
        self.candidates = candidates ?? Self.defaultCandidatePaths()
        self.requestTimeout = requestTimeout
    }

    // MARK: - Lifecycle

    func start() async throws {
        if process != nil { return }

        guard let executable = resolveExecutable() else {
            throw DomainError.codexCLINotFound
        }

        let proc = Process()
        let inP = Pipe(), outP = Pipe(), errP = Pipe()

        proc.executableURL = executable
        proc.arguments = ["app-server"]
        proc.environment = Self.childEnvironment(from: ProcessInfo.processInfo.environment)
        proc.standardInput = inP
        proc.standardOutput = outP
        proc.standardError = errP

        proc.terminationHandler = { [weak self] _ in
            Task { await self?.handleProcessTerminated() }
        }

        outP.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleStdout(data) }
        }
        errP.fileHandleForReading.readabilityHandler = { handle in
            // stderr を捨てるとしても availableData を読まなければ macOS のパイプバッファ
            // (既定 64 KiB) が解放されず、子プロセスが write(2) でブロックする。必ずドレインする。
            _ = handle.availableData
        }

        do {
            try proc.run()
        } catch {
            throw DomainError.network("codex app-server failed to start: \(error.localizedDescription)")
        }

        self.process = proc
        self.stdin = inP
        self.stdout = outP
        self.stderr = errP

        _ = try await request(method: "initialize", params: InitializeParams.defaultClient)
        try send(method: "initialized", params: EmptyParams(), isNotification: true)
    }

    func stop() {
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        // stop() → start() の再起動シーケンスで、旧プロセスの terminationHandler が
        // 遅延発火 → handleProcessTerminated() が actor に hop → 新プロセスの状態を
        // 破壊する race を防ぐため、terminate より前にハンドラを解除する。
        process?.terminationHandler = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        try? stdin?.fileHandleForWriting.close()
        try? stdout?.fileHandleForReading.close()
        try? stderr?.fileHandleForReading.close()
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        lineBuffer.removeAll()
        failPending(with: DomainError.codexProcessExited)
    }

    // MARK: - RPC methods

    func readRateLimits() async throws -> CodexRateLimitsDTO {
        let envelope = try await request(method: "account/rateLimits/read", params: EmptyParams())
        guard let result = envelope.result else {
            let errorMsg = envelope.error?.message ?? "missing result for account/rateLimits/read"
            throw DomainError.codexRPCError(message: errorMsg)
        }
        do {
            return try result.decode(as: CodexRateLimitsDTO.self)
        } catch {
            throw DomainError.decoding("codex rateLimits: \(error.localizedDescription)")
        }
    }

    // MARK: - Internals

    private func resolveExecutable() -> URL? {
        candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// GUI アプリは login shell の PATH を継承しないため、Homebrew 以外の一般的な
    /// npm/global installer の配置先も明示的に見る。
    private static func defaultCandidatePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let fixedCandidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.volta/bin/codex",
            "\(home)/.asdf/shims/codex",
        ]
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/codex" }

        var seen = Set<String>()
        return (fixedCandidates + pathCandidates).filter { seen.insert($0).inserted }
    }

    /// 子プロセス (`codex app-server`) に渡す環境変数を最小限の whitelist で構築する。
    ///
    /// 親プロセス（このアプリ）の環境変数をそのまま継承させると、ターミナル経由で
    /// 起動した場合に `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `AWS_*` 等の秘密が
    /// 子に渡ってしまう。codex 自身が必要とするのは PATH と HOME 程度なので、
    /// それ以外は意図的に渡さない。
    private static func childEnvironment(from base: [String: String]) -> [String: String] {
        // codex が動くのに必要な最小キーだけ通す
        let allowedKeys: Set<String> = [
            "HOME", "USER", "LOGNAME", "SHELL",
            "LANG", "LC_ALL", "LC_CTYPE",
            "TMPDIR",
            "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
            // codex CLI 固有
            "CODEX_HOME",
        ]
        var env: [String: String] = [:]
        for key in allowedKeys {
            if let value = base[key] { env[key] = value }
        }

        // PATH は固定セット + 親の PATH の安全な部分をマージ
        let basePathDirs = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = base["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "\(home)/.asdf/shims",
        ]
        var seen = Set<String>()
        let merged = (extras + basePathDirs).filter { seen.insert($0).inserted }.joined(separator: ":")
        env["PATH"] = merged
        return env
    }

    private func send<P: Encodable>(method: String, params: P?, isNotification: Bool = false) throws {
        guard let stdin else {
            throw DomainError.codexProcessExited
        }
        let id: Int? = isNotification ? nil : { defer { self.nextId += 1 }; return self.nextId }()
        let envelope = RPCOutbound(method: method, id: id, params: params)
        var data = try JSONEncoder().encode(envelope)
        data.append(0x0A)
        stdin.fileHandleForWriting.write(data)
    }

    /// 1 リクエストを投げて、レスポンスかタイムアウトのどちらかで完了する。
    ///
    /// 競合状態の扱い：
    /// - 書き込みは actor isolated な同期処理として実行（hop なし）
    /// - `withCheckedThrowingContinuation` のクロージャ本体も同 actor 内で動くので
    ///   `pending[id] = cont` は atomic に登録される
    /// - タイムアウト Task が `cancelPending(id:)` を呼ぶことで継続が確実に解決される
    /// - レスポンスが先に来た場合は `defer` でタイムアウト Task を cancel して終了
    private func request<P: Encodable>(method: String, params: P) async throws -> RPCInbound {
        guard let stdin else { throw DomainError.codexProcessExited }
        let id = nextId
        nextId += 1
        let timeout = requestTimeout

        // 同期的にエンコードして書き込み（actor 内、hop なし）
        let envelope = RPCOutbound(method: method, id: id, params: params)
        var data = try JSONEncoder().encode(envelope)
        data.append(0x0A)
        stdin.fileHandleForWriting.write(data)

        // タイムアウト監視タスクを別途起動
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled {
                await self?.cancelPending(id: id)
            }
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RPCInbound, Error>) in
            // クロージャは actor isolated な同期コンテキストで実行される
            pending[id] = cont
        }
    }

    /// レスポンス到着時に呼ぶ。継続がすでに無ければ no-op（タイムアウト後の到着など）。
    private func resumePending(id: Int, with result: Result<RPCInbound, Error>) {
        guard let cont = pending.removeValue(forKey: id) else { return }
        switch result {
        case .success(let env): cont.resume(returning: env)
        case .failure(let err): cont.resume(throwing: err)
        }
    }

    /// タイムアウト時に呼ぶ。継続を timeout エラーで終わらせる。
    private func cancelPending(id: Int) {
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(throwing: DomainError.timeout)
    }

    private func failPending(with error: DomainError) {
        let snapshot = pending
        pending.removeAll()
        for cont in snapshot.values {
            cont.resume(throwing: error)
        }
    }

    // MARK: - Stream handling

    private func handleStdout(_ data: Data) {
        if data.isEmpty {
            handleProcessTerminated()
            return
        }
        for line in lineBuffer.append(data) {
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        do {
            let inbound = try JSONDecoder().decode(RPCInbound.self, from: data)
            if let id = inbound.id {
                resumePending(id: id, with: .success(inbound))
            }
            // notifications (no id) は今は無視
        } catch {
            // 不正な行は捨てる
        }
    }

    private func handleProcessTerminated() {
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        // 子プロセスの異常終了 (外部 kill / OOM 等) でこの経路を通る場合、
        // stop() を介さないため Pipe の fd を明示的に閉じる必要がある。
        // 閉じないと CodexUsageProvider の再起動ループで fd が累積し枯渇する。
        try? stdin?.fileHandleForWriting.close()
        try? stdout?.fileHandleForReading.close()
        try? stderr?.fileHandleForReading.close()
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        lineBuffer.removeAll()
        failPending(with: .codexProcessExited)
    }
}

// MARK: - RPC params / DTOs

struct EmptyParams: Encodable, Sendable {}

struct InitializeParams: Encodable, Sendable {
    let clientInfo: ClientInfo
    let capabilities: Capabilities

    struct ClientInfo: Encodable, Sendable {
        let name: String
        let version: String
    }
    struct Capabilities: Encodable, Sendable {}

    static let defaultClient = InitializeParams(
        clientInfo: .init(name: "token-checker", version: "0.1.0"),
        capabilities: .init()
    )
}

/// `account/rateLimits/read` のレスポンス。
///
/// 実際の構造（codex-usage-menu のテストフィクスチャから確認）:
/// ```json
/// {
///   "rateLimits": {
///     "limitId": "codex",
///     "primary":   { "usedPercent": 25, "windowDurationMins": 300,   "resetsAt": 1760000000 },
///     "secondary": { "usedPercent": 28, "windowDurationMins": 10080, "resetsAt": 1760604800 },
///     "planType": "pro"
///   },
///   "rateLimitsByLimitId": { "codex": { ... 同じ構造 ... } }
/// }
/// ```
///
/// - JSON キーは camelCase（snake_case ではない）
/// - `usedPercent` は **0〜100 の Int**
/// - `resetsAt` は **Unix epoch 秒の Int64**
/// - `windowDurationMins`: 300 = 5 時間、10080 = 週次
struct CodexRateLimitsDTO: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let accountId: String?

    struct RateLimitSnapshot: Decodable, Sendable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Int?
        let windowDurationMins: Int64?
        let resetsAt: Int64?
    }
}

extension CodexRateLimitsDTO {
    /// アカウントのプラン種別（"plus", "pro" など）。
    var planType: String? {
        rateLimits?.planType ?? rateLimitsByLimitId?["codex"]?.planType
    }

    /// 5h (300 分前後) ウィンドウを抽出。
    /// Plusプランなどでは primary に 5時間リミット（300分）が設定される。Proプランには存在しない。
    func fiveHourRateLimit() -> RateLimit? {
        // まず厳密に 300分（5時間）を探す
        if let window = window(forDurationMins: 300) {
            return Self.toRateLimit(window)
        }
        // フォールバック: 12時間（720分）以下かつ週次でない短期ウィンドウを採用
        if let shortWindow = allWindows().first(where: {
            guard let mins = $0.windowDurationMins else { return false }
            return mins > 0 && mins <= 720 && mins != 10080
        }) {
            return Self.toRateLimit(shortWindow)
        }
        return nil
    }

    /// 週次 (10080 分前後) ウィンドウを抽出。
    /// Proプランでは週次のみ、Plusプランでは secondary などに設定される。
    func weeklyRateLimit() -> RateLimit? {
        // まず厳密に 10080分（7日）を探す
        if let window = window(forDurationMins: 10080) {
            return Self.toRateLimit(window)
        }
        // フォールバック: 24時間（1440分）以上の長期ウィンドウを採用
        if let longWindow = allWindows().first(where: {
            guard let mins = $0.windowDurationMins else { return false }
            return mins >= 1440
        }) {
            return Self.toRateLimit(longWindow)
        }
        return nil
    }

    /// 利用可能な全ウィンドウを優先順（rateLimits → rateLimitsByLimitId）で取得。
    private func allWindows() -> [Window] {
        var windows: [Window] = []
        if let snap = rateLimits {
            if let p = snap.primary { windows.append(p) }
            if let s = snap.secondary { windows.append(s) }
        }
        let sortedSnapshots = (rateLimitsByLimitId ?? [:]).sorted(by: { $0.key < $1.key })
        for (_, snap) in sortedSnapshots {
            if let p = snap.primary { windows.append(p) }
            if let s = snap.secondary { windows.append(s) }
        }
        return windows
    }

    /// 指定分数のウィンドウを探す。primary/secondary 両方を見る。
    private func window(forDurationMins minutes: Int64) -> Window? {
        allWindows().first { $0.windowDurationMins == minutes }
    }

    /// `usedPercent` または `resetsAt` が欠落しているウィンドウは「データなし」として nil 返却。
    /// 旧実装は欠落値を 0 にフォールバックしていたため、Codex API がフィールドを返さなくなった
    /// 際に `resetsAt = 1970-01-01` となり UI が永続的に「まもなくリセット」を表示してしまっていた。
    private static func toRateLimit(_ window: Window) -> RateLimit? {
        guard let used = window.usedPercent, let resets = window.resetsAt else { return nil }
        // Window モデル内の usedPercent は 0-100 の Int 想定なので /100 で 0.0-1.0 化。
        // 負値は API バグとして 0 に丸める。上限は呼び出し側 (MenuBarLabel) で表示時に処理。
        let utilization = max(0, Double(used) / 100.0)
        let date = Date(timeIntervalSince1970: TimeInterval(resets))
        return RateLimit(utilization: utilization, resetsAt: date)
    }
}
