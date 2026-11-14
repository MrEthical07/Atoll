/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// Asks the YouTube Music desktop app's API server for the current song's cover URL.
///
/// Lets the sharp-cover lookup work while "Now Playing" is the selected source, which only
/// reports a small image and no link to a bigger one. It never changes which source the
/// notch uses, and it stays silent when the app or its API Server plugin isn't available.
actor YouTubeMusicCoverLookup {
    static let shared = YouTubeMusicCoverLookup()
    static let bundleIdentifier = YouTubeMusicConfiguration.default.bundleIdentifier

    private let client = YouTubeMusicHTTPClient(baseURL: YouTubeMusicConfiguration.default.baseURL)
    private var token: String?
    /// After a failure (server off, not approved) don't ask again straight away.
    private var retryNotBefore = Date.distantPast

    /// The cover URL for the song the app is playing, or `nil` if it isn't `title`
    /// (the system's view and the app's can differ for a moment around a track change).
    func coverURL(forTitle title: String) async -> URL? {
        guard Date() >= retryNotBefore else { return nil }
        do {
            let info = try await playbackInfo()
            guard let source = info.imageSrc, let url = URL(string: source) else { return nil }
            if let reported = info.title, !title.isEmpty, !Self.sameSong(reported, title) { return nil }
            return url
        } catch {
            token = nil
            retryNotBefore = Date().addingTimeInterval(30)
            return nil
        }
    }

    /// Sends a transport command (play, pause, next, ...) to the app. Used when the notch shows
    /// YouTube Music but macOS would send a system command to a different player.
    func send(_ endpoint: String, body: (any Codable & Sendable)? = nil) async -> Bool {
        do {
            let current = try await currentToken()
            _ = try await client.sendCommand(endpoint: endpoint, method: "POST", body: body, token: current)
            return true
        } catch {
            token = nil
            return false
        }
    }

    private func currentToken() async throws -> String {
        if let token { return token }
        let fresh = try await client.authenticate()
        token = fresh
        return fresh
    }

    private func playbackInfo() async throws -> PlaybackResponse {
        let current = try await currentToken()
        do {
            return try await client.getPlaybackInfo(token: current)
        } catch YouTubeMusicError.authenticationRequired {
            let fresh = try await client.authenticate()
            token = fresh
            return try await client.getPlaybackInfo(token: fresh)
        }
    }

    private static func sameSong(_ lhs: String, _ rhs: String) -> Bool {
        func squash(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let a = squash(lhs), b = squash(rhs)
        return !a.isEmpty && !b.isEmpty && (a == b || a.contains(b) || b.contains(a))
    }
}
