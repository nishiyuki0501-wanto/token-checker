import SwiftUI
import AppKit

struct UsagePopoverView: View {
    @Bindable var viewModel: UsageViewModel
    @ObservedObject var launchAtLogin: LaunchAtLoginStore
    @AppStorage(CatCharacter.storageKey) private var cat: CatCharacter = .default

    private var mood: CatMood? {
        viewModel.snapshot.worstUtilization.map { CatMood(utilization: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            card {
                ServiceSectionView(
                    title: "Claude Code",
                    brand: .claude,
                    result: viewModel.snapshot.claude,
                    loginAction: { viewModel.openClaudeLogin() }
                )
            }
            card {
                ServiceSectionView(
                    title: "Codex",
                    brand: .codex,
                    result: viewModel.snapshot.codex,
                    loginAction: { viewModel.openCodexLogin() }
                )
            }
            card {
                ServiceSectionView(
                    title: "Gemini",
                    brand: .gemini,
                    result: viewModel.snapshot.gemini,
                    loginAction: { viewModel.openGeminiLogin() }
                )
            }
            card {
                ServiceSectionView(
                    title: "Cursor",
                    brand: .cursor,
                    result: viewModel.snapshot.cursor,
                    loginAction: { viewModel.openCursorLogin() }
                )
            }

            card { settingsBlock }
            footer
        }
        .padding(14)
        .frame(width: 320)
        // 白ベース。ダークモードでも白地に濃い文字で揃える。
        .background(Theme.background)
        .environment(\.colorScheme, .light)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 10) {
            CatMascot(character: cat, size: 34, mood: mood, tint: Color(white: 0.3))
                .frame(width: 44, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("にゃんこのスタミナ")
                    .font(.system(size: 14, weight: .semibold))
                Text(mood?.headline ?? "ようすを見てくるにゃ…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("うちの子をえらぶ")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            CatPickerView(selection: $cat, mood: mood)
            Text(menuBarLegend)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)

            HStack {
                Text("見回りの間隔")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $viewModel.pollingInterval) {
                    ForEach(PollingInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            HStack {
                Text("Mac といっしょに起きる")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { _ in launchAtLogin.toggle() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    /// メニューバーの数字がどのサービスかの説明。
    private var menuBarLegend: String {
        let names = viewModel.snapshot.menuBarEntries.map(\.name)
        return "メニューバーの数字: " + names.joined(separator: " → ")
    }

    private var footer: some View {
        HStack {
            if viewModel.snapshot.fetchedAt > .distantPast {
                HStack(spacing: 3) {
                    Image(systemName: "pawprint.fill")
                    Text("\(DateFormatter.localizedString(from: viewModel.snapshot.fetchedAt, dateStyle: .none, timeStyle: .short)) に見回ったにゃ")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "pawprint.circle")
                }
            }
            .buttonStyle(.borderless)
            .help("今すぐ見回る（更新）")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("おやすみ", systemImage: "moon.zzz")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("アプリを終了")
        }
    }
}
