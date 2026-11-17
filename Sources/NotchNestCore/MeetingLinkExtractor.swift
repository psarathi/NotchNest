import Foundation

/// Extracts video-meeting URLs from calendar event fields and task titles using deterministic pattern matching.
public enum MeetingLinkExtractor {
    private static let priorityHosts: [String] = [
        "zoom.us",
        "zoom.com",
        "zoomgov.com",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "meet.jit.si",
        "whereby.com",
        "around.co",
        "facetime.apple.com",
        "gather.town",
        "tuple.app",
        "chime.aws",
        "gotomeeting.com",
        "meet.goto.com",
        "bluejeans.com",
        "app.ringcentral.com"
    ]

    public static func extractMeetingURL(
        explicitURL: URL?,
        location: String?,
        notes: String?
    ) -> URL? {
        if let explicitURL {
            let resolved = unwrapRedirectIfNeeded(explicitURL)
            if isMeetingHost(resolved) || resolved.scheme?.lowercased() == "zoommtg" {
                return resolved
            }
            if isSupportedWebOrMeetingScheme(resolved) && (location == nil && notes == nil) {
                return resolved
            }
        }

        let candidates = [location, notes]
            .compactMap { $0 }
            .flatMap { detectURLs(in: $0) }
            .map { unwrapRedirectIfNeeded($0) }

        if let prioritized = candidates.first(where: { isMeetingHost($0) }) {
            return prioritized
        }

        if let explicitURL, isSupportedWebOrMeetingScheme(explicitURL) {
            let resolved = unwrapRedirectIfNeeded(explicitURL)
            if isMeetingHost(resolved) {
                return resolved
            }
            // Allow explicit event URLs only when they look like web links if no better conferencing host was found
            return resolved
        }
        return nil
    }

    public static func isMeetingHost(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == "facetime" || scheme == "zoommtg" {
            return true
        }
        guard let host = url.host?.lowercased() else {
            return false
        }
        if priorityHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }
        // Slack huddles
        if (host == "app.slack.com" || host.hasSuffix(".slack.com")) && url.path.lowercased().contains("huddle") {
            return true
        }
        return false
    }

    public static func serviceLabel(for url: URL) -> String {
        let scheme = url.scheme?.lowercased()
        if scheme == "zoommtg" {
            return "Zoom"
        }
        if scheme == "facetime" {
            return "FaceTime"
        }
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Meet" }
        if host.contains("teams.") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        if host.contains("slack") { return "Huddle" }
        return "Call"
    }

    private static func isSupportedWebOrMeetingScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http" || scheme == "facetime" || scheme == "zoommtg"
    }

    private static func unwrapRedirectIfNeeded(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }
        // Unwrap Outlook SafeLinks or Google calendar redirect URLs (?url=... or ?q=...)
        if host.contains("safelinks.protection.outlook.com") || host == "www.google.com" {
            for key in ["url", "q"] {
                if let rawTarget = comps.queryItems?.first(where: { $0.name == key })?.value,
                   let decoded = URL(string: rawTarget),
                   isSupportedWebOrMeetingScheme(decoded) {
                    return decoded
                }
            }
        }
        return url
    }

    private static func detectURLs(in text: String) -> [URL] {
        let cleaned = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\n", with: "\n")
        guard !cleaned.isEmpty else { return [] }

        var results: [URL] = []

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            let matches = detector.matches(in: cleaned, options: [], range: range)
                .compactMap { $0.url }
                .filter { isSupportedWebOrMeetingScheme($0) }
            results.append(contentsOf: matches)
        }

        // Also match zoommtg:// deep links which NSDataDetector skips
        if let regex = try? NSRegularExpression(pattern: #"zoommtg://[^\s<>\"']+"#, options: [.caseInsensitive]) {
            let ns = cleaned as NSString
            let range = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: cleaned, range: range) {
                if let url = URL(string: ns.substring(with: match.range)) {
                    results.append(url)
                }
            }
        }

        return results
    }
}
