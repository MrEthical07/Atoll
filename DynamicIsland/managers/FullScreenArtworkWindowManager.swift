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
import AVFoundation
import Combine
import CoreImage
import Defaults
import SkyLightWindow
import SwiftUI

// MARK: - Click Receiver Window

private class ClickReceiverWindow: NSWindow {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Keep left click inert so the fallback only dismisses on right click.
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class LoopingVideoView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func play(url: URL) {
        stop()

        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.backgroundColor = NSColor.clear.cgColor

        self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.layer?.addSublayer(layer)

        playerLayer = layer
        queuePlayer = player
        playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        playerLooper = nil
        queuePlayer = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }

    func pause() {
        queuePlayer?.pause()
    }

    func resume() {
        queuePlayer?.play()
    }
}

private final class WallpaperTransitionImageView: NSView {
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(imageLayer)
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func updateImage(_ image: NSImage) {
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

private final class SpotifyCanvasFallbackArtworkOverlayView: NSView {
    var onDismiss: (() -> Void)?

    private let imageLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var artwork: NSImage

    init(artwork: NSImage) {
        self.artwork = artwork
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.34).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 26
        layer?.shadowOffset = CGSize(width: 0, height: -22)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        imageLayer.contents = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        borderLayer.lineWidth = 1.1

        layer?.addSublayer(imageLayer)
        layer?.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()

        let radius = cornerRadius
        imageLayer.frame = bounds
        imageLayer.cornerRadius = radius
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.55, dy: 0.55),
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDismiss?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismiss?()
    }

    func updateArtwork(_ artwork: NSImage) {
        self.artwork = artwork
        imageLayer.contents = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)
        needsLayout = true
    }

    private var aspectRatio: CGFloat {
        let height = max(artwork.size.height, 1)
        return artwork.size.width / height
    }

    private var cornerRadius: CGFloat {
        aspectRatio > 1 ? 16 : 34
    }
}

private struct FullScreenLyricsOverlayContent: View {
    let text: String
    let fontSize: CGFloat

    private var isPlaceholder: Bool {
        text == "Loading lyrics..." || text == "No lyrics found"
    }

    var body: some View {
        VStack {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(isPlaceholder ? 0.72 : 0.94))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 6)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

private struct SpotifyCanvasFallbackLayoutFrames {
    let artworkFrame: NSRect
    let panelFrame: NSRect
    let groupFrame: NSRect
    let lyricsFrame: NSRect?
}

// MARK: - Window Manager

@MainActor
final class FullScreenArtworkWindowManager: ObservableObject {
    private enum ArtworkOverlayMode {
        case none
        case spotifyFallback
    }

    static let shared = FullScreenArtworkWindowManager()

    @Published private(set) var isShowing = false
    @Published private(set) var isShowingSpotifyCanvasFallback = false
    var onDismiss: (() -> Void)?

