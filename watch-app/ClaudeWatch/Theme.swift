//
//  Theme.swift
//  Shared design system: palette, background, haptics, and reusable views.
//
//  One place for the app's look so every screen stays consistent.
//

import SwiftUI
import WatchKit

// MARK: - Palette

enum Theme {
    /// Claude's warm coral — the app's signature accent.
    static let accent       = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let accentBright  = Color(red: 0.97, green: 0.59, blue: 0.43)
    static let success       = Color(red: 0.36, green: 0.80, blue: 0.55)
    static let danger        = Color(red: 0.96, green: 0.52, blue: 0.34)

    static let card          = Color.white.opacity(0.085)
    static let cardStroke    = Color.white.opacity(0.10)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentBright, accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Background

/// Pure-black (OLED-friendly) with a soft coral glow up top.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Theme.accent.opacity(0.28), .clear],
                           center: .top, startRadius: 0, endRadius: 170)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap()     { WKInterfaceDevice.current().play(.click) }
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func failure() { WKInterfaceDevice.current().play(.failure) }
}

// MARK: - Reusable styles

/// Compact translucent pill used for the quick-prompt buttons.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(configuration.isPressed ? 0.20 : 0.09), in: Capsule())
            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Feedback banner

/// A small, colour-coded result message (used for send results & connection tests).
enum Banner: Equatable {
    case success(String)
    case failure(String)
    case info(String)

    var text: String {
        switch self {
        case .success(let s), .failure(let s), .info(let s): return s
        }
    }
    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .success: return Theme.success
        case .failure: return Theme.danger
        case .info:    return Theme.accent
        }
    }
}

struct BannerView: View {
    let banner: Banner
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: banner.symbol)
            Text(banner.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(banner.color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(banner.color.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
