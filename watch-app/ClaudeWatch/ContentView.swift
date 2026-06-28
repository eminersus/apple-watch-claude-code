//
//  ContentView.swift
//  Compose a prompt (dictate or type) and send it to the chosen Claude Code session.
//
//  Tapping the prompt field opens the watchOS input panel (Dictation / Scribble /
//  keyboard), so voice input is built in. The globe key switches input language.
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
    @State private var status: Banner?
    @FocusState private var promptFocused: Bool

    /// One-tap prompts. `label` is what shows on the chip; `text` is what's sent.
    private let presets: [(label: String, text: String)] = [
        ("Continue",      "continue"),
        ("Yes",           "yes"),
        ("Run tests",     "run the tests"),
        ("Status",        "what's the status?"),
        ("Commit & push", "commit and push"),
        ("Undo",          "undo that"),
    ]

    private var hasConfig: Bool { !baseURL.isEmpty && !token.isEmpty }
    private var hasTarget: Bool { !selectedTarget.isEmpty }
    private var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        sessionChip
                        composer
                        sendButton
                        quickPrompts
                        if let status {
                            BannerView(banner: status)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("Claude")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear { if !hasConfig { showSettings = true } }
        }
    }

    // MARK: - Pieces

    private var sessionChip: some View {
        NavigationLink { SessionsView() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(hasTarget ? Theme.accent.opacity(0.20) : Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)
                    Image(systemName: hasTarget ? "sparkles" : "terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hasTarget ? Theme.accent : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(hasTarget ? "SESSION" : "NO SESSION")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(hasTarget ? selectedName : "Tap to choose")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                Text("PROMPT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !prompt.isEmpty {
                    Button { withAnimation { prompt = "" } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Dictate or type…", text: $prompt, axis: .vertical)
                .focused($promptFocused)
                .lineLimit(1...6)
                .submitLabel(.send)
                .onSubmit(send)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(promptFocused ? Theme.accent.opacity(0.7) : Theme.cardStroke,
                        lineWidth: promptFocused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: promptFocused)
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: 7) {
                if sending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(sending ? "Sending…" : "Send")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(sending || trimmed.isEmpty)
        .opacity(trimmed.isEmpty ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.15), value: trimmed.isEmpty)
    }

    private var quickPrompts: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("QUICK")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6),
                                GridItem(.flexible(), spacing: 6)],
                      spacing: 6) {
                ForEach(presets, id: \.label) { p in
                    Button {
                        prompt = p.text
                        send()
                    } label: {
                        Text(p.label)
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
        }
    }

    // MARK: - Send

    private func send() {
        let text = trimmed
        guard !text.isEmpty, !sending else { return }
        guard hasConfig else {
            Haptics.failure()
            withAnimation { status = .failure("Set URL & token in Settings.") }
            showSettings = true
            return
        }
        guard hasTarget else {
            Haptics.failure()
            withAnimation { status = .failure("Choose a session first.") }
            return
        }

        sending = true
        withAnimation { status = nil }
        Haptics.tap()

        let client = BridgeClient(baseURL: baseURL, token: token)
        let target = selectedTarget
        let doSubmit = submit
        let name = selectedName
        Task {
            do {
                let submitted = try await client.send(prompt: text, target: target, submit: doSubmit)
                await MainActor.run {
                    sending = false
                    Haptics.success()
                    withAnimation {
                        status = .success(submitted ? "Sent to \(name)" : "Typed (not submitted)")
                    }
                    prompt = ""
                    promptFocused = false
                }
            } catch {
                await MainActor.run {
                    sending = false
                    Haptics.failure()
                    withAnimation { status = .failure(error.localizedDescription) }
                }
            }
        }
    }
}

#Preview { ContentView() }
