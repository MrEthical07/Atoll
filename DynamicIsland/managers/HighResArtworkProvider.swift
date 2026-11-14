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

import AppKit
import Foundation

/// Looks up a high-resolution copy of the current track's cover art for use as a
/// full-screen wallpaper.
///
/// Now-playing sources usually expose only ~300–640 px artwork. That is fine for
/// the lock-screen panel, but stretched across a Retina display it turns into a
/// soft, pixelated wallpaper. The iTunes catalog serves the same covers at up to
/// 3000×3000, so we ask it for one sized to the screen.
actor HighResArtworkProvider {
    static let shared = HighResArtworkProvider()

    private struct SearchResponse: Decodable {
        let results: [Track]
    }

    private struct Track: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
    }

    private static let maximumPixelSide = 3000

    // Only the most recent lookup is cached: the wallpaper refreshes for the
    // current track repeatedly, while older tracks rarely come back.
    private var lastKey: String?
    private var lastImageData: Data?

    /// Returns encoded cover art at least `minimumPixelSide` pixels square (capped
    /// at 3000), or `nil` when no confident match exists. A wrong cover is worse than
    /// a soft one, so this never falls back to an unrelated search result.
    ///
    /// Tried in order: a larger variant of the URL the source app itself used
    /// (Spotify, YouTube Music), then the iTunes catalog by track metadata, then the
    /// catalog again with the video-style title cleaned up (browser tabs).
    func artwork(
        title: String,
        artist: String,
        album: String,
        sourceArtworkURL: URL?,
        minimumPixelSide: Int
    ) async -> Data? {
        let key = "\(title)|\(artist)|\(album)|\(sourceArtworkURL?.absoluteString ?? "")|\(minimumPixelSide)"
        if key == lastKey { return lastImageData }

        // The warm-up and the wallpaper request often ask for the same track at the same
        // moment. Share one lookup instead of downloading the cover twice. The shared task
        // is separate from either caller, so a caller's timeout doesn't cancel it.
        if let pending = inFlight[key] { return await pending.value }
        let task = Task {
            await self.resolve(
                title: title, artist: artist, album: album,
                sourceArtworkURL: sourceArtworkURL, minimumPixelSide: minimumPixelSide
            )
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        lastKey = key
        lastImageData = result
        return result
    }

    private var inFlight: [String: Task<Data?, Never>] = [:]

    private func resolve(
        title: String,
        artist: String,
        album: String,
        sourceArtworkURL: URL?,
        minimumPixelSide: Int
    ) async -> Data? {
        let side = min(max(minimumPixelSide, 1000), Self.maximumPixelSide)

        var imageData: Data?
        if let sourceArtworkURL {
            for candidate in Self.largerVariants(of: sourceArtworkURL, side: side) {
                if let data = await download(candidate) {
                    print("[HighResArtworkProvider] using larger source cover \(candidate.absoluteString)")
                    imageData = data
                    break
                }
            }
        }
        if imageData == nil {
            imageData = await fetchFromCatalog(title: title, artist: artist, album: album, side: side)
        }
        if imageData == nil, let cleaned = Self.cleanedVideoTitle(title), cleaned.query != title {
            imageData = await fetchFromCatalog(cleanedTitle: cleaned, side: side)
        }

        return imageData
    }

    // MARK: - Source-provided URLs

    /// Larger versions of a cover URL, best first. Unknown hosts return nothing.
    private static func largerVariants(of url: URL, side: Int) -> [URL] {
        let string = url.absoluteString
        var variants: [String] = []

        if url.host?.hasSuffix("scdn.co") == true,
           let range = string.range(of: "ab67616d0000[0-9a-f]{4}", options: .regularExpression) {
            // Spotify: the 16-character prefix of the image ID selects the size.
            // 82c1 is the original upload, b273 is 640 px.
            for prefix in ["ab67616d000082c1", "ab67616d0000b273"] {
                variants.append(string.replacingCharacters(in: range, with: prefix))
            }
        } else if let host = url.host,
                  host.hasSuffix("googleusercontent.com") || host.hasSuffix("ggpht.com") {
            // Google image hosts take the size as a "=w600-h600..." suffix.
            let base = string.replacingOccurrences(of: "=[ws]\\d+.*$", with: "", options: .regularExpression)
            variants.append("\(base)=w\(side)-h\(side)-l90-rj")
        } else if url.host == "i.ytimg.com" || url.host == "img.youtube.com" {
            variants.append(string.replacingOccurrences(
                of: "/[a-z0-9_]+\\.(jpg|webp)", with: "/maxresdefault.jpg", options: .regularExpression
            ))
        }

        return variants.compactMap(URL.init(string:))
    }

    private func download(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard NSImage(data: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - iTunes catalog

    private func fetchFromCatalog(title: String, artist: String, album: String, side: Int) async -> Data? {
        guard let searchURL = makeAppleMusicCatalogSearchURL(query: "\(title) \(artist)"),
              let results = await search(searchURL)
        else { return nil }

        let normalizedTitle = title.lowercased()
        let normalizedAlbum = album.lowercased()
        let normalizedArtist = artist.lowercased()

        let match = results.first(where: {
            $0.trackName?.lowercased() == normalizedTitle
                && $0.collectionName?.lowercased() == normalizedAlbum
        }) ?? results.first(where: {
            !normalizedAlbum.isEmpty && $0.collectionName?.lowercased() == normalizedAlbum
        }) ?? results.first(where: {
            $0.trackName?.lowercased() == normalizedTitle
                && ($0.artistName?.lowercased().contains(normalizedArtist) ?? false)
        }) ?? results.first(where: {
            // Streaming apps often tag editions differently ("Album (Deluxe)"),
            // so accept a containing album name when the artist also agrees.
            guard !normalizedAlbum.isEmpty, let collection = $0.collectionName?.lowercased() else { return false }
            return (collection.contains(normalizedAlbum) || normalizedAlbum.contains(collection))
                && ($0.artistName?.lowercased().contains(normalizedArtist) ?? false)
        })

        guard let thumbnailURL = match?.artworkUrl100 else {
            print("[HighResArtworkProvider] no catalog match for '\(title)' by '\(artist)' (\(results.count) results)")
            return nil
        }
        return await downloadCatalogCover(thumbnailURL, side: side, title: title)
    }

    /// Browser tabs report video titles ("Song - Film - Full Video | Credits"). Search
    /// with the cleaned name, and only accept a result whose track name is the song part
    /// and whose album contains another part of the title (the film or album name).
    private func fetchFromCatalog(cleanedTitle: (query: String, parts: [String]), side: Int) async -> Data? {
        guard let searchURL = makeAppleMusicCatalogSearchURL(query: cleanedTitle.query),
              let results = await search(searchURL),
              let song = cleanedTitle.parts.first
        else { return nil }

        let others = cleanedTitle.parts.dropFirst().map(Self.squash).filter { !$0.isEmpty }
        let match = results.first(where: { track in
            guard let name = track.trackName, Self.squash(name) == Self.squash(song),
                  let collection = track.collectionName.map(Self.squash)
            else { return false }
            return others.contains(where: { collection.contains($0) })
        })

        guard let thumbnailURL = match?.artworkUrl100 else {
            print("[HighResArtworkProvider] no confident catalog match for cleaned title '\(cleanedTitle.query)'")
            return nil
        }
        return await downloadCatalogCover(thumbnailURL, side: side, title: cleanedTitle.query)
    }

    private func search(_ url: URL) async -> [Track]? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(SearchResponse.self, from: data).results
        } catch {
            print("[HighResArtworkProvider] lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func downloadCatalogCover(_ thumbnailURL: String, side: Int, title: String) async -> Data? {
        let highResURLString = thumbnailURL.replacingOccurrences(of: "100x100", with: "\(side)x\(side)")
        guard let highResURL = URL(string: highResURLString),
              let data = await download(highResURL),
              let image = NSImage(data: data)
        else { return nil }
        print("[HighResArtworkProvider] fetched \(Int(image.atollPixelSize.width))px cover for '\(title)'")
        return data
    }

    // MARK: - Title cleanup

    /// Lowercased with everything but letters and digits removed, so "ABCD 2" == "ABCD2".
    private static func squash(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Strips video-title noise: everything after "|", bracketed "(Official Video)" style
    /// tags, and trailing "- Full Video" style segments. Returns the search query and
    /// the remaining " - " separated parts, or nil if nothing useful is left.
    private static func cleanedVideoTitle(_ title: String) -> (query: String, parts: [String])? {
        var text = title.components(separatedBy: "|").first ?? title
        let noise = "official|video|audio|lyric|lyrics|full|song|hd|4k|remaster(ed)?|music"
        text = text.replacingOccurrences(
            of: "[\\(\\[][^\\)\\]]*(\(noise))[^\\)\\]]*[\\)\\]]",
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        var parts = text.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        while let last = parts.last, parts.count > 1,
              last.range(of: "^((\(noise))\\s*)+$", options: [.regularExpression, .caseInsensitive]) != nil {
            parts.removeLast()
        }
        guard !parts.isEmpty else { return nil }
        return (parts.joined(separator: " "), parts)
    }
}

extension NSImage {
    /// The image's size in actual pixels (largest bitmap representation), as
    /// opposed to `size`, which is in points.
    var atollPixelSize: CGSize {
        let bitmapSizes = representations
            .filter { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
            .map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
        return bitmapSizes.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? size
    }
}
