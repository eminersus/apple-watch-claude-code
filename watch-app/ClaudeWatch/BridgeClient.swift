//
//  BridgeClient.swift
//  Talks to the Claude Watch Bridge (GET /sessions, POST /prompt).
//

import Foundation

/// One running terminal session reported by the bridge.
struct BridgeSession: Identifiable, Hashable {
    let target: String        // tmux target, e.g. "trading:0.0" — the id we send back
    let session: String
    let windowName: String
    let path: String
    let command: String
    let active: Bool
    let claudeLike: Bool

    var id: String { target }

    /// Last path component, for a compact label ("…/prediction-market-bot").
    var shortPath: String {
        (path as NSString).lastPathComponent
    }

    /// Best human label for the row.
    var displayName: String {
        let name = session.isEmpty ? target : session
        return shortPath.isEmpty ? name : "\(name) · \(shortPath)"
    }
}

enum BridgeError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int, String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Set the bridge URL and token in Settings first."
        case .badURL:        return "The bridge URL is not valid."
        case .http(let code, let msg): return "Server \(code): \(msg)"
        case .transport(let msg):      return msg
        }
    }
}

struct BridgeClient {
    let baseURL: String
    let token: String

    private func makeURL(_ pathComponent: String) throws -> URL {
        let b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty, !token.isEmpty else { throw BridgeError.notConfigured }
        let root = b.hasSuffix("/") ? String(b.dropLast()) : b
        guard let url = URL(string: root + pathComponent) else { throw BridgeError.badURL }
        return url
    }

    private func authed(_ url: URL, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func run(_ req: URLRequest) async throws -> [String: Any] {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw BridgeError.transport(error.localizedDescription)
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BridgeError.http(http.statusCode, json["error"] as? String ?? "request failed")
        }
        return json
    }

    /// GET /sessions — every running terminal session, Claude-looking ones first.
    func listSessions() async throws -> [BridgeSession] {
        let json = try await run(authed(try makeURL("/sessions"), method: "GET"))
        let raw = json["sessions"] as? [[String: Any]] ?? []
        return raw.map { d in
            BridgeSession(
                target: d["target"] as? String ?? "",
                session: d["session"] as? String ?? "",
                windowName: d["window_name"] as? String ?? "",
                path: d["path"] as? String ?? "",
                command: d["command"] as? String ?? "",
                active: d["active"] as? Bool ?? false,
                claudeLike: d["claude_like"] as? Bool ?? false
            )
        }
    }

    /// POST /prompt — type `prompt` into the chosen session.
    @discardableResult
    func send(prompt: String, target: String, submit: Bool) async throws -> Bool {
        var body: [String: Any] = ["prompt": prompt, "submit": submit]
        if !target.isEmpty { body["target"] = target }
        let data = try JSONSerialization.data(withJSONObject: body)
        let json = try await run(authed(try makeURL("/prompt"), method: "POST", body: data))
        return json["submitted"] as? Bool ?? false
    }
}
