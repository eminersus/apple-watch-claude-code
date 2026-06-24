//
//  SessionsView.swift
//  Lists the live terminal sessions from the bridge and lets you pick one.
//
//  Claude-looking sessions are flagged and sorted to the top by the bridge.
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
        List {
            if loading {
                HStack { ProgressView(); Text("Loading…") }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.footnote)
            }
            if !loading && error == nil && sessions.isEmpty {
                Text("No tmux sessions found. Start one:\n  tmux new -s work\nthen run  claude  inside it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(sessions) { s in
                Button {
                    selectedTarget = s.target
                    selectedName = s.displayName
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if s.claudeLike {
                                    Image(systemName: "sparkles").foregroundStyle(.purple)
                                }
                                Text(s.session).font(.headline)
                            }
                            Text(s.shortPath.isEmpty ? s.target : s.shortPath)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if s.target == selectedTarget {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            sessions = try await BridgeClient(baseURL: baseURL, token: token).listSessions()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview { SessionsView() }
