import SwiftUI
import AppKit

/// メニューバーに表示する「看板猫 + 各サービスの使用率」。
///
/// SwiftUI ビューを `ImageRenderer` で NSImage に焼いて、
/// `Image(nsImage:)` でメニューバーに渡す。
/// `MenuBarExtra` の label に SwiftUI ビューを直接渡すとフォント等が制限されるため。
///
/// 幅が広すぎるとノッチに掛かり、macOS がステータス項目ごと非表示にしてしまう。
/// そのためサービスごとのアイコンは出さず、猫 1 匹 + 数字の並び（ポップオーバーと同じ順）に詰める。
struct MenuBarLabel: View {
    let viewModel: UsageViewModel
    @AppStorage(CatCharacter.storageKey) private var cat: CatCharacter = .default

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
        } else {
            Image(systemName: "pawprint")
        }
    }

    private var renderedImage: NSImage? {
        let snapshot = viewModel.snapshot
        let entries = snapshot.menuBarEntries
        let mood = snapshot.worstUtilization.map { CatMood(utilization: $0) }
        let content = HStack(spacing: 4) {
            CatMascot(character: cat, size: 16, mood: mood, tint: .white, useImage: false)
            HStack(spacing: 1) {
                ForEach(entries.indices, id: \.self) { index in
                    if index > 0 {
                        Text("·").opacity(0.55)
                    }
                    Text(percentLabel(utilization(from: entries[index].result)))
                }
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 2)
        .foregroundStyle(Color.white)

        let renderer = ImageRenderer(content: content)
        // ビットマップは高 DPI で焼いておく．image.size には触らない
        // （触ると point 単位として誤認されて表示サイズまで縮んでしまう）．
        let maxScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        renderer.scale = max(maxScale, 3)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    private func utilization(from result: Result<ServiceUsage, DomainError>?) -> Double? {
        guard case .success(let usage) = result else { return nil }
        return usage.headline?.utilization
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        // メニューバーは横幅が限られるため "%" を省き、100 で頭打ちにして超過は "+" で示す。
        // RateLimit.utilization は仕様上 1.0 を超えうる（Anthropic API 既知挙動）。
        if v > 1.0 { return "100+" }
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))"
    }
}
