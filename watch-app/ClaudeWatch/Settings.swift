//
//  Settings.swift
//  Persisted connection settings.
//
//  Stored in UserDefaults via @AppStorage so they survive app restarts.
//  The token is a bearer secret for a service that only lives inside your
//  private Tailscale network.
//

import Foundation

/// AppStorage keys in one place.
enum SettingsKey {
    static let baseURL    = "baseURL"        // e.g. https://mac.tailnet.ts.net
    static let token      = "token"          // bearer token shared with the bridge
    static let submit     = "submit"         // press Enter after typing the prompt
    static let target     = "selectedTarget" // tmux target of the chosen session
    static let targetName = "selectedName"   // human label for the chosen session
}
