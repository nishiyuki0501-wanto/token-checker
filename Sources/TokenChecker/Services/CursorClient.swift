import Foundation
import SQLite3

/// Cursor の請求サイクル内の使用率を取得する。
///
/// Cursor (IDE) はログイン中のアクセストークンを VS Code 系の state DB
/// (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`) に保存している。
/// これを読み取り専用で開いて取り出し、ダッシュボードと同じ `GetCurrentPeriodUsage` を叩く。
/// トークンの再発行は Cursor 本体に任せる（起動中なら自動で更新される）。
struct CursorClient: Sendable {
    static let usageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )!

    private static let session = NoRedirectDelegate.makeSession()
    private let databasePath: String

    init(home: String = NSHomeDirectory()) {
        databasePath = "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    struct Credentials: Sendable {
        let accessToken: String
        let membershipType: String?
    }

    func readCredentials() throws -> Credentials {
        guard FileManager.default.isReadableFile(atPath: databasePath) else {
            throw DomainError.cursorNotLoggedIn
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw DomainError.cursorNotLoggedIn
        }
        defer { sqlite3_close(db) }
        // Cursor が書き込み中でも少し待てば読めるようにする
        sqlite3_busy_timeout(db, 1000)

        guard let token = Self.value(forKey: "cursorAuth/accessToken", in: db), !token.isEmpty else {
            throw DomainError.cursorNotLoggedIn
        }
        if let exp = Self.jwtExpiry(token), exp < Date() {
            throw DomainError.cursorTokenExpired
        }
        return Credentials(
            accessToken: token,
            membershipType: Self.value(forKey: "cursorAuth/stripeMembershipType", in: db)
        )
    }

    func fetch(accessToken: String) async throws -> CursorUsageDTO {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw DomainError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DomainError.network("Invalid response")
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw DomainError.cursorTokenExpired
        default:
            throw DomainError.cursorHTTP(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(CursorUsageDTO.self, from: data)
        } catch {
            throw DomainError.decoding("Cursor usage: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func value(forKey key: String, in db: OpaquePointer?) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        // SQLITE_TRANSIENT 相当: バインド後に Swift 側の文字列が解放されても安全なようコピーさせる
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(stmt, 0) else {
            return nil
        }
        let length = Int(sqlite3_column_bytes(stmt, 0))
        let data = Data(bytes: bytes, count: length)
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// JWT の payload から `exp` を読む。署名は検証しない（期限切れの事前判定にだけ使う）。
    private static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - DTO

/// `GetCurrentPeriodUsage` のレスポンス（使う部分だけ）。
///
/// ```json
/// {
///   "billingCycleStart": "1790676416000",
///   "billingCycleEnd": "1793268416000",
///   "planUsage": {
///     "remaining": 2000, "limit": 2000,
///     "autoPercentUsed": 0, "apiPercentUsed": 0, "totalPercentUsed": 0
///   }
/// }
/// ```
/// - int64 は Connect の JSON 表現で文字列になる（epoch ミリ秒）
/// - `*PercentUsed` は 0〜100
struct CursorUsageDTO: Decodable, Sendable {
    let billingCycleEnd: FlexibleNumber?
    let planUsage: PlanUsage?

    struct PlanUsage: Decodable, Sendable {
        let limit: Double?
        let remaining: Double?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
        let totalPercentUsed: Double?
    }

    /// 文字列でも数値でも受ける数値。
    struct FlexibleNumber: Decodable, Sendable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else if let parsed = Double(try container.decode(String.self)) {
                value = parsed
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a number")
            }
        }
    }
}
