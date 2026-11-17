import Foundation

public enum ClipsFilter {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"
    ]

    public static let captureExtensions: Set<String> = imageExtensions.union([
        "mov", "mp4", "m4v"
    ])

    public static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isCaptureCandidate(
        url: URL,
        createdAt: Date?,
        cutoffDate: Date
    ) -> Bool {
        let name = url.lastPathComponent
        if name.isEmpty || name.hasPrefix(".") {
            return false
        }
        guard captureExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }
        guard let createdAt else { return false }
        return createdAt >= cutoffDate
    }
}

@MainActor
public final class ClipsWatcher {
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var watchDirectoryURL: URL?
    private let sessionStartDate: Date
    private let onNewFiles: ([ClipItem]) -> Void

    public init(
        sessionStartDate: Date = Date(),
        onNewFiles: @escaping ([ClipItem]) -> Void
    ) {
        self.sessionStartDate = sessionStartDate
        self.onNewFiles = onNewFiles
    }

    deinit {
        directorySource?.cancel()
    }

    public static func resolveScreenshotDirectory() -> URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    public func start(directory: URL? = nil) {
        stop()
        let target = directory ?? Self.resolveScreenshotDirectory()
        watchDirectoryURL = target
        let cutoff = min(sessionStartDate.addingTimeInterval(-3600 * 12), Date().addingTimeInterval(-3600 * 12))

        // Open and scan off the main thread so Desktop TCC consent prompts never freeze launch UI.
        Task.detached(priority: .utility) { [weak self] in
            let fd = open(target.path, O_EVTONLY)
            let scanned = Self.scanDirectory(target, cutoff: cutoff)
            await MainActor.run { [weak self] in
                guard let self, self.watchDirectoryURL == target else {
                    if fd >= 0 { close(fd) }
                    return
                }
                self.onNewFiles(scanned)
                guard fd >= 0 else { return }
                self.directoryFD = fd
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: [.write, .extend, .rename],
                    queue: .main
                )
                source.setEventHandler { [weak self] in
                    self?.scanNow()
                }
                source.setCancelHandler { [fd] in
                    close(fd)
                }
                self.directorySource = source
                source.resume()
            }
        }
    }

    public func stop() {
        watchDirectoryURL = nil
        directorySource?.cancel()
        directorySource = nil
        directoryFD = -1
    }

    public func scanNow() {
        guard let dir = watchDirectoryURL else { return }
        let cutoff = min(sessionStartDate.addingTimeInterval(-3600 * 12), Date().addingTimeInterval(-3600 * 12))
        Task.detached(priority: .utility) { [weak self] in
            let scanned = Self.scanDirectory(dir, cutoff: cutoff)
            await MainActor.run { [weak self] in
                guard let self, self.watchDirectoryURL == dir else { return }
                self.onNewFiles(scanned)
            }
        }
    }

    nonisolated private static func scanDirectory(_ dir: URL, cutoff: Date) -> [ClipItem] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [ClipItem] = []

        for url in contents {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else {
                continue
            }
            let created = values.creationDate ?? values.contentModificationDate
            guard ClipsFilter.isCaptureCandidate(url: url, createdAt: created, cutoffDate: cutoff) else {
                continue
            }
            candidates.append(
                ClipItem(
                    url: url,
                    addedAt: created ?? Date(),
                    isPinned: false,
                    isImage: ClipsFilter.isImageFile(url)
                )
            )
        }

        candidates.sort { $0.addedAt > $1.addedAt }
        return Array(candidates.prefix(15))
    }
}
