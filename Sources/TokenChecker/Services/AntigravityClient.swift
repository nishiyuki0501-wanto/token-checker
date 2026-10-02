import Foundation

/// Antigravity (Gemini) の Code Assist 内部 API から、モデル別の残量を取得する actor。
///
/// 大まかな流れ:
///   1. `~/.gemini/jetski-standalone-oauth-token` の refresh_token でアクセストークンを再発行
///      （ファイル内の access_token は agy 起動時にしか更新されず、すぐ期限切れになるため）
///   2. `v1internal:loadCodeAssist` でプロジェクト ID とプラン名を得る
///   3. `v1internal:fetchAvailableModels` でモデルごとの `quotaInfo` を得る
///
/// トークン再発行に使う OAuth クライアント ID / シークレットは、agy や Antigravity.app の
/// バイナリに埋め込まれているものを実行時に読み取る。リポジトリにシークレットを置かないため、
/// また Antigravity 側の更新に自動追従するため。再発行したトークンはファイルへ書き戻さない
/// （agy 本体との競合を避ける）。
actor AntigravityClient {
    private static let baseURL = "https://cloudcode-pa.googleapis.com/v1internal:"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    /// Google 側は UA でクライアント種別を判定しており、別の UA だとプロジェクトが返らない。
    private static let userAgent = "antigravity"

    private let session = NoRedirectDelegate.makeSession()
    private let home: String

    private var clientCredentials: ClientCredentials?
    private var accessToken: (value: String, expiresAt: Date)?
    private var project: (id: String, planName: String?)?

    init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    func fetchModels() async throws -> (models: AntigravityModelsDTO, planName: String?) {
        let project = try await resolveProject()
        let data = try await post("fetchAvailableModels", body: ["project": project.id])
        do {
            return (try JSONDecoder().decode(AntigravityModelsDTO.self, from: data), project.planName)
        } catch {
            throw DomainError.decoding("Antigravity models: \(error.localizedDescription)")
        }
    }

    // MARK: - Project

    private func resolveProject() async throws -> (id: String, planName: String?) {
        if let project { return project }
        let body: [String: Any] = [
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI",
            ],
        ]
        let data = try await post("loadCodeAssist", body: body)
        let dto: LoadCodeAssistDTO
        do {
            dto = try JSONDecoder().decode(LoadCodeAssistDTO.self, from: data)
        } catch {
            throw DomainError.decoding("Antigravity loadCodeAssist: \(error.localizedDescription)")
        }
        guard let id = dto.cloudaicompanionProject?.id, !id.isEmpty else {
            // プロジェクトが無い = Antigravity の利用資格が無いアカウント
            throw DomainError.geminiUnauthorized
        }
        let resolved = (id: id, planName: dto.paidTier?.name ?? dto.currentTier?.name)
        project = resolved
        return resolved
    }

    // MARK: - HTTP

    /// 401 のときはアクセストークンを捨てて 1 回だけ再発行・再送する。
    private func post(_ method: String, body: [String: Any], isRetry: Bool = false) async throws -> Data {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: Self.baseURL + method)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, status) = try await send(request)
        switch status {
        case 200:
            return data
        case 401 where !isRetry:
            accessToken = nil
            return try await post(method, body: body, isRetry: true)
        case 401:
            throw DomainError.geminiUnauthorized
        default:
            throw DomainError.geminiHTTP(status: status)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DomainError.network("Invalid response")
            }
            return (data, http.statusCode)
        } catch let err as DomainError {
            throw err
        } catch {
            throw DomainError.network(error.localizedDescription)
        }
    }

    // MARK: - OAuth

    private func validAccessToken() async throws -> String {
        if let accessToken, accessToken.expiresAt > Date().addingTimeInterval(60) {
            return accessToken.value
        }
        let refreshToken = try readRefreshToken()

        // キャッシュ済みのクライアントで失敗したら、バイナリから読み直して全組み合わせを試す。
        if let cached = clientCredentials {
            if let token = try await refresh(refreshToken, with: cached) { return token }
            clientCredentials = nil
        }
        for candidate in Self.extractClientCredentials(home: home) {
            if let token = try await refresh(refreshToken, with: candidate) {
                clientCredentials = candidate
                return token
            }
        }
        throw DomainError.geminiUnauthorized
    }

    /// 成功時はトークンを返す。クライアント不一致や失効など OAuth 側の拒否は nil。
    private func refresh(_ refreshToken: String, with client: ClientCredentials) async throws -> String? {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": client.id,
            "client_secret": client.secret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        let (data, status) = try await send(request)
        guard status == 200,
              let dto = try? JSONDecoder().decode(TokenResponseDTO.self, from: data) else {
            return nil
        }
        accessToken = (dto.accessToken, Date().addingTimeInterval(TimeInterval(dto.expiresIn ?? 3600)))
        return dto.accessToken
    }

    private func readRefreshToken() throws -> String {
        let url = URL(fileURLWithPath: home).appendingPathComponent(".gemini/jetski-standalone-oauth-token")
        guard let data = try? Data(contentsOf: url) else {
            throw DomainError.geminiNotLoggedIn
        }
        guard let file = try? JSONDecoder().decode(TokenFileDTO.self, from: data),
              let token = file.token?.refreshToken, !token.isEmpty else {
            throw DomainError.geminiNotLoggedIn
        }
        return token
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    // MARK: - Client credential extraction

    struct ClientCredentials: Equatable, Sendable {
        let id: String
        let secret: String
    }

    private static func binaryCandidates(home: String) -> [String] {
        [
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/Applications/Antigravity.app/Contents/Resources/bin/language_server",
            "/Applications/Antigravity IDE.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
        ]
    }

    /// 最初に見つかったバイナリから、クライアント ID とシークレットの全組み合わせを返す。
    /// どの ID とどのシークレットが対になるかはバイナリからは分からないため、
    /// 呼び出し側で順に試す（数件なので問題にならない）。
    private static func extractClientCredentials(home: String) -> [ClientCredentials] {
        let fm = FileManager.default
        for path in binaryCandidates(home: home) where fm.isReadableFile(atPath: path) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else {
                continue
            }
            let ids = scanClientIDs(in: data)
            let secrets = scanSecrets(in: data)
            let pairs = ids.flatMap { id in secrets.map { ClientCredentials(id: id, secret: $0) } }
            if !pairs.isEmpty { return pairs }
        }
        return []
    }

    /// `<数字>-<小文字英数字 32 文字>.apps.googleusercontent.com` を抜き出す。
    ///
    /// Go バイナリは文字列を区切りなしで連結して格納しているため、前後の文字種では境界が
    /// 決まらない（実際 `...divide it1071006060591-...` のように英字が直前に来る）。
    /// 固定長の 32 文字部分から逆算し、数字部分だけ遡る。
    private static func scanClientIDs(in data: Data) -> [String] {
        let suffix = Array(".apps.googleusercontent.com".utf8)
        let hashLength = 32
        var found: [String] = []
        forEachMatch(of: suffix, in: data) { bytes, offset in
            let hashStart = offset - hashLength
            guard hashStart > 1,
                  bytes[hashStart..<offset].allSatisfy(isLowerAlnumByte),
                  bytes[hashStart - 1] == UInt8(ascii: "-") else { return }
            var numberStart = hashStart - 1
            while numberStart > 0, hashStart - 1 - numberStart < 14, isDigitByte(bytes[numberStart - 1]) {
                numberStart -= 1
            }
            guard numberStart < hashStart - 1 else { return }
            let id = String(decoding: bytes[numberStart..<offset], as: UTF8.self) + ".apps.googleusercontent.com"
            if !found.contains(id) { found.append(id) }
        }
        return found
    }

    /// `GOCSPX-` に続く 28 文字を抜き出す（後ろには次の文字列が連結されているので固定長で切る）。
    private static func scanSecrets(in data: Data) -> [String] {
        let prefix = Array("GOCSPX-".utf8)
        let bodyLength = 28
        var found: [String] = []
        forEachMatch(of: prefix, in: data) { bytes, offset in
            let start = offset + prefix.count
            guard start + bodyLength <= bytes.count else { return }
            let body = bytes[start..<(start + bodyLength)]
            guard body.allSatisfy(isSecretByte) else { return }
            let secret = "GOCSPX-" + String(decoding: body, as: UTF8.self)
            if !found.contains(secret) { found.append(secret) }
        }
        return found
    }

    private static func forEachMatch(
        of needle: [UInt8],
        in data: Data,
        _ body: (UnsafeBufferPointer<UInt8>, Int) -> Void
    ) {
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                guard let hit = memmem(base + offset, bytes.count - offset, needle, needle.count) else { break }
                let index = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                body(bytes, index)
                offset = index + needle.count
            }
        }
    }

    private static func isDigitByte(_ b: UInt8) -> Bool {
        b >= 0x30 && b <= 0x39
    }

    private static func isLowerAlnumByte(_ b: UInt8) -> Bool {
        isDigitByte(b) || (b >= 0x61 && b <= 0x7A)
    }

    private static func isSecretByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2D || b == 0x5F
    }
}

