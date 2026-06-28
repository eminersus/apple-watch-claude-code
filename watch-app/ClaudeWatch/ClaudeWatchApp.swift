//
//  ClaudeWatchApp.swift
//  ClaudeWatch — send prompts from your Apple Watch to Claude Code.
//
//  Entry point. Coral tint + dark scheme are applied app-wide here.
//

import SwiftUI

@main
struct ClaudeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}
