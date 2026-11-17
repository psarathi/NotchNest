import AppKit
import Foundation
import Observation

public struct NowPlayingInfo: Equatable, Sendable {
    public var appName: String
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var artworkData: Data?

    public init(
        appName: String,
        title: String,
        artist: String,
        album: String = "",
        isPlaying: Bool,
        artworkData: Data? = nil
    ) {
        self.appName = appName
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.artworkData = artworkData
    }
}

/// Integrates safely with Apple Music, Spotify, and YouTube Music (Chrome/Chrome PWA/Safari tabs) via non-launching AppleScript & notifications.
@MainActor
@Observable
public final class MediaPlaybackService {
    public private(set) var currentTrack: NowPlayingInfo?
    public private(set) var automationError: String?
    public private(set) var youTubeMusicNeedsJSHint: Bool = false
    public var preferredPlayer: MusicPlayerPreference = .automatic {
        didSet {
            if preferredPlayer != oldValue {
                currentTrack = nil
                automationError = nil
                youTubeMusicNeedsJSHint = false
                lastNotifiedTrackKey = nil
                wasPlayingLastSample = false
                refreshNowPlaying()
            }
        }
    }
    public var onTrackChanged: (@MainActor (NowPlayingInfo) -> Void)?

    @ObservationIgnored private nonisolated(unsafe) var musicObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var spotifyObserver: NSObjectProtocol?
    private var pollTask: Task<Void, Never>?
    private var lastNotifiedTrackKey: String?
    private var wasPlayingLastSample: Bool = false
    private var ytmTitleFallbackPlayingState: Bool = true
    private var artworkCache: [String: Data] = [:]
    private var inFlightArtworkURLs: Set<String> = []

    public init() {}

    deinit {
        if let musicObserver {
            DistributedNotificationCenter.default().removeObserver(musicObserver)
        }
        if let spotifyObserver {
            DistributedNotificationCenter.default().removeObserver(spotifyObserver)
        }
    }

