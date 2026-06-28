//
//  SessionsView.swift
//  Pick which live Claude Code session a prompt goes to.
//
//  Claude-looking sessions are flagged (✨) and sorted to the top by the bridge.
//

import SwiftUI

struct SessionsView: View {
    @AppStorage(SettingsKey.baseURL)    private var baseURL = ""
    @AppStorage(SettingsKey.token)      private var token = ""
    @AppStorage(SettingsKey.target)     private var selectedTarget = ""
    @AppStorage(SettingsKey.targetName) private var selectedName = ""

    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [BridgeSession] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if loading && sessions.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading sessions…")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else if let error {
            centeredMessage(
                symbol: "wifi.exclamationmark", tint: Theme.danger,
                title: "Can't reach the bridge", detail: error, showRetry: true
            )
        } else if sessions.isEmpty {
            centeredMessage(
                symbol: "terminal", tint: .secondary,
                title: "No sessions running",
                detail: "On your Mac:\ntmux new -s work\nthen run  claude", showRetry: true
            )
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sessions) { sessionRow($0) }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
            .refreshable { await load() }
        }
    }

    private func sessionRow(_ s: BridgeSession) -> some View {
        let isSelected = s.target == selectedTarget
        return Button {
            selectedTarget = s.target
            selectedName = s.displayName
            Haptics.success()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(s.claudeLike ? Theme.accent.opacity(0.20) : Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)
                    Image(systemName: s.claudeLike ? "sparkles" : "terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(s.claudeLike ? Theme.accent : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.session.isEmpty ? s.target : s.session)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(s.shortPath.isEmpty ? s.target : s.shortPath)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                } else if s.active {
                    Circle().fill(Theme.success).frame(width: 7, height: 7)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Theme.accent.opacity(0.12) : Theme.card,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func centeredMessage(symbol: String, tint: Color,
                                 title: String, detail: String, showRetry: Bool) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if showRetry {
                    Button { Task { await load() } } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let list = try await BridgeClient(baseURL: baseURL, token: token).listSessions()
            withAnimation { sessions = list }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview { SessionsView() }
