//
//  SettingsView.swift
//  Bridge URL, token, submit behaviour — plus a one-tap connection test.
//
//  Typing a long token on a watch is painful: paste it via Handoff (type it in
//  Notes on your Mac, copy on the watch, paste here) — see docs/SETUP.md.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.baseURL) private var baseURL = ""
    @AppStorage(SettingsKey.token)   private var token = ""
    @AppStorage(SettingsKey.submit)  private var submit = true

    @State private var testing = false
    @State private var testResult: Banner?

    private var canTest: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty && !testing
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        urlField
                        tokenField
                        testRow
                        submitCard
                        Text("URL is your Mac's Tailscale name (tailscale serve) or http://<LAN-ip>:8787. Token must match the bridge's config.json.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)
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

    // MARK: - Fields

    private var urlField: some View {
        fieldCard(title: "BRIDGE URL", systemImage: "link") {
            TextField("https://mac.tailnet.ts.net", text: $baseURL)
                .textContentType(.URL)
        } onClear: { baseURL = "" } isEmpty: { baseURL.isEmpty }
    }

    private var tokenField: some View {
        fieldCard(title: "TOKEN", systemImage: "key.fill") {
            TextField("Bearer token", text: $token)
        } onClear: { token = "" } isEmpty: { token.isEmpty }
    }

    private func fieldCard<Field: View>(
        title: String, systemImage: String,
        @ViewBuilder field: () -> Field,
        onClear: @escaping () -> Void,
        isEmpty: () -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2).foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !isEmpty() {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            field()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Test connection

    private var testRow: some View {
        VStack(spacing: 8) {
            Button(action: test) {
                HStack(spacing: 6) {
                    if testing { ProgressView().tint(.white) }
                    else { Image(systemName: "bolt.horizontal.fill") }
                    Text(testing ? "Testing…" : "Test connection").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!canTest)
            .opacity(canTest ? 1 : 0.45)

            if let testResult {
                BannerView(banner: testResult)
                    .transition(.opacity)
            }
        }
    }

    private func test() {
        testing = true
        withAnimation { testResult = nil }
        let client = BridgeClient(baseURL: baseURL, token: token)
        Task {
            do {
                let list = try await client.listSessions()
                await MainActor.run {
                    testing = false
                    Haptics.success()
                    let n = list.count
                    withAnimation { testResult = .success("Connected · \(n) session\(n == 1 ? "" : "s")") }
                }
            } catch {
                await MainActor.run {
                    testing = false
                    Haptics.failure()
                    withAnimation { testResult = .failure(error.localizedDescription) }
                }
            }
        }
    }

    // MARK: - Submit toggle

    private var submitCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $submit) {
                Label("Press Enter to submit", systemImage: "return")
                    .font(.footnote)
            }
            .tint(Theme.accent)
            Text("Off = the prompt is typed into the session but not sent, so you can review it on your Mac before hitting Return.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview { SettingsView() }
