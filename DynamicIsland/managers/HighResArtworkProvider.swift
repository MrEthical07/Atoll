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
import ImageIO

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

    /// Covers are fetched for every track so the wallpaper can use one instantly, then dropped
    /// after five minutes. Each entry is the encoded image (typically 1-3 MB), never a decoded
    /// bitmap. Failed lookups are remembered only briefly so a network hiccup can be retried.
    private struct CacheEntry {
        let data: Data?
        let expires: Date
    }
    private static let successLifetime: TimeInterval = 300
    private static let failureLifetime: TimeInterval = 30
    private static let maximumEntries = 6
    private var cache: [String: CacheEntry] = [:]
    private var evictionTask: Task<Void, Never>?

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
        // Album is left out of the key: it is often filled in a moment after playback starts,
        // and including it would make the warm-up and the later request miss each other.
        let key = "\(title)|\(artist)|\(sourceArtworkURL?.absoluteString ?? "")|\(minimumPixelSide)"
        evictExpiredEntries()
        if let entry = cache[key] { return entry.data }

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
        store(result, forKey: key)
        return result
    }

    private func store(_ data: Data?, forKey key: String) {
        let lifetime = data == nil ? Self.failureLifetime : Self.successLifetime
        cache[key] = CacheEntry(data: data, expires: Date().addingTimeInterval(lifetime))
        // Keep the newest few; a long session of short tracks must not accumulate covers.
        if cache.count > Self.maximumEntries {
            let oldest = cache.sorted { $0.value.expires < $1.value.expires }
            for (staleKey, _) in oldest.prefix(cache.count - Self.maximumEntries) { cache[staleKey] = nil }
        }
        scheduleEviction()
    }

    private func evictExpiredEntries() {
        let now = Date()
        cache = cache.filter { $0.value.expires > now }
    }

    /// Frees the covers even when no further request arrives to trigger a cleanup.
    private func scheduleEviction() {
        guard evictionTask == nil else { return }
        evictionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.successLifetime))
            await self?.finishEviction()
        }
    }

    private func finishEviction() {
        evictionTask = nil
        evictExpiredEntries()
        if !cache.isEmpty { scheduleEviction() }
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
            guard Self.pixelWidth(of: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Reads the width from the image header without decoding the pixels (a 3000 px cover
    /// would otherwise briefly cost ~36 MB just to check that it is a picture).
    private static func pixelWidth(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyPixelWidth] as? Int
    }

    // MARK: - iTunes catalog

    private func fetchFromCatalog(title: String, artist: String, album: String, side: Int) async -> Data? {
        let baseTitle = Self.baseTitle(title)
        let artists = Self.artistTokens(artist)
        // Several credited artists make a poor search term; the song and the first one do better.
        let query = [baseTitle, artists.first ?? ""].filter { !$0.isEmpty }.joined(separator: " ")

        // The user's own storefront first (regional releases often exist only there), then the default.
        let regions: [String?] = [Locale.current.region?.identifier, nil]
        // Second query is the bare title: a track credited to several people is often filed
        // under a different one first, and the album/artist checks below keep it safe.
        var queries = [query]
        if !baseTitle.isEmpty, baseTitle != query { queries.append(baseTitle) }

        var totalResults = 0
        for query in queries {
            for region in regions {
                guard var components = makeAppleMusicCatalogSearchURL(query: query)
                    .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { continue }
                if let region { components.queryItems?.append(URLQueryItem(name: "country", value: region)) }
                guard let searchURL = components.url, let results = await search(searchURL) else { continue }
                totalResults += results.count

                if let thumbnailURL = Self.bestMatch(in: results, title: title, artist: artist, album: album)?.artworkUrl100 {
                    return await downloadCatalogCover(thumbnailURL, side: side, title: title)
                }
            }
        }
        print("[HighResArtworkProvider] no catalog match for '\(title)' by '\(artist)' (\(totalResults) results)")
        return nil
    }

    /// Picks the result that is the same song. Titles are compared without bracketed tags
    /// ("(From \"Film\")", "(feat. X)") and punctuation, and a credited artist only has to
    /// overlap with one of the result's, since services list collaborators differently.
    private static func bestMatch(in results: [Track], title: String, artist: String, album: String) -> Track? {
        let wantedTitle = squash(baseTitle(title))
        let wantedAlbum = squash(baseTitle(album))
        let wantedArtists = artistTokens(artist).map(squash).filter { !$0.isEmpty }

        func artistsAgree(_ track: Track) -> Bool {
            guard let name = track.artistName.map(squash), !wantedArtists.isEmpty else { return false }
            return wantedArtists.contains { name.contains($0) || ($0.contains(name) && !name.isEmpty) }
        }
        func albumsAgree(_ track: Track) -> Bool {
            guard !wantedAlbum.isEmpty, let collection = track.collectionName.map({ squash(baseTitle($0)) }),
                  !collection.isEmpty else { return false }
            return collection == wantedAlbum || collection.contains(wantedAlbum) || wantedAlbum.contains(collection)
        }
        func titleAgrees(_ track: Track) -> Bool {
            track.trackName.map { squash(baseTitle($0)) == wantedTitle } ?? false
        }

        return results.first(where: { titleAgrees($0) && albumsAgree($0) && artistsAgree($0) })
            ?? results.first(where: { titleAgrees($0) && artistsAgree($0) })
            ?? results.first(where: { titleAgrees($0) && albumsAgree($0) })
            ?? results.first(where: { albumsAgree($0) && artistsAgree($0) })
    }

    /// The title without bracketed tags and without a trailing " - Remix"-style suffix.
    private static func baseTitle(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\\([^)]*\\)|\\[[^\\]]*\\]", with: "", options: .regularExpression)
        if let dash = result.range(of: " - ") { result = String(result[..<dash.lowerBound]) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "A, B and C" / "A & B feat. C" -> ["A", "B", "C"].
    private static func artistTokens(_ artist: String) -> [String] {
        artist
            .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
            .replacingOccurrences(of: " & ", with: ",")
            .replacingOccurrences(of: " feat. ", with: ",", options: .caseInsensitive)
            .replacingOccurrences(of: " ft. ", with: ",", options: .caseInsensitive)
            .replacingOccurrences(of: " x ", with: ",", options: .caseInsensitive)
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
              let width = Self.pixelWidth(of: data)
        else { return nil }
        print("[HighResArtworkProvider] fetched \(width)px cover for '\(title)'")
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
