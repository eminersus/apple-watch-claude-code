//
//  ContentView.swift
//  Main screen: pick a live Claude Code session, dictate/type a prompt, send it.
//
//  Tapping the prompt field on watchOS opens the standard input panel
//  (Dictation / Scribble / keyboard), so voice input is built in for free.
//

import SwiftUI

struct ContentView: View {
    @AppStorage(SettingsKey.baseURL)    private var baseURL = ""
    @AppStorage(SettingsKey.token)      private var token = ""
    @AppStorage(SettingsKey.submit)     private var submit = true
    @AppStorage(SettingsKey.target)     private var selectedTarget = ""
    @AppStorage(SettingsKey.targetName) private var selectedName = ""

    @State private var prompt = ""
    @State private var showSettings = false
    @State private var sending = false
    @State private var status: Status?

    // A few one-tap prompts. Edit to taste.
    private let presets = ["continue", "run the tests", "what's the status?", "commit and push", "yes"]

    private var hasConfig: Bool { !baseURL.isEmpty && !token.isEmpty }
    private var hasTarget: Bool { !selectedTarget.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {

                    // Which session am I sending to? Tap to choose/refresh.
                    NavigationLink {
                        SessionsView()
                    } label: {
                        HStack {
                            Image(systemName: "terminal.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Session").font(.caption2).foregroundStyle(.secondary)
                                Text(hasTarget ? selectedName : "Tap to choose")
                                    .font(.footnote).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)

                    // Prompt entry — tap to dictate or type.
                    // Tapping opens the watchOS input panel: Dictation (voice),
                    // Scribble, and keyboard. The globe key switches input
                    // language (e.g. English ⇄ Türkçe) — dictation follows it.
                    TextField("Tap to dictate or type…", text: $prompt, axis: .vertical)
                        .lineLimit(1...4)
                        .submitLabel(.send)
                        .onSubmit(send)

                    Text("Tap → 🎙 Dictate / ⌨︎ type. Globe key = EN ⇄ TR.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: send) {
                        HStack {
                            if sending { ProgressView() }
                            Image(systemName: "arrow.up.message.fill")
                            Text(sending ? "Sending…" : "Send")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sending || prompt.trimmingCharacters(in: .whitespaces).isEmpty)

                    DisclosureGroup("Quick prompts") {
                        ForEach(presets, id: \.self) { p in
                            Button(p) { prompt = p; send() }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if let status { StatusBanner(status: status) }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Claude")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear { if !hasConfig { showSettings = true } }
        }
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        guard hasConfig else { status = .failure("Set URL & token in Settings."); showSettings = true; return }
        guard hasTarget else { status = .failure("Choose a session first."); return }

        sending = true; status = nil
        let client = BridgeClient(baseURL: baseURL, token: token)
        let target = selectedTarget
        let doSubmit = submit
        Task {
            do {
                let submitted = try await client.send(prompt: text, target: target, submit: doSubmit)
                await MainActor.run {
                    sending = false
                    status = .success(submitted ? "Sent to \(selectedName) ✓"
                                                 : "Typed (not submitted)")
                    prompt = ""
                }
            } catch {
                await MainActor.run { sending = false; status = .failure(error.localizedDescription) }
            }
        }
    }
}

// MARK: - Status banner

enum Status {
    case success(String)
    case failure(String)
}

struct StatusBanner: View {
    let status: Status
    var body: some View {
        switch status {
        case .success(let msg): banner(msg, "checkmark.circle.fill", .green)
        case .failure(let msg): banner(msg, "exclamationmark.triangle.fill", .orange)
        }
    }
    private func banner(_ msg: String, _ system: String, _ color: Color) -> some View {
        Label(msg, systemImage: system)
            .font(.footnote).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview { ContentView() }
