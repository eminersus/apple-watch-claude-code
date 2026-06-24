//
//  SettingsView.swift
//  Enter the bridge URL + token, and how prompts are submitted.
//
//  Typing a long token on a watch is painful — set these once on your iPhone in
//  the paired "Claude" app (Watch app data syncs), or use the token Shortcut
//  trick in docs/SETUP.md.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.baseURL) private var baseURL = ""
    @AppStorage(SettingsKey.token)   private var token = ""
    @AppStorage(SettingsKey.submit)  private var submit = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Bridge") {
                    TextField("https://mac.tailnet.ts.net", text: $baseURL)
                        .textContentType(.URL)
                    TextField("Bearer token", text: $token)
                }
                Section("Sending") {
                    Toggle("Press Enter to submit", isOn: $submit)
                    Text("Off = the prompt is typed into the session but not sent, so you can review it on your Mac before hitting Return.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section {
                    Text("URL is your Mac's Tailscale name (from `tailscale serve`). Token must match the bridge's config.json.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview { SettingsView() }