    public func startMonitoring() {
        let dnc = DistributedNotificationCenter.default()
        if musicObserver == nil {
            musicObserver = dnc.addObserver(
                forName: NSNotification.Name("com.apple.Music.playerInfo"),
                object: nil,
                queue: .main
            ) { [weak self] note in
                let parsed = Self.parseNotificationUserInfo(appName: "Music", userInfo: note.userInfo)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.preferredPlayer == .automatic || self.preferredPlayer == .appleMusic else { return }
                    if let parsed {
                        self.applyTrackUpdate(parsed.info, artworkURL: parsed.artworkURL)
                    }
                    self.refreshNowPlaying()
                }
            }
        }
        if spotifyObserver == nil {
            spotifyObserver = dnc.addObserver(
                forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
                object: nil,
                queue: .main
            ) { [weak self] note in
                let parsed = Self.parseNotificationUserInfo(appName: "Spotify", userInfo: note.userInfo)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.preferredPlayer == .automatic || self.preferredPlayer == .spotify else { return }
                    if let parsed {
                        self.applyTrackUpdate(parsed.info, artworkURL: parsed.artworkURL)
                    }
                    self.refreshNowPlaying()
                }
            }
        }

        refreshNowPlaying()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                self?.refreshNowPlaying()
            }
        }
    }

    public func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refreshNowPlaying() {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let musicRunning = runningBundleIDs.contains("com.apple.Music")
        let spotifyRunning = runningBundleIDs.contains("com.spotify.client")
        let chromeRunning = runningBundleIDs.contains("com.google.Chrome")
        let safariRunning = runningBundleIDs.contains("com.apple.Safari")
        let pref = preferredPlayer
        let fallbackPlaying = ytmTitleFallbackPlayingState

        let anyRelevantRunning: Bool
        switch pref {
        case .automatic:
            anyRelevantRunning = musicRunning || spotifyRunning || chromeRunning || safariRunning
        case .spotify:
            anyRelevantRunning = spotifyRunning
        case .appleMusic:
            anyRelevantRunning = musicRunning
        case .youTubeMusic:
            anyRelevantRunning = chromeRunning || safariRunning
        }

        guard anyRelevantRunning else {
            currentTrack = nil
            automationError = nil
            youTubeMusicNeedsJSHint = false
            lastNotifiedTrackKey = nil
            wasPlayingLastSample = false
            return
        }

        Task.detached(priority: .utility) {
            let outcome = Self.queryRunningMedia(
                preference: pref,
                musicRunning: musicRunning,
                spotifyRunning: spotifyRunning,
                chromeRunning: chromeRunning,
                safariRunning: safariRunning,
                ytmFallbackPlaying: fallbackPlaying
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch outcome {
                case .track(let info, let artworkURL, let needsJSHint):
                    self.automationError = nil
                    self.youTubeMusicNeedsJSHint = needsJSHint
                    self.applyTrackUpdate(info, artworkURL: artworkURL)
                case .stopped:
                    self.automationError = nil
                    self.youTubeMusicNeedsJSHint = false
                    self.currentTrack = nil
                    self.wasPlayingLastSample = false
                case .permissionDenied(let app):
                    self.youTubeMusicNeedsJSHint = false
                    self.automationError = "Allow Automation for \(app) in System Settings → Privacy & Security → Automation."
                case .failed:
                    break
                }
            }
        }
    }

    public func openPreferredPlayer() {
        switch preferredPlayer {
        case .spotify:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                NSWorkspace.shared.open(url)
            }
        case .appleMusic:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.open(url)
            }
        case .youTubeMusic, .automatic:
            openYouTubeMusic()
        }
    }

    public func openYouTubeMusic() {
        let pwaCandidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Chrome Apps.localized/YouTube Music.app"),
            URL(fileURLWithPath: "/Applications/YouTube Music.app")
        ]
        if let appURL = pwaCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(appURL)
            return
        }

        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if runningBundleIDs.contains("com.google.Chrome") {
            Task.detached(priority: .userInitiated) { [weak self] in
                let focusScript = """
                tell application "Google Chrome"
                    repeat with w in windows
                        set tabIdx to 1
                        repeat with t in tabs of w
                            if (URL of t as text) contains "music.youtube.com" then
                                set active tab index of w to tabIdx
                                set index of w to 1
                                activate
                                return "focused"
                            end if
                            set tabIdx to tabIdx + 1
                        end repeat
                    end repeat
                    return ""
                end tell
                """
                let script = NSAppleScript(source: focusScript)
                var err: NSDictionary?
                let out = script?.executeAndReturnError(&err).stringValue ?? ""
                await MainActor.run { [weak self] in
                    if out != "focused", let url = URL(string: "https://music.youtube.com") {
                        NSWorkspace.shared.open(url)
                    }
                    self?.refreshNowPlaying()
                }
            }
            return
        }

        if let url = URL(string: "https://music.youtube.com") {
            NSWorkspace.shared.open(url)
        }
    }

    public func togglePlayPause() {
        sendTransportCommand(.playPause)
    }

    public func nextTrack() {
        sendTransportCommand(.next)
    }

    public func previousTrack() {
        sendTransportCommand(.previous)
    }

    private enum TransportAction: String, Sendable {
        case playPause
        case next
        case previous
    }

    private func applyTrackUpdate(_ incoming: NowPlayingInfo, artworkURL: String?) {
        var resolved = incoming
        if resolved.artworkData == nil, let artworkURL {
            if let cached = artworkCache[artworkURL] {
                resolved.artworkData = cached
            } else {
                fetchArtworkIfNeeded(urlString: artworkURL)
            }
        } else if resolved.artworkData == nil,
                  let existing = currentTrack,
                  existing.title == resolved.title,
                  existing.artist == resolved.artist {
            resolved.artworkData = existing.artworkData
        }

        currentTrack = resolved
        let key = "\(resolved.appName)|\(resolved.title)|\(resolved.artist)"
        let becamePlaying = resolved.isPlaying && (!wasPlayingLastSample || key != lastNotifiedTrackKey)
        wasPlayingLastSample = resolved.isPlaying
        if becamePlaying {
            lastNotifiedTrackKey = key
            onTrackChanged?(resolved)
        }
    }

    private func fetchArtworkIfNeeded(urlString: String) {
        guard !inFlightArtworkURLs.contains(urlString),
              let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http"
        else {
            return
        }
        inFlightArtworkURLs.insert(urlString)

        Task.detached(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.inFlightArtworkURLs.remove(urlString)
                }
            }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty
            else {
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.artworkCache.count >= 24, let firstKey = self.artworkCache.keys.first {
                    self.artworkCache.removeValue(forKey: firstKey)
                }
                self.artworkCache[urlString] = data
                if var track = self.currentTrack {
                    track.artworkData = data
                    self.currentTrack = track
                }
            }
        }
    }

    private func sendTransportCommand(_ action: TransportAction) {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let isYTM = currentTrack?.appName == "YouTube Music" || preferredPlayer == .youTubeMusic

        if isYTM {
            let chromeRunning = runningBundleIDs.contains("com.google.Chrome")
            let safariRunning = runningBundleIDs.contains("com.apple.Safari")
            if youTubeMusicNeedsJSHint && action == .playPause {
                ytmTitleFallbackPlayingState.toggle()
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                let handledByJS = Self.controlYouTubeMusicTab(
                    action: action,
                    chromeRunning: chromeRunning,
                    safariRunning: safariRunning
                )
                if !handledByJS {
                    let keyCode: Int32
                    switch action {
                    case .playPause: keyCode = 16 // NX_KEYTYPE_PLAY
                    case .next: keyCode = 17      // NX_KEYTYPE_NEXT
                    case .previous: keyCode = 18  // NX_KEYTYPE_PREVIOUS
                    }
                    await MainActor.run {
                        Self.postHardwareMediaKey(keyCode)
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run { [weak self] in
                    self?.refreshNowPlaying()
                }
            }
            return
        }

        let targetApp: String?
        if preferredPlayer == .spotify
            || currentTrack?.appName == "Spotify"
            || (preferredPlayer == .automatic && !runningBundleIDs.contains("com.apple.Music") && runningBundleIDs.contains("com.spotify.client")) {
            targetApp = runningBundleIDs.contains("com.spotify.client") ? "Spotify" : nil
        } else {
            targetApp = runningBundleIDs.contains("com.apple.Music") ? "Music" : nil
        }

        guard let targetApp else {
            let keyCode: Int32 = (action == .playPause) ? 16 : (action == .next ? 17 : 18)
            Self.postHardwareMediaKey(keyCode)
            return
        }

        let command: String
        switch action {
        case .playPause: command = "playpause"
        case .next: command = "next track"
        case .previous: command = "previous track"
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let script = NSAppleScript(source: "tell application \"\(targetApp)\" to \(command)")
            var err: NSDictionary?
            script?.executeAndReturnError(&err)
            try? await Task.sleep(for: .milliseconds(200))
            await MainActor.run { [weak self] in
                self?.refreshNowPlaying()
            }
        }
    }

    private enum MediaQueryOutcome: Sendable {
        case track(NowPlayingInfo, artworkURL: String?, needsJSHint: Bool)
        case stopped
        case permissionDenied(String)
        case failed
    }

    nonisolated private static func queryRunningMedia(
        preference: MusicPlayerPreference,
        musicRunning: Bool,
        spotifyRunning: Bool,
        chromeRunning: Bool,
        safariRunning: Bool,
        ytmFallbackPlaying: Bool
    ) -> MediaQueryOutcome {
        switch preference {
        case .spotify:
            return spotifyRunning ? querySpotify() : .stopped
        case .appleMusic:
            return musicRunning ? queryMusic() : .stopped
        case .youTubeMusic:
            return queryYouTubeMusic(
                chromeRunning: chromeRunning,
                safariRunning: safariRunning,
                fallbackPlaying: ytmFallbackPlaying
            )
        case .automatic:
            var candidates: [MediaQueryOutcome] = []
            if spotifyRunning { candidates.append(querySpotify()) }
            if musicRunning { candidates.append(queryMusic()) }
            if chromeRunning || safariRunning {
                candidates.append(
                    queryYouTubeMusic(
                        chromeRunning: chromeRunning,
                        safariRunning: safariRunning,
                        fallbackPlaying: ytmFallbackPlaying
                    )
                )
            }

            for outcome in candidates {
                if case .track(let info, _, _) = outcome, info.isPlaying {
                    return outcome
                }
            }
            for outcome in candidates {
                if case .track = outcome {
                    return outcome
                }
            }
            for outcome in candidates {
                if case .permissionDenied = outcome {
                    return outcome
                }
            }
            return .stopped
        }
    }

    nonisolated private static func queryYouTubeMusic(
        chromeRunning: Bool,
        safariRunning: Bool,
        fallbackPlaying: Bool
    ) -> MediaQueryOutcome {
        if chromeRunning {
            let chromeOutcome = queryYouTubeMusicInChrome(fallbackPlaying: fallbackPlaying)
            if case .track = chromeOutcome {
                return chromeOutcome
            }
            if case .permissionDenied = chromeOutcome, !safariRunning {
                return chromeOutcome
            }
        }
        if safariRunning {
            return queryYouTubeMusicInSafari(fallbackPlaying: fallbackPlaying)
        }
        return .stopped
    }

    nonisolated private static func queryYouTubeMusicInChrome(fallbackPlaying: Bool) -> MediaQueryOutcome {
        let js = "(() => { const m = navigator.mediaSession && navigator.mediaSession.metadata; const p = (navigator.mediaSession && navigator.mediaSession.playbackState) || ''; const v = document.querySelector('video'); const playing = p === 'playing' || (!!v && !v.paused && !v.ended); const titleEl = document.querySelector('ytmusic-player-bar .title'); const bylineEl = document.querySelector('ytmusic-player-bar .byline'); const imgEl = document.querySelector('ytmusic-player-bar img.image'); const t = (m && m.title) || (titleEl && titleEl.textContent && titleEl.textContent.trim()) || ''; const a = (m && m.artist) || (bylineEl && bylineEl.textContent && bylineEl.textContent.trim()) || ''; const alb = (m && m.album) || ''; const art = (m && m.artwork && m.artwork.length) ? m.artwork[m.artwork.length - 1].src : ((imgEl && imgEl.src) || ''); return JSON.stringify({playing, t, a, alb, art}); })()"
        let source = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t as text) contains "music.youtube.com" then
                        set tabTitle to title of t as text
                        set jsPayload to ""
                        try
                            set jsPayload to (execute t javascript "\(escapeForAppleScriptString(js))")
                        end try
                        return {tabTitle, jsPayload}
                    end if
                end repeat
            end repeat
            return {}
        end tell
        """
        return runBrowserYouTubeMusicScript(source, browserName: "Google Chrome", fallbackPlaying: fallbackPlaying)
    }

    nonisolated private static func queryYouTubeMusicInSafari(fallbackPlaying: Bool) -> MediaQueryOutcome {
        let js = "(() => { const m = navigator.mediaSession && navigator.mediaSession.metadata; const p = (navigator.mediaSession && navigator.mediaSession.playbackState) || ''; const v = document.querySelector('video'); const playing = p === 'playing' || (!!v && !v.paused && !v.ended); const titleEl = document.querySelector('ytmusic-player-bar .title'); const bylineEl = document.querySelector('ytmusic-player-bar .byline'); const imgEl = document.querySelector('ytmusic-player-bar img.image'); const t = (m && m.title) || (titleEl && titleEl.textContent && titleEl.textContent.trim()) || ''; const a = (m && m.artist) || (bylineEl && bylineEl.textContent && bylineEl.textContent.trim()) || ''; const alb = (m && m.album) || ''; const art = (m && m.artwork && m.artwork.length) ? m.artwork[m.artwork.length - 1].src : ((imgEl && imgEl.src) || ''); return JSON.stringify({playing, t, a, alb, art}); })()"
        let source = """
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t as text) contains "music.youtube.com" then
                        set tabTitle to name of t as text
                        set jsPayload to ""
                        try
                            set jsPayload to (do JavaScript "\(escapeForAppleScriptString(js))" in t)
                        end try
                        return {tabTitle, jsPayload}
                    end if
                end repeat
            end repeat
            return {}
        end tell
        """
        return runBrowserYouTubeMusicScript(source, browserName: "Safari", fallbackPlaying: fallbackPlaying)
    }

    nonisolated private static func runBrowserYouTubeMusicScript(
        _ source: String,
        browserName: String,
        fallbackPlaying: Bool
    ) -> MediaQueryOutcome {
        let script = NSAppleScript(source: source)
        var err: NSDictionary?
        let descriptor = script?.executeAndReturnError(&err)
        if let err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                return .permissionDenied(browserName)
            }
            return .failed
        }
        guard let descriptor, descriptor.numberOfItems >= 1 else {
            return .stopped
        }
        let tabTitle = descriptor.atIndex(1)?.stringValue ?? ""
        let jsPayload = descriptor.numberOfItems >= 2 ? descriptor.atIndex(2)?.stringValue : nil
        guard let parsed = parseYouTubeMusicPayload(
            tabTitle: tabTitle,
            jsJSON: jsPayload,
            fallbackPlayingWhenTitleOnly: fallbackPlaying
        ) else {
            return .stopped
        }
        return .track(parsed.info, artworkURL: parsed.artworkURL, needsJSHint: !parsed.hasRichMetadata)
    }

    nonisolated private static func controlYouTubeMusicTab(
        action: TransportAction,
        chromeRunning: Bool,
        safariRunning: Bool
    ) -> Bool {
        let js: String
        switch action {
        case .playPause:
            js = "(() => { const btn = document.querySelector('#play-pause-button'); if (btn) { btn.click(); return 'ok'; } const v = document.querySelector('video'); if (v) { if (v.paused) v.play(); else v.pause(); return 'ok'; } return ''; })()"
        case .next:
            js = "(() => { const btn = document.querySelector('.next-button'); if (btn) { btn.click(); return 'ok'; } return ''; })()"
        case .previous:
            js = "(() => { const btn = document.querySelector('.previous-button'); if (btn) { btn.click(); return 'ok'; } return ''; })()"
        }

        if chromeRunning {
            let src = """
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as text) contains "music.youtube.com" then
                            return (execute t javascript "\(escapeForAppleScriptString(js))")
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
            let script = NSAppleScript(source: src)
            var err: NSDictionary?
            if let res = script?.executeAndReturnError(&err), res.stringValue == "ok" {
                return true
            }
        }
        if safariRunning {
            let src = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as text) contains "music.youtube.com" then
                            return (do JavaScript "\(escapeForAppleScriptString(js))" in t)
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
            let script = NSAppleScript(source: src)
            var err: NSDictionary?
            if let res = script?.executeAndReturnError(&err), res.stringValue == "ok" {
                return true
            }
        }
        return false
    }

    @MainActor
    private static func postHardwareMediaKey(_ keyType: Int32) {
        func send(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((keyType << 16) | (down ? 0xA00 : 0xB00))
            if let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) {
                event.cgEvent?.post(tap: .cghidEventTap)
            }
        }
        send(down: true)
        send(down: false)
    }

    nonisolated private static func escapeForAppleScriptString(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated private static func queryMusic() -> MediaQueryOutcome {
        let source = """
        tell application "Music"
            if player state is stopped then
                return {}
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set isPlayingNow to (player state is playing)
            return {isPlayingNow, trackName, trackArtist, trackAlbum}
        end tell
        """
        return runListAppleScript(source, appName: "Music")
    }

    nonisolated private static func querySpotify() -> MediaQueryOutcome {
        let source = """
        tell application "Spotify"
            if player state is stopped then
                return {}
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackArt to ""
            try
                set trackArt to artwork url of current track
            end try
            set isPlayingNow to (player state is playing)
            return {isPlayingNow, trackName, trackArtist, trackAlbum, trackArt}
        end tell
        """
        return runListAppleScript(source, appName: "Spotify")
    }

    nonisolated private static func runListAppleScript(_ source: String, appName: String) -> MediaQueryOutcome {
        let script = NSAppleScript(source: source)
        var err: NSDictionary?
        let descriptor = script?.executeAndReturnError(&err)
        if let err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                return .permissionDenied(appName)
            }
            return .failed
        }
        guard let descriptor else { return .failed }
        guard let parsed = parseAppleScriptDescriptor(descriptor, appName: appName) else {
            return .stopped
        }
        return .track(parsed.info, artworkURL: parsed.artworkURL, needsJSHint: false)
    }

    nonisolated public static func parseYouTubeMusicPayload(
        tabTitle: String,
        jsJSON: String?,
        fallbackPlayingWhenTitleOnly: Bool = true
    ) -> (info: NowPlayingInfo, artworkURL: String?, hasRichMetadata: Bool)? {
        if let jsJSON,
           !jsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let data = jsJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let title = (obj["t"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                let rawArtist = (obj["a"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedArtist = rawArtist
                    .components(separatedBy: "•")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawArtist
                let album = (obj["alb"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let artURL = (obj["art"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let playing = obj["playing"] as? Bool ?? false
                return (
                    NowPlayingInfo(
                        appName: "YouTube Music",
                        title: title,
                        artist: cleanedArtist,
                        album: album,
                        isPlaying: playing
                    ),
                    (artURL?.isEmpty == false) ? artURL : nil,
                    true
                )
            }
        }

        let trimmedTitle = tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              trimmedTitle.caseInsensitiveCompare("YouTube Music") != .orderedSame
        else {
            return nil
        }

        var cleanTrack = trimmedTitle
        for suffix in [" - YouTube Music", " – YouTube Music", " — YouTube Music"] {
            if cleanTrack.hasSuffix(suffix) {
                cleanTrack = String(cleanTrack.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        guard !cleanTrack.isEmpty,
              cleanTrack.caseInsensitiveCompare("YouTube Music") != .orderedSame
        else {
            return nil
        }

        return (
            NowPlayingInfo(
                appName: "YouTube Music",
                title: cleanTrack,
                artist: "YouTube Music",
                album: "",
                isPlaying: fallbackPlayingWhenTitleOnly
            ),
            nil,
            false
        )
    }

    nonisolated public static func parseAppleScriptDescriptor(
        _ descriptor: NSAppleEventDescriptor,
        appName: String
    ) -> (info: NowPlayingInfo, artworkURL: String?)? {
        guard descriptor.numberOfItems >= 3 else { return nil }
        let first = descriptor.atIndex(1)
        let isPlaying = (first?.booleanValue ?? false)
            || (first?.stringValue?.lowercased() == "true")
            || (first?.stringValue?.lowercased().contains("playing") == true)
        let title = descriptor.atIndex(2)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = descriptor.atIndex(3)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = (descriptor.numberOfItems >= 4 ? descriptor.atIndex(4)?.stringValue : nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artworkURL = (descriptor.numberOfItems >= 5 ? descriptor.atIndex(5)?.stringValue : nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return nil }
        return (
            NowPlayingInfo(
                appName: appName,
                title: title,
                artist: artist,
                album: album,
                isPlaying: isPlaying
            ),
            (artworkURL?.isEmpty == false) ? artworkURL : nil
        )
    }

    nonisolated public static func parseNotificationUserInfo(
        appName: String,
        userInfo: [AnyHashable: Any]?
    ) -> (info: NowPlayingInfo, artworkURL: String?)? {
        guard let userInfo else { return nil }
        let stateRaw = (userInfo["Player State"] as? String ?? "").lowercased()
        if stateRaw == "stopped" {
            return nil
        }
        let title = (userInfo["Name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = (userInfo["Artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (userInfo["Album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaying = stateRaw.contains("playing")
        let artURL = (userInfo["Artwork URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            NowPlayingInfo(
                appName: appName,
                title: title,
                artist: artist,
                album: album,
                isPlaying: isPlaying
            ),
            (artURL?.isEmpty == false) ? artURL : nil
        )
    }
}
