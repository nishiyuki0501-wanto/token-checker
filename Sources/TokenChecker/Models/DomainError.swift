import Foundation

enum DomainError: Error, Equatable, LocalizedError, Sendable {
    case keychainTokenMissing
    case anthropicUnauthorized
    case anthropicRateLimited(retryAfter: TimeInterval?)
    case anthropicHTTP(status: Int)
    case codexCLINotFound
    case codexProcessExited
    case codexRPCError(message: String)
    case geminiNotLoggedIn
    case geminiClientNotFound
    case geminiUnauthorized
    case geminiHTTP(status: Int)
    case cursorNotLoggedIn
    case cursorTokenExpired
    case cursorHTTP(status: Int)
    case decoding(String)
    case timeout
    case network(String)

    /// そもそもそのサービスを使っていない（未インストール・未ログイン）ことを示すエラー。
    /// メニューバーではこの場合に項目ごと隠す。
    var isNotConfigured: Bool {
        switch self {
        case .geminiNotLoggedIn, .geminiClientNotFound, .cursorNotLoggedIn: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .keychainTokenMissing:
            return "Claude Code の OAuth トークンが Keychain に見つかりません。ターミナルで `claude login` を実行してください。"
        case .anthropicUnauthorized:
            return "Anthropic からの認証エラー (401)。`claude login` で再ログインしてください。"
        case .anthropicRateLimited(let retryAfter):
            if let sec = retryAfter {
                let mins = max(1, Int((sec / 60).rounded()))
                return "Anthropic API のレート制限に達しました。約 \(mins) 分後に自動で再試行します。"
            }
            return "Anthropic API のレート制限 (429)。次回ポーリングまで待機します。"
        case .anthropicHTTP(let status):
            return "Anthropic API エラー (status \(status))"
        case .codexCLINotFound:
            return "Codex CLI が見つかりません。`npm i -g @openai/codex` を実行してください。"
        case .codexProcessExited:
            return "codex app-server が終了しました。再起動を試みます。"
        case .codexRPCError(let message):
            return "Codex RPC エラー: \(message)"
        case .geminiNotLoggedIn:
            return "Antigravity のログイン情報が見つかりません。ターミナルで `agy` を起動してログインしてください。"
        case .geminiClientNotFound:
            return "Antigravity CLI (agy) が見つかりません。トークン更新に必要です。"
        case .geminiUnauthorized:
            return "Antigravity の認証が切れています。`agy` を起動して再ログインしてください。"
        case .geminiHTTP(let status):
            return "Antigravity API エラー (status \(status))"
        case .cursorNotLoggedIn:
            return "Cursor のログイン情報が見つかりません。Cursor を起動してログインしてください。"
        case .cursorTokenExpired:
            return "Cursor のトークンが期限切れです。Cursor を起動すると自動で更新されます。"
        case .cursorHTTP(let status):
            return "Cursor API エラー (status \(status))"
        case .decoding(let detail):
            return "レスポンスのデコードに失敗: \(detail)"
        case .timeout:
            return "通信がタイムアウトしました。"
        case .network(let detail):
            return "ネットワークエラー: \(detail)"
        }
    }
}
