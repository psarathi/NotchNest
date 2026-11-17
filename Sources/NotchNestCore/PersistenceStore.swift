import Foundation

/// Atomic JSON persistence store under Application Support (or an explicit directory for tests).
public final class PersistenceStore: @unchecked Sendable {
    public let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.baseDirectory = appSupport.appendingPathComponent("NotchNest", isDirectory: true)
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
    }

    public func loadTasks() -> [TaskItem] {
        load([TaskItem].self, from: "tasks.json") ?? []
    }

    public func saveTasks(_ tasks: [TaskItem]) {
        save(tasks, to: "tasks.json")
    }

    public func loadNotes() -> [NoteEntry] {
        let loaded = load([NoteEntry].self, from: "notes.json") ?? []
        if loaded.isEmpty {
            return [NoteEntry(title: "Scratchpad", body: "")]
        }
        return loaded
    }

    public func saveNotes(_ notes: [NoteEntry]) {
        save(notes, to: "notes.json")
    }

    public func loadSettings() -> AppSettings {
        load(AppSettings.self, from: "settings.json") ?? AppSettings()
    }

    public func saveSettings(_ settings: AppSettings) {
        save(settings, to: "settings.json")
    }

    public func loadPinnedClips() -> [ClipItem] {
        load([ClipItem].self, from: "pinned_clips.json") ?? []
    }

    public func savePinnedClips(_ clips: [ClipItem]) {
        save(clips, to: "pinned_clips.json")
    }

    public func loadStats(now: Date = Date()) -> DailyFocusStats {
        let today = DailyFocusStats.todayKey(for: now)
        if let stats = load(DailyFocusStats.self, from: "focus_stats.json"), stats.dayKey == today {
            return stats
        }
        return DailyFocusStats(dayKey: today)
    }

    public func saveStats(_ stats: DailyFocusStats) {
        save(stats, to: "focus_stats.json")
    }

    public func loadActivityHistory() -> [DailyActivityRecord] {
        load([DailyActivityRecord].self, from: "activity_history.json") ?? []
    }

    public func saveActivityHistory(_ history: [DailyActivityRecord]) {
        save(history, to: "activity_history.json")
    }

    public func loadHealthStats(now: Date = Date()) -> DailyHealthStats {
        let today = DailyFocusStats.todayKey(for: now)
        if let loaded = load(DailyHealthStats.self, from: "health_stats.json") {
            if loaded.dayKey == today {
                return loaded
            }
            return DailyHealthStats(dayKey: today, streakDays: loaded.breaksTaken > 0 ? loaded.streakDays + 1 : 0)
        }
        return DailyHealthStats(dayKey: today)
    }

    public func saveHealthStats(_ stats: DailyHealthStats) {
        save(stats, to: "health_stats.json")
    }

    public func loadScreenTimeStats(now: Date = Date()) -> ScreenTimeDailyStats {
        let today = DailyFocusStats.todayKey(for: now)
        if let loaded = load(ScreenTimeDailyStats.self, from: "screen_time.json"), loaded.dayKey == today {
            return loaded
        }
        return ScreenTimeDailyStats(dayKey: today)
    }

    public func saveScreenTimeStats(_ stats: ScreenTimeDailyStats) {
        save(stats, to: "screen_time.json")
    }

    private func fileURL(for name: String) -> URL {
        baseDirectory.appendingPathComponent(name)
    }

    private func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = fileURL(for: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL(for: filename), options: [.atomic])
    }
}