    private let wallpaperPlistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }()
    private let backupPlistURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_wallpaper_backup.plist")
    }()
    private let aerialManifestURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json")
    }()
    private let aerialVideosDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
    }()
    private let aerialThumbnailsDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails", isDirectory: true)
    }()
    private let customLiveWallpaperAssetID = "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7"
    private let liveWallpaperManifestBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_manifest_backup.json")
    }()
    private let liveWallpaperVideoBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_video_backup.mov")
    }()
    private let liveWallpaperThumbnailBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_thumbnail_backup.png")
    }()
    private var artworkFileURL: URL?
    private var tempCleanupTask: Task<Void, Never>?
    /// Wallpaper image rendered ahead of time for a track, keyed by track and screen size.
    private var prerenderedWallpaper: (trackKey: String, pixelKey: String, url: URL)?
    private static let tempFilePrefix = "atoll_artwork_wallpaper"
    private static let tempFileLifetime: TimeInterval = 300
    private var cachedArtworkPNG: URL?
    private var cachedArtworkFingerprint: String?
    private var cachedBlurredArtworkPNG: URL?
    private var cachedBlurredArtworkFingerprint: String?
    private var cachedBlurredArtworkPixelSize: CGSize = .zero
    private var cachedFilledArtworkPNG: URL?
    private var cachedFilledArtworkKey: String?
    private var highResArtwork: (trackKey: String, image: NSImage)?
    /// Model-upscaled stand-in used only when no sharper cover could be found online.
    private var upscaledArtwork: (trackKey: String, image: NSImage)?
    private var highResArtworkTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var activeSongTitle: String?
    private var activeArtist: String?
    private var trackChangeCancellable: AnyCancellable?
    private var artworkCacheCancellable: AnyCancellable?
    private var videoArtworkCancellable: AnyCancellable?
    private var playbackStateCancellable: AnyCancellable?
    private var hasSuspendedWallpaperAgent = false
    private var appTerminationObserver: NSObjectProtocol?
    private var clickWindow: ClickReceiverWindow?
    private var clickWindowDelegated = false
    private var videoWindow: NSWindow?
    private var videoView: LoopingVideoView?
    private var activeVideoWindowURL: URL?
    private var videoWindowHideTask: Task<Void, Never>?
    private var artworkOverlayWindow: NSWindow?
    private var artworkOverlayWindowDelegated = false
    private var lyricsOverlayWindow: NSWindow?
    private var lyricsOverlayWindowDelegated = false
    private var currentArtworkOverlayMode: ArtworkOverlayMode = .none
    private var wallpaperTransitionWindow: NSWindow?
    private var wallpaperTransitionView: WallpaperTransitionImageView?
    private var wallpaperTransitionHideTask: Task<Void, Never>?
    private var panelFrameChangeObserver: NSObjectProtocol?
    private var liveWallpaperTask: Task<Void, Never>?
    private var deferredTrackRefreshTask: Task<Void, Never>?
    private var isLiveWallpaperAllowed = false
    private var activeLiveWallpaperFingerprint: String?
    private var activeWallpaperKey: String?
    private var pendingFallbackStaticURL: URL?
    private var pendingFallbackWallpaperKey: String?
    private var fallbackRightClickMonitor: Any?
    private var artworkLayoutOverCanvasPreferenceCancellable: AnyCancellable?
    private var lyricsTextCancellable: AnyCancellable?
    private var lyricsPreferenceCancellable: AnyCancellable?
    private let spotifyCanvasFallbackHorizontalMargin: CGFloat = 48

    private init() {
        // Leftovers from a previous run (crash, force quit) are never in use.
        pruneArtworkTempFiles(olderThan: 0)
        observeArtworkChanges()
        observeVideoArtworkChanges()
        observePanelFrameChanges()
        observeArtworkLayoutOverCanvasPreference()
        observeLyricsChanges()
        observeLyricsPreference()
        observePlaybackStateChanges()
        observeAppTermination()
    }

    /// Applies the cover as the wallpaper without a click, for the sources the user enabled.
    /// Skips quietly unless a sharp cover is found for the track.
    func autoApplyIfEligible() {
        guard !isShowing, presentationTask == nil else { return }
        let music = MusicManager.shared
        guard music.hasActiveSession else { return }
        guard isAutoWallpaperEnabled(forBundleIdentifier: music.bundleIdentifier) else {
            // No automatic wallpaper, but a right-click may come: have the sharp cover ready.
            if Defaults[.lockScreenMusicFullscreenArtworkEnabled] { warmUpHighResArtwork() }
            return
        }
        show(artwork: music.albumArt, videoURL: nil, allowLiveWallpaper: false, requireSharpCover: true)
    }

    /// Whether anything can use the sharp cover: right-click fullscreen artwork or an automatic source.
    private var isWallpaperFeatureEnabled: Bool {
        Defaults[.lockScreenMusicFullscreenArtworkEnabled]
            || Defaults[.lockScreenAutoWallpaperAppleMusic]
            || Defaults[.lockScreenAutoWallpaperSpotify]
            || Defaults[.lockScreenAutoWallpaperYouTubeMusic]
    }

    private func isAutoWallpaperEnabled(forBundleIdentifier bundleIdentifier: String?) -> Bool {
        switch bundleIdentifier {
        case "com.apple.Music": return Defaults[.lockScreenAutoWallpaperAppleMusic]
        case "com.spotify.client": return Defaults[.lockScreenAutoWallpaperSpotify]
        case "com.github.th-ch.youtube-music": return Defaults[.lockScreenAutoWallpaperYouTubeMusic]
        default: return false
        }
    }

    func show(
        artwork: NSImage,
        videoURL: URL? = nil,
        allowLiveWallpaper: Bool = false,
        requireSharpCover: Bool = false
    ) {
        guard !isShowing, presentationTask == nil else { return }
        guard let screen = NSScreen.main else { return }

        // The now-playing artwork is usually only a few hundred pixels wide. Give the
        // sharp catalog cover a moment to arrive so the wallpaper is applied once with
        // the best image, instead of being set from the small one first.
        presentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prefetchHighResArtwork(on: screen, timeout: requireSharpCover ? .seconds(15) : .milliseconds(600), requireSharp: requireSharpCover)
            guard !Task.isCancelled else { return }
            self.presentationTask = nil
            if requireSharpCover, self.highResArtwork?.trackKey != self.currentTrackKey {
                print("[FullScreenArtworkWindowManager] auto wallpaper skipped: no sharp cover for this track")
                return
            }
            self.applyPresentation(
                artwork: artwork,
                videoURL: videoURL,
                allowLiveWallpaper: allowLiveWallpaper,
                on: screen,
                backupWallpaperConfiguration: true
            )
            self.observeTrackChanges()
        }
    }

    func hide() {
        let wasPreparing = presentationTask != nil
        presentationTask?.cancel()
        presentationTask = nil
        if wasPreparing, !isShowing {
            // Dismissed while still waiting for the cover; nothing was applied yet.
            let callback = onDismiss
            onDismiss = nil
            callback?()
            return
        }
        guard isShowing else { return }
        resumeWallpaperAgentIfNeeded()
        isShowing = false
        isLiveWallpaperAllowed = false
        activeLiveWallpaperFingerprint = nil
        activeWallpaperKey = nil
        pendingFallbackStaticURL = nil
        pendingFallbackWallpaperKey = nil
        let shouldRestoreStandardPanelLayout = isShowingSpotifyCanvasFallback
        isShowingSpotifyCanvasFallback = false
        removeFallbackRightClickMonitor()
        trackChangeCancellable?.cancel()
        trackChangeCancellable = nil
        liveWallpaperTask?.cancel()
        liveWallpaperTask = nil
        deferredTrackRefreshTask?.cancel()
        deferredTrackRefreshTask = nil
        highResArtworkTask?.cancel()
        highResArtworkTask = nil

        hideVideoWindow()
        hideArtworkOverlay()
        hideLyricsOverlay()
        hideWallpaperTransition()
        hideClickReceiver()
        if shouldRestoreStandardPanelLayout, LockScreenManager.shared.isLocked {
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: true)
        }
        restoreWallpaper()

        activeSongTitle = nil
        activeArtist = nil

        let callback = onDismiss
        onDismiss = nil
        callback?()

        scheduleArtworkTempCleanup()

        print("[FullScreenArtworkWindowManager] Original wallpaper restored")
    }

    // MARK: - Artwork Pre-Cache

    private func observeArtworkChanges() {
        artworkCacheCancellable = MusicManager.shared.$albumArt
            .debounce(for: .milliseconds(180), scheduler: DispatchQueue.main)
            .sink { [weak self] newArt in
                guard let self else { return }
                // Fetch the sharp cover for every track (it is cached for five minutes), so
                // the wallpaper can be applied the moment it is asked for.
                if self.isWallpaperFeatureEnabled { self.warmUpHighResArtwork() }
                // Encoding the PNG is wasted work while the lock screen isn't up; the
                // wallpaper path builds what it needs on demand.
                guard self.isShowing || LockScreenManager.shared.isLocked else { return }
                guard let fingerprint = self.imageFingerprint(for: newArt) else { return }
                guard fingerprint != self.cachedArtworkFingerprint else { return }
                let url = self.artworkCacheFileURL(for: fingerprint)
                Task.detached(priority: .utility) {
                    guard let pngData = self.encodeToPNG(newArt) else { return }
                    try? pngData.write(to: url, options: .atomic)
                    await MainActor.run {
                        self.cachedArtworkPNG = url
                        self.cachedArtworkFingerprint = fingerprint
                        self.scheduleArtworkTempCleanup()
                        if self.isShowing {
                            self.refreshPresentationForCurrentTrack()
                        }
                    }
                }
            }
    }

    private func observeVideoArtworkChanges() {
        videoArtworkCancellable = MusicManager.shared.$videoArtworkURL
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing, self.isLiveWallpaperAllowed else { return }
                self.refreshPresentationForCurrentTrack()
            }
    }

    private func observePlaybackStateChanges() {
        playbackStateCancellable = MusicManager.shared.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.applyCanvasPlaybackState(isPlaying: isPlaying)
            }
    }

    private static let wallpaperRenderProcessNames: [String] = [
        "WallpaperAgent",
        "WallpaperAerialsExtension",
        "WallpaperVideoExtension",
        "wallpaperexportd"
    ]

    private func applyCanvasPlaybackState(isPlaying: Bool) {
        if let videoView, videoWindow != nil {
            if isPlaying {
                videoView.resume()
            } else {
                videoView.pause()
            }
        }

        let canSuspend = isShowing && isLiveWallpaperAllowed && activeLiveWallpaperFingerprint != nil
        print("[FullScreenArtworkWindowManager] playback state -> isPlaying=\(isPlaying) showing=\(isShowing) liveAllowed=\(isLiveWallpaperAllowed) fingerprint=\(activeLiveWallpaperFingerprint ?? "nil")")

        if isPlaying {
            resumeWallpaperAgentIfNeeded()
        } else if canSuspend {
            suspendWallpaperAgent()
        }
    }

    private func suspendWallpaperAgent() {
        guard !hasSuspendedWallpaperAgent else { return }
        var anySucceeded = false
        for name in Self.wallpaperRenderProcessNames {
            if signalProcess(name: name, signalFlag: "-STOP") {
                anySucceeded = true
            }
        }
        hasSuspendedWallpaperAgent = anySucceeded
        print("[FullScreenArtworkWindowManager] SIGSTOP wallpaper processes -> anySucceeded=\(anySucceeded)")
    }

    private func resumeWallpaperAgentIfNeeded() {
        guard hasSuspendedWallpaperAgent else { return }
        for name in Self.wallpaperRenderProcessNames {
            _ = signalProcess(name: name, signalFlag: "-CONT")
        }
        hasSuspendedWallpaperAgent = false
        print("[FullScreenArtworkWindowManager] SIGCONT wallpaper processes")
    }

    @discardableResult
    private func signalProcess(name: String, signalFlag: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [signalFlag, name]
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("[FullScreenArtworkWindowManager] killall \(signalFlag) \(name) threw: \(error)")
            return false
        }
    }

    private func observeAppTermination() {
        appTerminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeWallpaperAgentIfNeeded()
        }
    }

    private func applyPresentation(
        artwork: NSImage,
        videoURL: URL?,
        allowLiveWallpaper: Bool,
        on screen: NSScreen,
        backupWallpaperConfiguration: Bool
    ) {
        let artwork = preferredArtwork(fallback: artwork)
        let artworkID = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
        guard let artworkFingerprint = imageFingerprint(for: artwork) else { return }
        isLiveWallpaperAllowed = allowLiveWallpaper
        let shouldUseStaticFallbackWallpaper = shouldUseSpotifyStaticFallbackWallpaper(videoURL: videoURL)
        let shouldUseFallbackLayout = shouldUseSpotifyFallbackLayout(videoURL: videoURL)
        let effectiveVideoURL = resolvedVideoURL(videoURL: videoURL)
        let overlayMode = artworkOverlayMode(shouldUseFallbackLayout: shouldUseFallbackLayout)
        let previousFallbackState = isShowingSpotifyCanvasFallback

        let expectCanvas = effectiveVideoURL != nil
        let needsFallbackWallpaper = shouldUseStaticFallbackWallpaper || expectCanvas

        // Build only the image the wallpaper actually uses. Each of these is a full-size
        // render plus a PNG encode, and doing all three took seconds on the main thread.
        let blurredFallbackURL: URL?
        let wallpaperURL: URL
        if needsFallbackWallpaper {
            guard let url = blurredWallpaperFileURL(for: artwork, fingerprint: artworkFingerprint, screen: screen)
                ?? persistedArtworkFileURL(for: artwork, fingerprint: artworkFingerprint)
            else { return }
            blurredFallbackURL = url
            wallpaperURL = url
        } else {
            // Rendered at the display's native pixel size with a high-quality filter instead
            // of handing macOS a small square to stretch. Usually already prepared in the
            // background when the track started.
            guard let url = filledWallpaperFileURL(for: artwork, fingerprint: artworkFingerprint, screen: screen)
                ?? persistedArtworkFileURL(for: artwork, fingerprint: artworkFingerprint)
            else { return }
            blurredFallbackURL = nil
            wallpaperURL = url
        }
        let wallpaperKey = wallpaperIdentityKey(
            fingerprint: artworkFingerprint,
            usesFallback: shouldUseStaticFallbackWallpaper || expectCanvas,
            screen: screen
        )
        let desiredLiveWallpaperFingerprint = effectiveVideoURL?.absoluteString
        let requiresWallpaperRefresh = backupWallpaperConfiguration
            || activeWallpaperKey != wallpaperKey
            || activeLiveWallpaperFingerprint != desiredLiveWallpaperFingerprint

        artworkFileURL = wallpaperURL

        if backupWallpaperConfiguration {
            backupWallpaperConfig()
        }

        if requiresWallpaperRefresh {
            if expectCanvas {
                pendingFallbackStaticURL = blurredFallbackURL ?? wallpaperURL
                pendingFallbackWallpaperKey = wallpaperKey
                activeWallpaperKey = nil
                activeLiveWallpaperFingerprint = nil
            } else {
                showWallpaperTransition(on: screen, imageURL: wallpaperURL)

                guard applyArtworkToPlist(imageURL: wallpaperURL) else {
                    print("[FullScreenArtworkWindowManager] Failed to patch plist")
                    hideWallpaperTransition()
                    return
                }

                restartWallpaperAgent()
                activeWallpaperKey = wallpaperKey
                activeLiveWallpaperFingerprint = nil
                pendingFallbackStaticURL = nil
                pendingFallbackWallpaperKey = nil
            }
        }

        isShowing = true
        isShowingSpotifyCanvasFallback = shouldUseFallbackLayout
        activeSongTitle = MusicManager.shared.songTitle
        activeArtist = MusicManager.shared.artistName

        if overlayMode == .spotifyFallback {
            installFallbackRightClickMonitorIfNeeded()
        } else {
            removeFallbackRightClickMonitor()
        }

        if overlayMode == .none {
            hideArtworkOverlay()
        } else {
            showArtworkOverlay(on: screen, artwork: artwork, mode: overlayMode)
        }

        updateLyricsOverlayIfNeeded(on: screen)

        if previousFallbackState != shouldUseFallbackLayout, LockScreenManager.shared.isLocked {
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: true)
        }

        showClickReceiver(on: screen)
        scheduleLiveWallpaperPreparation(for: effectiveVideoURL, artwork: artwork, identifier: artworkID)

        if effectiveVideoURL == nil {
            hideVideoWindow()
            scheduleWallpaperTransitionHide(after: .milliseconds(900))
        }

        requestHighResArtworkIfNeeded(on: screen)

        print("[FullScreenArtworkWindowManager] Artwork applied as wallpaper")
    }

    // MARK: - High-resolution artwork

    private var currentTrackKey: String {
        // Title and artist only: the album field is often filled in a moment after the track
        // starts, which would make a lookup that began earlier look like it belongs to another song.
        "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
    }

    /// Uses the high-resolution cover for the current track once it has arrived.
    private func preferredArtwork(fallback: NSImage) -> NSImage {
        if let highResArtwork, highResArtwork.trackKey == currentTrackKey { return highResArtwork.image }
        if let upscaledArtwork, upscaledArtwork.trackKey == currentTrackKey { return upscaledArtwork.image }
        return fallback
    }

    /// Fetches a sharper cover for the current track in the background and
    /// re-applies the wallpaper when it arrives. Until then the existing artwork
    /// is shown, so the wallpaper never waits on the network.
    private func requestHighResArtworkIfNeeded(on screen: NSScreen) {
        let trackKey = currentTrackKey
        if highResArtwork?.trackKey == trackKey { return }

        let title = MusicManager.shared.songTitle
        let artist = MusicManager.shared.artistName
        let album = MusicManager.shared.album
        let knownSourceURL = MusicManager.shared.sourceArtworkURL
        let bundleIdentifier = MusicManager.shared.bundleIdentifier
        let targetPixelSize = wallpaperPixelSize(for: screen)
        let minimumPixelSide = Int(max(targetPixelSize.width, targetPixelSize.height).rounded())

        highResArtworkTask?.cancel()
        highResArtworkTask = Task { @MainActor [weak self] in
            let sourceArtworkURL = await Self.resolveSourceArtworkURL(
                known: knownSourceURL, bundleIdentifier: bundleIdentifier, title: title
            )
            guard let imageData = await HighResArtworkProvider.shared.artwork(
                title: title,
                artist: artist,
                album: album,
                sourceArtworkURL: sourceArtworkURL,
                minimumPixelSide: minimumPixelSide
            ), let image = NSImage(data: imageData) else { return }

            guard let self, !Task.isCancelled, self.isShowing, self.currentTrackKey == trackKey else { return }
            // Only swap if the catalog copy is actually sharper than what we have.
            guard image.atollPixelSize.width > MusicManager.shared.albumArt.atollPixelSize.width else {
                print("[FullScreenArtworkWindowManager] catalog cover not sharper than current art; keeping current")
                return
            }
            print("[FullScreenArtworkWindowManager] swapping in \(Int(image.atollPixelSize.width))px cover")

            self.highResArtwork = (trackKey, image)
            self.refreshPresentationForCurrentTrack()
        }
    }

    private func refreshPresentationForCurrentTrack() {
        guard isShowing else { return }
        guard MusicManager.shared.hasActiveSession else { return }
        guard let screen = NSScreen.main else { return }

        presentationTask?.cancel()
        presentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Same as the first apply: wait briefly for the sharp cover of the new track.
            await self.prefetchHighResArtwork(on: screen, timeout: .milliseconds(500))
            guard !Task.isCancelled, self.isShowing else { return }
            self.presentationTask = nil
            self.applyPresentation(
                artwork: MusicManager.shared.albumArt,
                videoURL: self.isLiveWallpaperAllowed ? MusicManager.shared.videoArtworkURL : nil,
                allowLiveWallpaper: self.isLiveWallpaperAllowed,
                on: screen,
                backupWallpaperConfiguration: false
            )
        }
    }

    /// The source app's own cover URL. With "Now Playing" selected there isn't one, so when the
    /// YouTube Music desktop app is the active source, ask its API server directly.
    private nonisolated static func resolveSourceArtworkURL(
        known: URL?,
        bundleIdentifier: String?,
        title: String
    ) async -> URL? {
        if let known { return known }
        guard bundleIdentifier == YouTubeMusicCoverLookup.bundleIdentifier else { return nil }
        return await YouTubeMusicCoverLookup.shared.coverURL(forTitle: title)
    }

    /// No sharper cover exists online, so enlarge the one we have with the on-device model.
    private func prepareUpscaledArtwork(trackKey: String, targetSide: Int) async {
        guard #available(macOS 26.0, *) else { return }
        if upscaledArtwork?.trackKey == trackKey { return }
        let current = MusicManager.shared.albumArt
        guard let upscaled = await ArtworkUpscaler.upscale(current, toward: targetSide, timeout: .milliseconds(900)),
              !Task.isCancelled, currentTrackKey == trackKey
        else { return }
        upscaledArtwork = (trackKey, upscaled)
    }

    /// Starts the sharp-cover lookup as soon as a track's artwork arrives, so by the time
    /// the wallpaper is requested the answer is already cached.
    private func warmUpHighResArtwork() {
        guard let screen = NSScreen.main else { return }
        let title = MusicManager.shared.songTitle
        let artist = MusicManager.shared.artistName
        let album = MusicManager.shared.album
        let knownSourceURL = MusicManager.shared.sourceArtworkURL
        let bundleIdentifier = MusicManager.shared.bundleIdentifier
        let trackKey = currentTrackKey
        let pixelSize = wallpaperPixelSize(for: screen)
        let minimumPixelSide = Int(max(pixelSize.width, pixelSize.height).rounded())
        Task.detached(priority: .utility) { [weak self] in
            let sourceArtworkURL = await Self.resolveSourceArtworkURL(
                known: knownSourceURL, bundleIdentifier: bundleIdentifier, title: title
            )
            let data = await HighResArtworkProvider.shared.artwork(
                title: title,
                artist: artist,
                album: album,
                sourceArtworkURL: sourceArtworkURL,
                minimumPixelSide: minimumPixelSide
            )
            guard let data, let self else { return }
            await self.prerenderFilledWallpaper(from: data, trackKey: trackKey, pixelSize: pixelSize)
        }
    }

    /// Renders the screen-sized wallpaper image for a fetched cover off the main thread, so
    /// applying it later is just a file swap.
    private func prerenderFilledWallpaper(from data: Data, trackKey: String, pixelSize: CGSize) async {
        let pixelKey = "\(Int(pixelSize.width.rounded()))x\(Int(pixelSize.height.rounded()))"
        if let existing = prerenderedWallpaper, existing.trackKey == trackKey, existing.pixelKey == pixelKey,
           FileManager.default.fileExists(atPath: existing.url.path) {
            return
        }

        let png: Data? = await Task.detached(priority: .utility) { [self] in
            autoreleasepool { self.encodeFilledWallpaperPNG(fromEncoded: data, targetPixelSize: pixelSize) }
        }.value
        guard let png, !isShowing else { return }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.tempFilePrefix)_filled_prerender_\(abs(trackKey.hashValue))_\(pixelKey).png")
        guard (try? png.write(to: fileURL, options: .atomic)) != nil else { return }
        prerenderedWallpaper = (trackKey, pixelKey, fileURL)
        scheduleArtworkTempCleanup()
        print("[FullScreenArtworkWindowManager] wallpaper image prepared in background")
    }

    /// Looks up the sharp cover for the current track and stores it when it beats the
    /// artwork we already have. Gives up after `timeout`; a late arrival is still picked
    /// up by `requestHighResArtworkIfNeeded`.
    private func prefetchHighResArtwork(on screen: NSScreen, timeout: Duration, requireSharp: Bool = false) async {
        let trackKey = currentTrackKey
        if highResArtwork?.trackKey == trackKey { return }

        let title = MusicManager.shared.songTitle
        let artist = MusicManager.shared.artistName
        let album = MusicManager.shared.album
        let knownSourceURL = MusicManager.shared.sourceArtworkURL
        let bundleIdentifier = MusicManager.shared.bundleIdentifier
        let targetPixelSize = wallpaperPixelSize(for: screen)
        let minimumPixelSide = Int(max(targetPixelSize.width, targetPixelSize.height).rounded())

        let imageData: Data? = await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                let sourceArtworkURL = await Self.resolveSourceArtworkURL(
                    known: knownSourceURL, bundleIdentifier: bundleIdentifier, title: title
                )
                return await HighResArtworkProvider.shared.artwork(
                    title: title,
                    artist: artist,
                    album: album,
                    sourceArtworkURL: sourceArtworkURL,
                    minimumPixelSide: minimumPixelSide
                )
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        if Task.isCancelled { return }
        if currentTrackKey != trackKey {
            print("[FullScreenArtworkWindowManager] track changed during cover lookup; dropping result")
            return
        }
        guard let imageData, let image = NSImage(data: imageData),
              image.atollPixelSize.width > MusicManager.shared.albumArt.atollPixelSize.width
        else {
            print("[FullScreenArtworkWindowManager] no sharper cover before applying wallpaper (current art is \(Int(MusicManager.shared.albumArt.atollPixelSize.width))px, lookup \(imageData == nil ? "returned nothing or timed out" : "was not sharper"))")
            // Automatic wallpaper only ever uses a real cover, so don't spend time upscaling.
            if !requireSharp { await prepareUpscaledArtwork(trackKey: trackKey, targetSide: minimumPixelSide) }
            return
        }

        print("[FullScreenArtworkWindowManager] using \(Int(image.atollPixelSize.width))px cover for first apply")
        highResArtwork = (trackKey, image)
        scheduleArtworkTempCleanup()
    }

    private func observePanelFrameChanges() {
        panelFrameChangeObserver = NotificationCenter.default.addObserver(
            forName: .atollLockScreenPanelFrameDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateArtworkOverlayFrameIfNeeded()
                self?.updateLyricsOverlayIfNeeded()
            }
        }
    }

    private func observeArtworkLayoutOverCanvasPreference() {
        artworkLayoutOverCanvasPreferenceCancellable = Defaults.publisher(.lockScreenUseArtworkLayoutOverFullscreenCanvas)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing else { return }
                self.refreshPresentationForCurrentTrack()
            }
    }

    private func observeLyricsChanges() {
        lyricsTextCancellable = MusicManager.shared.$currentLyrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing else { return }
                self.updateLyricsOverlayIfNeeded()
            }
    }

    private func observeLyricsPreference() {
        lyricsPreferenceCancellable = Defaults.publisher(.enableLyrics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing else { return }
                self.updateLyricsOverlayIfNeeded()
            }
    }

    private func shouldUseSpotifyStaticFallbackWallpaper(videoURL: URL?) -> Bool {
        guard MusicManager.shared.bundleIdentifier == SpotifyController.bundleIdentifier else {
            return false
        }

        return videoURL == nil
    }

    private func shouldUseSpotifyFallbackLayout(videoURL: URL?) -> Bool {
        guard MusicManager.shared.bundleIdentifier == SpotifyController.bundleIdentifier else {
            return false
        }

        if videoURL == nil {
            return true
        }

        return Defaults[.lockScreenUseArtworkLayoutOverFullscreenCanvas]
    }

    private func resolvedVideoURL(videoURL: URL?) -> URL? {
        guard isLiveWallpaperAllowed else { return nil }
        return videoURL
    }

    private func artworkOverlayMode(shouldUseFallbackLayout: Bool) -> ArtworkOverlayMode {
        if shouldUseFallbackLayout {
            return .spotifyFallback
        }

        return .none
    }

    func spotifyCanvasFallbackInterItemSpacing(screenFrame: NSRect) -> CGFloat {
        min(max(screenFrame.width * 0.018, 28), 42)
    }

    func spotifyCanvasFallbackArtworkSideLength(screenFrame: NSRect, panelSize: CGSize) -> CGFloat {
        let preferred = min(max(screenFrame.height * 0.28, 250), 330)
        let spacing = spotifyCanvasFallbackInterItemSpacing(screenFrame: screenFrame)
        let maxByWidth = max(
            min(screenFrame.width - (spotifyCanvasFallbackHorizontalMargin * 2) - spacing - panelSize.width, 360),
            180
        )
        let maxByHeight = max(min(screenFrame.height * 0.42, 360), 180)
        return min(preferred, maxByWidth, maxByHeight)
    }

    private func persistedArtworkFileURL(for artwork: NSImage, fingerprint: String) -> URL? {
        if let cached = cachedArtworkPNG,
           cachedArtworkFingerprint == fingerprint,
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        guard let encoded = encodeToPNG(artwork) else { return nil }

        let tempURL = artworkCacheFileURL(for: fingerprint)

        do {
            try encoded.write(to: tempURL, options: .atomic)
            cachedArtworkPNG = tempURL
            cachedArtworkFingerprint = fingerprint
            scheduleArtworkTempCleanup()
            return tempURL
        } catch {
            return nil
        }
    }

    private func blurredWallpaperFileURL(for artwork: NSImage, fingerprint: String, screen: NSScreen) -> URL? {
        let pixelSize = wallpaperPixelSize(for: screen)

        if let cached = cachedBlurredArtworkPNG,
           cachedBlurredArtworkFingerprint == fingerprint,
           cachedBlurredArtworkPixelSize == pixelSize,
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        guard let encoded = encodeBlurredWallpaperPNG(from: artwork, targetPixelSize: pixelSize) else {
            return nil
        }

        let tempURL = blurredArtworkCacheFileURL(for: fingerprint, pixelSize: pixelSize)

        do {
            try encoded.write(to: tempURL, options: .atomic)
            cachedBlurredArtworkPNG = tempURL
            cachedBlurredArtworkFingerprint = fingerprint
            cachedBlurredArtworkPixelSize = pixelSize
            scheduleArtworkTempCleanup()
            return tempURL
        } catch {
            return nil
        }
    }

    private func filledWallpaperFileURL(for artwork: NSImage, fingerprint: String, screen: NSScreen) -> URL? {
        let pixelSize = wallpaperPixelSize(for: screen)
        let pixelKey = "\(Int(pixelSize.width.rounded()))x\(Int(pixelSize.height.rounded()))"
        let cacheKey = "\(normalizedFingerprintComponent(fingerprint))_\(pixelKey)"

        // Prepared in the background when the track started: nothing left to render.
        if let ready = prerenderedWallpaper,
           ready.trackKey == currentTrackKey, ready.pixelKey == pixelKey,
           highResArtwork?.image === artwork,
           FileManager.default.fileExists(atPath: ready.url.path) {
            return ready.url
        }

        if let cached = cachedFilledArtworkPNG,
           cachedFilledArtworkKey == cacheKey,
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        guard let encoded = encodeFilledWallpaperPNG(from: artwork, targetPixelSize: pixelSize) else { return nil }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_artwork_wallpaper_filled_\(cacheKey).png")

        do {
            try encoded.write(to: fileURL, options: .atomic)
            cachedFilledArtworkPNG = fileURL
            cachedFilledArtworkKey = cacheKey
            scheduleArtworkTempCleanup()
            return fileURL
        } catch {
            return nil
        }
    }

    /// Scales the artwork to cover the whole screen (aspect-fill, centered crop)
    /// using Lanczos resampling, which keeps edges far cleaner than the default
    /// filter macOS applies when it stretches a small wallpaper itself.
    private nonisolated func encodeFilledWallpaperPNG(from artwork: NSImage, targetPixelSize: CGSize) -> Data? {
        guard let tiffData = artwork.tiffRepresentation,
              let sourceImage = CIImage(data: tiffData)
        else { return nil }
        return encodeFilledWallpaperPNG(from: sourceImage, targetPixelSize: targetPixelSize)
    }

    /// Same render, straight from the cover's original compressed bytes. Core Image decodes
    /// those lazily, so the full 3000 px bitmap and an uncompressed TIFF copy of it are never
    /// both held in memory.
    private nonisolated func encodeFilledWallpaperPNG(fromEncoded data: Data, targetPixelSize: CGSize) -> Data? {
        guard let sourceImage = CIImage(data: data) else { return nil }
        return encodeFilledWallpaperPNG(from: sourceImage, targetPixelSize: targetPixelSize)
    }

    private nonisolated func encodeFilledWallpaperPNG(from sourceImage: CIImage, targetPixelSize: CGSize) -> Data? {
        let sourceExtent = sourceImage.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return nil }

        let targetRect = CGRect(origin: .zero, size: targetPixelSize)
        let scale = max(
            targetRect.width / sourceExtent.width,
            targetRect.height / sourceExtent.height
        )

        var scaledImage = sourceImage.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
        )
        // A big enlargement leaves edges soft; a light unsharp mask brings back some
        // definition without the blocky look of nearest-neighbour scaling.
        if scale > 1.5 {
            scaledImage = scaledImage.applyingFilter(
                "CIUnsharpMask",
                parameters: [kCIInputRadiusKey: 2.0, kCIInputIntensityKey: 0.5]
            )
        }
        let scaledExtent = scaledImage.extent
        let centeredImage = scaledImage
            .transformed(by: CGAffineTransform(
                translationX: (targetRect.width - scaledExtent.width) / 2 - scaledExtent.minX,
                y: (targetRect.height - scaledExtent.height) / 2 - scaledExtent.minY
            ))
            .cropped(to: targetRect)

        let context = SharedCIContext.shared
        guard let cgImage = context.createCGImage(centeredImage, from: targetRect) else { return nil }

        // Written straight from the CGImage; going through NSBitmapImageRep copies the pixels again.
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func wallpaperPixelSize(for screen: NSScreen) -> CGSize {
        let scale = max(screen.backingScaleFactor, 1)
        let frame = screen.frame
        return CGSize(
            width: max(frame.width * scale, 1),
            height: max(frame.height * scale, 1)
        )
    }

    private func artworkCacheFileURL(for fingerprint: String) -> URL {
        let normalizedFingerprint = normalizedFingerprintComponent(fingerprint)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_artwork_wallpaper_\(normalizedFingerprint).png")
    }

    private func blurredArtworkCacheFileURL(for fingerprint: String, pixelSize: CGSize) -> URL {
        let normalizedFingerprint = normalizedFingerprintComponent(fingerprint)
        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_artwork_wallpaper_blurred_\(normalizedFingerprint)_\(width)x\(height).png")
    }

    private func normalizedFingerprintComponent(_ fingerprint: String) -> String {
        fingerprint.replacingOccurrences(of: "-", with: "_")
    }

    private func wallpaperIdentityKey(fingerprint: String, usesFallback: Bool, screen: NSScreen) -> String {
        if usesFallback {
            let pixelSize = wallpaperPixelSize(for: screen)
            let width = Int(pixelSize.width.rounded())
            let height = Int(pixelSize.height.rounded())
            return "fallback:\(fingerprint):\(width)x\(height)"
        }

        return "artwork:\(fingerprint)"
    }

    private nonisolated func encodeToPNG(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Cheap identity for an image: its dimensions plus ~4k bytes sampled evenly across the
    /// pixel data. Avoids re-encoding the whole image to PNG just to tell two covers apart.
    private nonisolated func imageFingerprint(for image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cgImage.dataProvider?.data as Data?
        else { return nil }
        var hasher = Hasher()
        hasher.combine(cgImage.width)
        hasher.combine(cgImage.height)
        hasher.combine(data.count)
        let samples = 4096
        let stride = max(1, data.count / samples)
        data.withUnsafeBytes { bytes in
            var index = 0
            while index < bytes.count {
                hasher.combine(bytes[index])
                index += stride
            }
        }
        return String(hasher.finalize())
    }

    /// Wallpaper PNGs are only needed while a wallpaper is applied. Remove them a few minutes
    /// after they were written so they don't pile up in the temp folder.
    private func scheduleArtworkTempCleanup() {
        guard tempCleanupTask == nil else { return }
        tempCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.tempFileLifetime))
            guard !Task.isCancelled, let self else { return }
            self.tempCleanupTask = nil
            self.pruneArtworkTempFiles(olderThan: Self.tempFileLifetime)
            if !self.isShowing {
                // Covers kept for a quick apply are dropped after five minutes.
                self.highResArtwork = nil
                self.upscaledArtwork = nil
                self.prerenderedWallpaper = nil
            }
        }
    }

    private func pruneArtworkTempFiles(olderThan age: TimeInterval) {
        // Files behind the wallpaper that is currently applied must stay.
        var inUse = Set<String>()
        if isShowing {
            for url in [artworkFileURL, cachedArtworkPNG, cachedBlurredArtworkPNG, cachedFilledArtworkPNG, prerenderedWallpaper?.url] {
                if let name = url?.lastPathComponent { inUse.insert(name) }
            }
        }

        let directory = FileManager.default.temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-age)
        var removed = 0
        for url in urls where url.lastPathComponent.hasPrefix(Self.tempFilePrefix) {
            guard !inUse.contains(url.lastPathComponent) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified > cutoff { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        if removed > 0 {
            print("[FullScreenArtworkWindowManager] removed \(removed) old artwork file(s)")
        }
        // Whatever is left (in use, or too new) gets another look later.
        if removed < urls.filter({ $0.lastPathComponent.hasPrefix(Self.tempFilePrefix) }).count {
            scheduleArtworkTempCleanup()
        }
    }

    private func encodeBlurredWallpaperPNG(from artwork: NSImage, targetPixelSize: CGSize) -> Data? {
        guard let tiffData = artwork.tiffRepresentation,
              let sourceImage = CIImage(data: tiffData)
        else { return nil }

        let targetRect = CGRect(origin: .zero, size: targetPixelSize)
        let sourceExtent = sourceImage.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return nil }

        let scale = max(
            targetRect.width / sourceExtent.width,
            targetRect.height / sourceExtent.height
        )
        let scaledWidth = sourceExtent.width * scale
        let scaledHeight = sourceExtent.height * scale
        let offsetX = (targetRect.width - scaledWidth) / 2
        let offsetY = (targetRect.height - scaledHeight) / 2

        let scaledImage = sourceImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            .cropped(to: targetRect)

        let blurredImage = scaledImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28])
            .cropped(to: targetRect)
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0.92,
                    kCIInputBrightnessKey: -0.03,
                    kCIInputContrastKey: 0.98
                ]
            )

        let context = SharedCIContext.shared
        guard let cgImage = context.createCGImage(blurredImage, from: targetRect) else { return nil }

        let renderedImage = NSImage(cgImage: cgImage, size: NSSize(width: targetPixelSize.width, height: targetPixelSize.height))
        let composedImage = NSImage(size: renderedImage.size)

        composedImage.lockFocus()
        renderedImage.draw(in: NSRect(origin: .zero, size: renderedImage.size))

        NSColor(calibratedWhite: 0.02, alpha: 0.08).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: renderedImage.size)).fill()

        let gradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.05),
            NSColor.clear,
            NSColor.black.withAlphaComponent(0.16)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: renderedImage.size), angle: -90)
        composedImage.unlockFocus()

        guard let finalTIFF = composedImage.tiffRepresentation,
              let finalBitmap = NSBitmapImageRep(data: finalTIFF)
        else { return nil }

        return finalBitmap.representation(using: .png, properties: [:])
    }

    private func applyDeferredStaticFallback() {
        guard let url = pendingFallbackStaticURL else { return }
        let key = pendingFallbackWallpaperKey
        pendingFallbackStaticURL = nil
        pendingFallbackWallpaperKey = nil

        if let screen = NSScreen.main {
            showWallpaperTransition(on: screen, imageURL: url)
        }
        guard applyArtworkToPlist(imageURL: url) else {
            print("[FullScreenArtworkWindowManager] Failed to apply deferred static fallback")
            hideWallpaperTransition()
            return
        }
        restartWallpaperAgent()
        activeWallpaperKey = key
        activeLiveWallpaperFingerprint = nil
        hideVideoWindow()
        scheduleWallpaperTransitionHide(after: .milliseconds(900))
    }

    private func scheduleLiveWallpaperPreparation(for videoURL: URL?, artwork: NSImage, identifier: String) {
        liveWallpaperTask?.cancel()
        liveWallpaperTask = nil

        guard isLiveWallpaperAllowed else {
            scheduleWallpaperTransitionHide(after: .milliseconds(260))
            return
        }

        guard let videoURL else {
            scheduleWallpaperTransitionHide(after: .milliseconds(260))
            return
        }

        let nextFingerprint = videoURL.absoluteString
        if activeLiveWallpaperFingerprint == nextFingerprint {
            scheduleWallpaperTransitionHide(after: .milliseconds(220))
            scheduleHideVideoWindow(after: .milliseconds(220), expectedURL: videoURL)
            return
        }

        if let screen = NSScreen.main {
            showVideoWindow(on: screen, videoURL: videoURL)
        }
        scheduleWallpaperTransitionHide(after: .milliseconds(420))

        let assetID = customLiveWallpaperAssetID
        let manifestURL = aerialManifestURL
        let videosDirectoryURL = aerialVideosDirectoryURL
        let thumbnailsDirectoryURL = aerialThumbnailsDirectoryURL
        let manifestBackupURL = liveWallpaperManifestBackupURL
        let videoBackupURL = liveWallpaperVideoBackupURL
        let thumbnailBackupURL = liveWallpaperThumbnailBackupURL
        let thumbnailData = encodeToPNG(artwork)
        let title = activeSongTitle ?? MusicManager.shared.songTitle
        let artist = activeArtist ?? MusicManager.shared.artistName
        let displayName = [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")

        liveWallpaperTask = Task(priority: .utility) { [weak self] in
            let prepared = await Self.prepareCustomLiveWallpaperAsset(
                from: videoURL,
                assetID: assetID,
                displayName: displayName.isEmpty ? "MyNotch Canvas" : displayName,
                manifestURL: manifestURL,
                videosDirectoryURL: videosDirectoryURL,
                thumbnailsDirectoryURL: thumbnailsDirectoryURL,
                thumbnailData: thumbnailData,
                manifestBackupURL: manifestBackupURL,
                videoBackupURL: videoBackupURL,
                thumbnailBackupURL: thumbnailBackupURL
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.isShowing, self.isLiveWallpaperAllowed else { return }
                let currentIdentifier = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
                let currentVideoURL = self.isLiveWallpaperAllowed ? MusicManager.shared.videoArtworkURL : nil
                guard currentIdentifier == identifier else { return }
                guard currentVideoURL?.absoluteString == nextFingerprint else { return }
                guard !self.shouldUseSpotifyStaticFallbackWallpaper(videoURL: currentVideoURL) else { return }
                guard prepared else {
                    self.applyDeferredStaticFallback()
                    return
                }
                guard self.applyAerialToPlist(assetID: assetID) else {
                    self.applyDeferredStaticFallback()
                    return
                }

                self.activeLiveWallpaperFingerprint = nextFingerprint
                self.pendingFallbackStaticURL = nil
                self.pendingFallbackWallpaperKey = nil
                self.restartWallpaperAgent()
                self.scheduleHideVideoWindow(after: .milliseconds(950), expectedURL: videoURL)
                print("[FullScreenArtworkWindowManager] Live wallpaper applied")
            }
        }
    }

    private nonisolated static func prepareCustomLiveWallpaperAsset(
        from sourceURL: URL,
        assetID: String,
        displayName: String,
        manifestURL: URL,
        videosDirectoryURL: URL,
        thumbnailsDirectoryURL: URL,
        thumbnailData: Data?,
        manifestBackupURL: URL,
        videoBackupURL: URL,
        thumbnailBackupURL: URL
    ) async -> Bool {
        let fm = FileManager.default
        let videoDestinationURL = videosDirectoryURL.appendingPathComponent("\(assetID).mov")
        let thumbnailDestinationURL = thumbnailsDirectoryURL.appendingPathComponent("\(assetID).png")

        do {
            try fm.createDirectory(at: videosDirectoryURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return false
        }

        backupItemIfNeeded(at: manifestURL, backupURL: manifestBackupURL)
        backupItemIfNeeded(at: videoDestinationURL, backupURL: videoBackupURL)
        backupItemIfNeeded(at: thumbnailDestinationURL, backupURL: thumbnailBackupURL)

        guard await materializeVideo(from: sourceURL, to: videoDestinationURL) else {
            return false
        }

        if let thumbnailData {
            try? thumbnailData.write(to: thumbnailDestinationURL, options: .atomic)
        }

        return updateAerialManifest(
            manifestURL: manifestURL,
            assetID: assetID,
            videoURL: videoDestinationURL,
            thumbnailURL: fm.fileExists(atPath: thumbnailDestinationURL.path) ? thumbnailDestinationURL : nil,
            displayName: displayName
        )
    }

    private nonisolated static func materializeVideo(from sourceURL: URL, to destinationURL: URL) async -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: destinationURL)

        if !sourceURL.isFileURL {
            guard let downloadedURL = await downloadRemoteVideo(from: sourceURL) else {
                return false
            }
            defer { try? fm.removeItem(at: downloadedURL) }
            return await materializeVideo(from: downloadedURL, to: destinationURL)
        }

        if sourceURL.isFileURL, sourceURL.pathExtension.lowercased() == "mov" {
            do {
                try fm.copyItem(at: sourceURL, to: destinationURL)
                return validateVideo(at: destinationURL)
            } catch {
                return false
            }
        }

        let asset = AVURLAsset(url: sourceURL)
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        for preset in presets {
            try? fm.removeItem(at: destinationURL)
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }

            exportSession.outputURL = destinationURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true

            let exported = await export(exportSession)
            if exported, validateVideo(at: destinationURL) {
                return true
            }
        }

        return false
    }

    private nonisolated static func downloadRemoteVideo(from sourceURL: URL) async -> URL? {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private nonisolated static func export(_ exportSession: AVAssetExportSession) async -> Bool {
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume(returning: exportSession.status == .completed)
            }
        }
    }

    private nonisolated static func validateVideo(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        return !asset.tracks(withMediaType: .video).isEmpty
    }

    private nonisolated static func updateAerialManifest(
        manifestURL: URL,
        assetID: String,
        videoURL: URL,
        thumbnailURL: URL?,
        displayName: String
    ) -> Bool {
        guard let manifestData = try? Data(contentsOf: manifestURL),
              var root = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              var assets = root["assets"] as? [[String: Any]]
        else {
            return false
        }

        guard let existingIndex = assets.firstIndex(where: { ($0["id"] as? String) == assetID }) else {
            return false
        }

        var customAsset = assets[existingIndex]
        customAsset["accessibilityLabel"] = displayName
        customAsset["previewImage"] = thumbnailURL?.absoluteString ?? ""
        customAsset["url-4K-SDR-240FPS"] = videoURL.absoluteString
        customAsset["pointsOfInterest"] = [:]
        assets[existingIndex] = customAsset

        root["assets"] = assets

        guard let encoded = try? JSONSerialization.data(withJSONObject: root, options: []) else {
            return false
        }

        do {
            try encoded.write(to: manifestURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func backupItemIfNeeded(at sourceURL: URL, backupURL: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return }
        guard !fm.fileExists(atPath: backupURL.path) else { return }
        try? fm.copyItem(at: sourceURL, to: backupURL)
    }

    private func restoreLiveWallpaperResources() {
        let fm = FileManager.default
        let assetID = customLiveWallpaperAssetID
        let videoDestinationURL = aerialVideosDirectoryURL.appendingPathComponent("\(assetID).mov")
        let thumbnailDestinationURL = aerialThumbnailsDirectoryURL.appendingPathComponent("\(assetID).png")

        if fm.fileExists(atPath: liveWallpaperManifestBackupURL.path) {
            try? fm.removeItem(at: aerialManifestURL)
            try? fm.copyItem(at: liveWallpaperManifestBackupURL, to: aerialManifestURL)
            try? fm.removeItem(at: liveWallpaperManifestBackupURL)
        }

        if fm.fileExists(atPath: liveWallpaperVideoBackupURL.path) {
            try? fm.removeItem(at: videoDestinationURL)
            try? fm.copyItem(at: liveWallpaperVideoBackupURL, to: videoDestinationURL)
            try? fm.removeItem(at: liveWallpaperVideoBackupURL)
        }

        if fm.fileExists(atPath: liveWallpaperThumbnailBackupURL.path) {
            try? fm.removeItem(at: thumbnailDestinationURL)
            try? fm.copyItem(at: liveWallpaperThumbnailBackupURL, to: thumbnailDestinationURL)
            try? fm.removeItem(at: liveWallpaperThumbnailBackupURL)
        }
    }

    // MARK: - Click Receiver

    private func installFallbackRightClickMonitorIfNeeded() {
        guard fallbackRightClickMonitor == nil else { return }

        fallbackRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, self.isShowing, self.isShowingSpotifyCanvasFallback else {
                return event
            }

            self.hide()
            return nil
        }
    }

    private func removeFallbackRightClickMonitor() {
        guard let fallbackRightClickMonitor else { return }
        NSEvent.removeMonitor(fallbackRightClickMonitor)
        self.fallbackRightClickMonitor = nil
    }

    private func showClickReceiver(on screen: NSScreen) {
        let screenFrame = screen.frame

        let window: ClickReceiverWindow
        if let existing = clickWindow {
            window = existing
        } else {
            let newWindow = ClickReceiverWindow(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)
            clickWindow = newWindow
            window = newWindow
            clickWindowDelegated = false
        }

        window.setFrame(screenFrame, display: true)
        window.onClick = { [weak self] in
            self?.hide()
        }

        if !clickWindowDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            clickWindowDelegated = true
        }

        window.orderFrontRegardless()

        for other in NSApp.windows where other !== window && other.level.rawValue >= Int(CGShieldingWindowLevel()) && other.isVisible {
            window.order(.below, relativeTo: other.windowNumber)
        }
    }

    private func hideClickReceiver() {
        clickWindow?.orderOut(nil)
        clickWindow?.onClick = nil
    }

    private func showArtworkOverlay(on screen: NSScreen, artwork: NSImage, mode: ArtworkOverlayMode) {
        currentArtworkOverlayMode = mode
        guard let targetFrame = artworkOverlayFrame(on: screen) else { return }

        let window: NSWindow
        if let existing = artworkOverlayWindow {
            window = existing
        } else {
            let newWindow = NSWindow(
                contentRect: targetFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = false
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)
            artworkOverlayWindow = newWindow
            window = newWindow
            artworkOverlayWindowDelegated = false
        }

        window.setFrame(targetFrame, display: true)

        let contentView: SpotifyCanvasFallbackArtworkOverlayView
        if let existing = window.contentView as? SpotifyCanvasFallbackArtworkOverlayView {
            contentView = existing
            contentView.frame = NSRect(origin: .zero, size: targetFrame.size)
            contentView.updateArtwork(artwork)
        } else {
            let newContentView = SpotifyCanvasFallbackArtworkOverlayView(artwork: artwork)
            newContentView.frame = NSRect(origin: .zero, size: targetFrame.size)
            window.contentView = newContentView
            contentView = newContentView
        }

        contentView.onDismiss = { [weak self] in
            self?.hide()
        }

        if !artworkOverlayWindowDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            artworkOverlayWindowDelegated = true
        }

        window.orderFrontRegardless()
    }

    private func hideArtworkOverlay() {
        currentArtworkOverlayMode = .none
        if let contentView = artworkOverlayWindow?.contentView as? SpotifyCanvasFallbackArtworkOverlayView {
            contentView.onDismiss = nil
        }
        artworkOverlayWindow?.orderOut(nil)
        artworkOverlayWindow?.contentView = nil
    }

    private func updateArtworkOverlayFrameIfNeeded() {
        guard isShowing, currentArtworkOverlayMode != .none else { return }
        guard let window = artworkOverlayWindow else { return }
        guard let screen = NSScreen.main, let frame = artworkOverlayFrame(on: screen) else { return }
        window.setFrame(frame, display: true)
    }

    private func artworkOverlayFrame(on screen: NSScreen) -> NSRect? {
        switch currentArtworkOverlayMode {
        case .none:
            return nil
        case .spotifyFallback:
            return spotifyFallbackArtworkOverlayFrame(on: screen)
        }
    }

    private func spotifyFallbackArtworkOverlayFrame(on screen: NSScreen) -> NSRect? {
        guard let frames = spotifyCanvasFallbackLayoutFrames(on: screen) else { return nil }
        return frames.artworkFrame
    }

    private func updateLyricsOverlayIfNeeded(on screen: NSScreen? = NSScreen.main) {
        guard isShowing, isShowingSpotifyCanvasFallback, Defaults[.enableLyrics] else {
            hideLyricsOverlay()
            return
        }

        let line = MusicManager.shared.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            hideLyricsOverlay()
            return
        }

        guard let screen, let frame = spotifyCanvasFallbackLayoutFrames(on: screen)?.lyricsFrame else {
            hideLyricsOverlay()
            return
        }

        let fontSize = min(max(frame.height * 0.24, 24), 40)
        let content = FullScreenLyricsOverlayContent(text: line, fontSize: fontSize)

        let window: NSWindow
        let hostingView: NSHostingView<FullScreenLyricsOverlayContent>
        if let existingWindow = lyricsOverlayWindow,
           let existingView = existingWindow.contentView as? NSHostingView<FullScreenLyricsOverlayContent> {
            window = existingWindow
            hostingView = existingView
        } else {
            let newWindow = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let newHostingView = NSHostingView(rootView: content)
            newHostingView.frame = NSRect(origin: .zero, size: frame.size)
            newHostingView.wantsLayer = true
            newHostingView.layer?.backgroundColor = NSColor.clear.cgColor
            newWindow.contentView = newHostingView

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)
            lyricsOverlayWindow = newWindow
            window = newWindow
            hostingView = newHostingView
            lyricsOverlayWindowDelegated = false
        }

        window.setFrame(frame, display: true)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.rootView = content

        if !lyricsOverlayWindowDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            lyricsOverlayWindowDelegated = true
        }

        window.orderFrontRegardless()
    }

    private func hideLyricsOverlay() {
        lyricsOverlayWindow?.orderOut(nil)
    }

    private func spotifyCanvasFallbackLayoutFrames(on screen: NSScreen) -> SpotifyCanvasFallbackLayoutFrames? {
        let screenFrame = screen.frame
        guard let panelFrame = LockScreenPanelManager.shared.latestFrame else { return nil }

        let overlaySide = spotifyCanvasFallbackArtworkSideLength(
            screenFrame: screenFrame,
            panelSize: panelFrame.size
        )
        let spacing = spotifyCanvasFallbackInterItemSpacing(screenFrame: screenFrame)
        let targetX = panelFrame.minX - spacing - overlaySide
        let targetY = panelFrame.midY - (overlaySide / 2)
        let artworkFrame = NSRect(x: targetX, y: targetY, width: overlaySide, height: overlaySide)
        let groupFrame = artworkFrame.union(panelFrame)
        let lyricsGap = min(max(screenFrame.height * 0.022, 18), 28)
        let bottomMargin = min(max(screenFrame.height * 0.16, 140), 220)
        let availableHeight = groupFrame.minY - lyricsGap - (screenFrame.minY + bottomMargin)
        let desiredHeight = min(max(screenFrame.height * 0.13, 108), 156)
        let lyricsHeight = min(desiredHeight, max(availableHeight, 0))
        let lyricsFrame: NSRect?

        if lyricsHeight >= 56 {
            lyricsFrame = NSRect(
                x: groupFrame.minX,
                y: groupFrame.minY - lyricsGap - lyricsHeight,
                width: groupFrame.width,
                height: lyricsHeight
            )
        } else {
            lyricsFrame = nil
        }

        return SpotifyCanvasFallbackLayoutFrames(
            artworkFrame: artworkFrame,
            panelFrame: panelFrame,
            groupFrame: groupFrame,
            lyricsFrame: lyricsFrame
        )
    }

    private func showWallpaperTransition(on screen: NSScreen, imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return }

        wallpaperTransitionHideTask?.cancel()
        wallpaperTransitionHideTask = nil

        let screenFrame = screen.frame

        let window: NSWindow
        let view: WallpaperTransitionImageView

        if let existingWindow = wallpaperTransitionWindow, let existingView = wallpaperTransitionView {
            window = existingWindow
            view = existingView
        } else {
            let newWindow = NSWindow(
                contentRect: screenFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let newView = WallpaperTransitionImageView(frame: screenFrame)
            newWindow.contentView = newView

            wallpaperTransitionWindow = newWindow
            wallpaperTransitionView = newView
            window = newWindow
            view = newView
        }

        window.setFrame(screenFrame, display: true)
        view.frame = NSRect(origin: .zero, size: screenFrame.size)
        view.updateImage(image)
        window.orderFrontRegardless()
    }

    private func scheduleWallpaperTransitionHide(after delay: Duration) {
        wallpaperTransitionHideTask?.cancel()
        wallpaperTransitionHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.hideWallpaperTransition()
        }
    }

    private func hideWallpaperTransition() {
        wallpaperTransitionHideTask?.cancel()
        wallpaperTransitionHideTask = nil
        wallpaperTransitionWindow?.orderOut(nil)
    }

    private func showVideoWindow(on screen: NSScreen, videoURL: URL) {
        videoWindowHideTask?.cancel()
        videoWindowHideTask = nil

        let screenFrame = screen.frame

        let window: NSWindow
        let view: LoopingVideoView

        if let existingWindow = videoWindow, let existingView = videoView {
            window = existingWindow
            view = existingView
        } else {
            let newWindow = NSWindow(
                contentRect: screenFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let newView = LoopingVideoView(frame: screenFrame)
            newWindow.contentView = newView

            videoWindow = newWindow
            videoView = newView
            window = newWindow
            view = newView
        }

        window.setFrame(screenFrame, display: true)
        view.frame = NSRect(origin: .zero, size: screenFrame.size)
        if activeVideoWindowURL != videoURL {
            view.play(url: videoURL)
            activeVideoWindowURL = videoURL
        }
        window.orderFrontRegardless()
        applyCanvasPlaybackState(isPlaying: MusicManager.shared.isPlaying)
    }

    private func scheduleHideVideoWindow(after delay: Duration, expectedURL: URL?) {
        videoWindowHideTask?.cancel()
        let expectedURLString = expectedURL?.absoluteString

        videoWindowHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }

            if let expectedURLString,
               self.activeVideoWindowURL?.absoluteString != expectedURLString {
                return
            }

            self.hideVideoWindow()
        }
    }

    private func hideVideoWindow() {
        videoWindowHideTask?.cancel()
        videoWindowHideTask = nil
        activeVideoWindowURL = nil
        videoView?.stop()
        videoWindow?.orderOut(nil)
    }

    // MARK: - Backup / Restore

    private var hasValidBackup: Bool {
        FileManager.default.fileExists(atPath: backupPlistURL.path)
    }

    private func backupWallpaperConfig() {
        guard !hasValidBackup else { return }
        try? FileManager.default.copyItem(at: wallpaperPlistURL, to: backupPlistURL)
    }

    private func applyArtworkToPlist(imageURL: URL) -> Bool {
        guard let plistData = try? Data(contentsOf: wallpaperPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return false }

        let desktopBlock = makeImageWallpaperBlock(imageURL: imageURL)
        let idleBlock = makeImageWallpaperBlock(imageURL: imageURL)

        patchWallpaperEntries(&plist, desktopBlock: desktopBlock, idleBlock: idleBlock)

        guard let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        else { return false }

        return (try? newData.write(to: wallpaperPlistURL, options: .atomic)) != nil
    }

    private func applyAerialToPlist(assetID: String) -> Bool {
        guard let plistData = try? Data(contentsOf: wallpaperPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return false }

        let desktopTemplate = wallpaperBlock(
            named: "Desktop",
            in: plist["AllSpacesAndDisplays"] as? [String: Any],
            fallback: plist["SystemDefault"] as? [String: Any]
        )
        let idleTemplate = wallpaperBlock(
            named: "Idle",
            in: plist["AllSpacesAndDisplays"] as? [String: Any],
            fallback: plist["SystemDefault"] as? [String: Any]
        )

        let desktopBlock = makeAerialWallpaperBlock(assetID: assetID, existingBlock: desktopTemplate)
        let idleBlock = makeAerialWallpaperBlock(assetID: assetID, existingBlock: idleTemplate)

        patchWallpaperEntries(&plist, desktopBlock: desktopBlock, idleBlock: idleBlock)

        guard let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        else { return false }

        return (try? newData.write(to: wallpaperPlistURL, options: .atomic)) != nil
    }

    private func wallpaperBlock(named name: String, in primary: [String: Any]?, fallback: [String: Any]?) -> [String: Any]? {
        if let primaryBlock = primary?[name] as? [String: Any] {
            return primaryBlock
        }
        return fallback?[name] as? [String: Any]
    }

    private func makeImageWallpaperBlock(imageURL: URL) -> [String: Any] {
        let config: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": imageURL.absoluteString]
        ]
        let configData = (try? PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)) ?? Data()

        let imageChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [] as [Any],
            "Configuration": configData
        ]

        let contentBlock: [String: Any] = [
            "Choices": [imageChoice],
            "Shuffle": "$null"
        ]

        return [
            "Content": contentBlock,
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    private func makeAerialWallpaperBlock(assetID: String, existingBlock: [String: Any]?) -> [String: Any] {
        let config: [String: Any] = [
            "assetID": assetID
        ]
        let configData = (try? PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)) ?? Data()

        let aerialChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.aerials",
            "Files": [] as [Any],
            "Configuration": configData
        ]

        var contentBlock: [String: Any] = [
            "Choices": [aerialChoice],
            "Shuffle": "$null"
        ]

        if let existingContent = existingBlock?["Content"] as? [String: Any],
           let encodedOptionValues = existingContent["EncodedOptionValues"] {
            contentBlock["EncodedOptionValues"] = encodedOptionValues
        }

        return [
            "Content": contentBlock,
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    private func patchWallpaperEntries(_ plist: inout [String: Any], desktopBlock: [String: Any], idleBlock: [String: Any]) {
        var allSpaces = (plist["AllSpacesAndDisplays"] as? [String: Any]) ?? [:]
        allSpaces["Desktop"] = desktopBlock
        allSpaces["Idle"] = idleBlock
        allSpaces["Type"] = "individual"
        plist["AllSpacesAndDisplays"] = allSpaces

        var systemDefault = (plist["SystemDefault"] as? [String: Any]) ?? [:]
        systemDefault["Desktop"] = desktopBlock
        systemDefault["Idle"] = idleBlock
        systemDefault["Type"] = "individual"
        plist["SystemDefault"] = systemDefault

        if var displays = plist["Displays"] as? [String: Any] {
            for key in displays.keys {
                if var display = displays[key] as? [String: Any] {
                    display["Desktop"] = desktopBlock
                    display["Idle"] = idleBlock
                    if display["Type"] != nil {
                        display["Type"] = "individual"
                    }
                    displays[key] = display
                }
            }
            plist["Displays"] = displays
        }

        if var spaces = plist["Spaces"] as? [String: Any] {
            for spaceKey in spaces.keys {
                if var space = spaces[spaceKey] as? [String: Any] {
                    if var defaultEntry = space["Default"] as? [String: Any] {
                        defaultEntry["Desktop"] = desktopBlock
                        defaultEntry["Idle"] = idleBlock
                        if defaultEntry["Type"] != nil {
                            defaultEntry["Type"] = "individual"
                        }
                        space["Default"] = defaultEntry
                    }
                    if var spaceDisplays = space["Displays"] as? [String: Any] {
                        for displayKey in spaceDisplays.keys {
                            if var display = spaceDisplays[displayKey] as? [String: Any] {
                                display["Desktop"] = desktopBlock
                                display["Idle"] = idleBlock
                                if display["Type"] != nil {
                                    display["Type"] = "individual"
                                }
                                spaceDisplays[displayKey] = display
                            }
                        }
                        space["Displays"] = spaceDisplays
                    }
                    spaces[spaceKey] = space
                }
            }
            plist["Spaces"] = spaces
        }
    }

    private func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
    }

    private func restoreWallpaper() {
        let fm = FileManager.default
        guard hasValidBackup else { return }

        do {
            try fm.removeItem(at: wallpaperPlistURL)
            try fm.copyItem(at: backupPlistURL, to: wallpaperPlistURL)
            try fm.removeItem(at: backupPlistURL)
        } catch {
            print("[FullScreenArtworkWindowManager] Failed to restore plist: \(error)")
        }

        restoreLiveWallpaperResources()
        restartWallpaperAgent()
    }

    // MARK: - Track Change Observer

    private func observeTrackChanges() {
        trackChangeCancellable?.cancel()
        trackChangeCancellable = MusicManager.shared.$songTitle
            .combineLatest(MusicManager.shared.$artistName)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, artist in
                guard let self, self.isShowing else { return }
                if title != self.activeSongTitle || artist != self.activeArtist {
                    self.refreshPresentationForCurrentTrack()
                    self.scheduleDeferredTrackRefresh(expectedTitle: title, expectedArtist: artist)
                }
            }
    }

    private func scheduleDeferredTrackRefresh(expectedTitle: String, expectedArtist: String) {
        deferredTrackRefreshTask?.cancel()
        deferredTrackRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.isShowing else { return }
            guard MusicManager.shared.songTitle == expectedTitle,
                  MusicManager.shared.artistName == expectedArtist
            else { return }

            self.refreshPresentationForCurrentTrack()
        }
    }
}