// MARK: - DTOs

private struct TokenFileDTO: Decodable {
    let token: Token?

    struct Token: Decodable {
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }
}

private struct TokenResponseDTO: Decodable {
    let accessToken: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct LoadCodeAssistDTO: Decodable {
    let cloudaicompanionProject: ProjectRef?
    let currentTier: Tier?
    let paidTier: Tier?

    struct Tier: Decodable {
        let id: String?
        let name: String?
    }

    /// 文字列で返る場合と `{ "id": ... }` で返る場合の両方を受ける。
    struct ProjectRef: Decodable {
        let id: String

        private enum CodingKeys: String, CodingKey { case id }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer().decode(String.self) {
                id = single
            } else {
                id = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
            }
        }
    }
}

/// `fetchAvailableModels` のレスポンス（使う部分だけ）。
///
/// ```json
/// {
///   "models": {
///     "gemini-3.1-pro-high": {
///       "displayName": "Gemini 3.1 Pro (High)",
///       "modelProvider": "MODEL_PROVIDER_GOOGLE",
///       "quotaInfo": { "remainingFraction": 1, "resetTime": "2026-10-02T10:55:00Z" }
///     }
///   },
///   "agentModelSorts": [{ "groups": [{ "modelIds": ["gemini-3.1-pro-high", ...] }] }]
/// }
/// ```
struct AntigravityModelsDTO: Decodable, Sendable {
    let models: [String: Model]?
    let agentModelSorts: [Sort]?

    struct Model: Decodable, Sendable {
        let displayName: String?
        let modelProvider: String?
        let quotaInfo: QuotaInfo?
    }

    struct QuotaInfo: Decodable, Sendable {
        /// proto3 JSON は 0 を省略するため、resetTime があってこれが無い場合は使い切り扱い。
        let remainingFraction: Double?
        let resetTime: String?
    }

    struct Sort: Decodable, Sendable {
        let groups: [Group]?

        struct Group: Decodable, Sendable {
            let modelIds: [String]?
        }
    }
}
