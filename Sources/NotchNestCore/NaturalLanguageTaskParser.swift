import Foundation

public struct ParsedTaskDraft: Equatable, Sendable {
    public var title: String
    public var scheduledBucket: TaskBucket
    public var scheduledDayKey: String?
    public var dueDate: Date?
    public var priority: TaskPriority
    public var projectTag: String?
    public var recurrence: TaskRecurrence
    public var targetMinutes: Int?
    public var hasStructuredMetadata: Bool

    public init(
        title: String,
        scheduledBucket: TaskBucket,
        scheduledDayKey: String? = nil,
        dueDate: Date? = nil,
        priority: TaskPriority = .normal,
        projectTag: String? = nil,
        recurrence: TaskRecurrence = .none,
        targetMinutes: Int? = nil,
        hasStructuredMetadata: Bool = false
    ) {
        self.title = title
        self.scheduledBucket = scheduledBucket
        self.scheduledDayKey = scheduledDayKey
        self.dueDate = dueDate
        self.priority = priority
        self.projectTag = projectTag
        self.recurrence = recurrence
        self.targetMinutes = targetMinutes
        self.hasStructuredMetadata = hasStructuredMetadata
    }

    public func previewSummary(relativeTo referenceDate: Date = Date(), calendar: Calendar = .current) -> String? {
        guard hasStructuredMetadata, !title.isEmpty else { return nil }
        var parts: [String] = []

        if let dueDate {
            let timeText = Self.timeFormatter.string(from: dueDate)
            if calendar.isDate(dueDate, inSameDayAs: referenceDate) {
                parts.append("Today, \(timeText)")
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
                      calendar.isDate(dueDate, inSameDayAs: tomorrow) {
                parts.append("Tomorrow, \(timeText)")
            } else {
                parts.append("\(Self.dayFormatter.string(from: dueDate)), \(timeText)")
            }
        } else if let scheduledDayKey,
                  let targetDate = DailyFocusStats.date(fromDayKey: scheduledDayKey) {
            if calendar.isDate(targetDate, inSameDayAs: referenceDate) {
                parts.append("Today")
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
                      calendar.isDate(targetDate, inSameDayAs: tomorrow) {
                parts.append("Tomorrow")
            } else {
                parts.append(Self.dayFormatter.string(from: targetDate))
            }
        } else {
            parts.append(scheduledBucket.title)
        }

        if let projectTag {
            parts.append("#\(projectTag)")
        }
        if priority == .high {
            parts.append("High")
        }
        if let recurrenceLabel = recurrence.label {
            parts.append(recurrenceLabel)
        }
        if let targetMinutes {
            parts.append("⏱ \(targetMinutes)m")
        }

        return "\"\(title)\" planned for \(parts.joined(separator: " · "))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()
}

/// Parses natural-language task strings ("Call mom tomorrow 5pm #Personal") cleanly without external dependencies.
public enum NaturalLanguageTaskParser {
    public static func parse(
        _ input: String,
        defaultBucket: TaskBucket = .today,
        defaultDayKey: String? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ParsedTaskDraft {
        var working = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else {
            return ParsedTaskDraft(title: "", scheduledBucket: defaultBucket, scheduledDayKey: defaultDayKey)
        }

        var bucket = defaultBucket
        var explicitBucketMatched = false
        var priority: TaskPriority = .normal
        var projectTag: String?
        var recurrence: TaskRecurrence = .none
        var targetDay: Date = defaultDayKey.flatMap { DailyFocusStats.date(fromDayKey: $0) }
            ?? calendar.startOfDay(for: referenceDate)
        var resolvedDayKey: String? = defaultDayKey
        var parsedHour: Int?
        var parsedMinute: Int?
        var relativeDueDate: Date?
        var targetMinutes: Int?
        var matchedAnything = false

        // 1. Hashtags (#Work, #Personal)
        if let tagRange = working.range(of: #"(?:^|\s)#([A-Za-z0-9_-]{2,24})"#, options: .regularExpression) {
            let rawTag = String(working[tagRange]).trimmingCharacters(in: .whitespaces)
            let cleanedTag = String(rawTag.dropFirst())
            projectTag = normalizeTag(cleanedTag)
            working.removeSubrange(tagRange)
            matchedAnything = true
        } else if let projectRange = working.range(
            of: #"(?i)\bproject\s+([A-Za-z0-9_-]{2,24})\b"#,
            options: .regularExpression
        ) {
            let slice = String(working[projectRange])
            if let word = slice.split(separator: " ").last {
                projectTag = normalizeTag(String(word))
            }
            working.removeSubrange(projectRange)
            matchedAnything = true
        }

        // 2. Priority markers
        if let prioRange = working.range(
            of: #"(?i)(?:^|\s)(?:!high|!urgent|priority\s*:?\s*high|high\s+priority|urgent|!!+)(?=\s|$)"#,
            options: .regularExpression
        ) {
            priority = .high
            working.removeSubrange(prioRange)
            matchedAnything = true
        }

        // 3. Recurrence keywords
        if let recRange = working.range(
            of: #"(?i)\b(?:every\s+weekday|weekdays)\b"#,
            options: .regularExpression
        ) {
            recurrence = .weekdays
            working.removeSubrange(recRange)
            matchedAnything = true
        } else if let recRange = working.range(
            of: #"(?i)\b(?:every\s+day|daily)\b"#,
            options: .regularExpression
        ) {
            recurrence = .daily
            working.removeSubrange(recRange)
            matchedAnything = true
        } else if let recRange = working.range(
            of: #"(?i)\b(?:every\s+week|weekly)\b"#,
            options: .regularExpression
        ) {
            recurrence = .weekly
            working.removeSubrange(recRange)
            matchedAnything = true
        }

        // 4. Relative duration ("in 20m", "in 2 hours")
        if let relRange = working.range(
            of: #"(?i)\bin\s+(\d{1,3})\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours)\b"#,
            options: .regularExpression
        ) {
            let matchText = String(working[relRange]).lowercased()
            let digits = matchText.compactMap { $0.isNumber ? $0 : nil }
            if let amount = Int(String(digits)), amount > 0 {
                let isHours = matchText.contains("h")
                let seconds = TimeInterval(amount * (isHours ? 3600 : 60))
                let computed = referenceDate.addingTimeInterval(seconds)
                relativeDueDate = computed
                bucket = bucketForDate(computed, referenceDate: referenceDate, calendar: calendar)
                resolvedDayKey = DailyFocusStats.todayKey(for: computed)
                explicitBucketMatched = true
                matchedAnything = true
                working.removeSubrange(relRange)
            }
        }

        // 4b. Target countdown duration ("45m", "for 45 min", "~30m", "(15 min)")
        if let durMatch = matchTargetDuration(in: working) {
            targetMinutes = durMatch.minutes
            matchedAnything = true
            working.removeSubrange(durMatch.range)
        }

        // 5. Day keywords ("inbox", "tomorrow", "today", "18 Nov"/"Nov 18", weekdays)
        if let inboxRange = working.range(of: #"(?i)\b(?:to\s+inbox|inbox)\b"#, options: .regularExpression) {
            bucket = .inbox
            resolvedDayKey = nil
            explicitBucketMatched = true
            matchedAnything = true
            working.removeSubrange(inboxRange)
        } else if let tomorrowRange = working.range(of: #"(?i)\b(?:tomorrow|tmr|tmrw)\b"#, options: .regularExpression) {
            targetDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? targetDay
            bucket = .tomorrow
            resolvedDayKey = DailyFocusStats.todayKey(for: targetDay)
            explicitBucketMatched = true
            matchedAnything = true
            working.removeSubrange(tomorrowRange)
        } else if let todayRange = working.range(of: #"(?i)\btoday\b"#, options: .regularExpression) {
            targetDay = calendar.startOfDay(for: referenceDate)
            bucket = .today
            resolvedDayKey = DailyFocusStats.todayKey(for: targetDay)
            explicitBucketMatched = true
            matchedAnything = true
            working.removeSubrange(todayRange)
        } else if let explicitDateMatch = matchExplicitDate(in: working, referenceDate: referenceDate, calendar: calendar) {
            targetDay = explicitDateMatch.date
            bucket = bucketForDate(explicitDateMatch.date, referenceDate: referenceDate, calendar: calendar)
            resolvedDayKey = DailyFocusStats.todayKey(for: explicitDateMatch.date)
            explicitBucketMatched = true
            matchedAnything = true
            working.removeSubrange(explicitDateMatch.range)
        } else if let weekdayMatch = matchWeekday(in: working, referenceDate: referenceDate, calendar: calendar) {
            targetDay = weekdayMatch.date
            bucket = bucketForDate(weekdayMatch.date, referenceDate: referenceDate, calendar: calendar)
            resolvedDayKey = DailyFocusStats.todayKey(for: weekdayMatch.date)
            explicitBucketMatched = true
            matchedAnything = true
            working.removeSubrange(weekdayMatch.range)
        }

        // 6. Time of day ("at 5pm", "5:30 pm", "17:45", "noon")
        if relativeDueDate == nil {
            if let timeMatch = matchExplicitTime(in: working) {
                parsedHour = timeMatch.hour
                parsedMinute = timeMatch.minute
                matchedAnything = true
                working.removeSubrange(timeMatch.range)
                if !explicitBucketMatched {
                    if defaultBucket == .inbox {
                        bucket = .today
                        targetDay = calendar.startOfDay(for: referenceDate)
                        resolvedDayKey = DailyFocusStats.todayKey(for: targetDay)
                    } else if resolvedDayKey == nil {
                        resolvedDayKey = DailyFocusStats.todayKey(for: targetDay)
                    }
                }
            }
        }

        // Ensure dayKey stays populated for today/tomorrow even when un-timed
        if resolvedDayKey == nil && bucket != .inbox {
            if bucket == .today {
                resolvedDayKey = DailyFocusStats.todayKey(for: calendar.startOfDay(for: referenceDate))
            } else if bucket == .tomorrow,
                      let tmr = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) {
                resolvedDayKey = DailyFocusStats.todayKey(for: tmr)
            }
        }

        // Compose final dueDate
        let dueDate: Date?
        if let relativeDueDate {
            dueDate = relativeDueDate
        } else if let parsedHour, let parsedMinute {
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDay)
            comps.hour = parsedHour
            comps.minute = parsedMinute
            comps.second = 0
            dueDate = calendar.date(from: comps)
        } else {
            dueDate = nil
        }

        // Clean leftover filler prepositions at edges
        var cleaned = working
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "?!."))))

        if matchedAnything {
            cleaned = cleaned.replacingOccurrences(
                of: #"(?i)\s+\b(?:at|on|by|for)\s*$"#,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let finalTitle = cleaned.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned

        return ParsedTaskDraft(
            title: finalTitle,
            scheduledBucket: bucket,
            scheduledDayKey: resolvedDayKey,
            dueDate: dueDate,
            priority: priority,
            projectTag: projectTag,
            recurrence: recurrence,
            targetMinutes: targetMinutes,
            hasStructuredMetadata: matchedAnything
        )
    }

    private static func matchTargetDuration(in text: String) -> (minutes: Int, range: Range<String.Index>)? {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|\s)(?:for\s+|~|\()?(\d{1,3})\s*(?:m|min|mins|minute|minutes)\)?(?=\s|$)"#,
            options: [.caseInsensitive]
        ),
        let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
        match.range(at: 1).location != NSNotFound,
        let fullRange = Range(match.range, in: text) else {
            return nil
        }
        let rawDigits = nsText.substring(with: match.range(at: 1))
        guard let mins = Int(rawDigits), (1...240).contains(mins) else {
            return nil
        }
        return (mins, fullRange)
    }

    private static func normalizeTag(_ raw: String) -> String {
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + raw.dropFirst().lowercased()
    }

    private static func bucketForDate(_ date: Date, referenceDate: Date, calendar: Calendar) -> TaskBucket {
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return .today
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        return .upcoming
    }

    private static func matchExplicitDate(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> (date: Date, range: Range<String.Index>)? {
        let months: [(String, Int)] = [
            ("january|jan", 1), ("february|feb", 2), ("march|mar", 3), ("april|apr", 4),
            ("may", 5), ("june|jun", 6), ("july|jul", 7), ("august|aug", 8),
            ("september|sept|sep", 9), ("october|oct", 10), ("november|nov", 11), ("december|dec", 12)
        ]
        let monthUnion = months.map(\.0).joined(separator: "|")
        let pattern1 = #"(?i)\b(?:on\s+)?(\d{1,2})\s+("# + monthUnion + #")\b"#
        let pattern2 = #"(?i)\b(?:on\s+)?("# + monthUnion + #")\s+(\d{1,2})\b"#
        let nsText = text as NSString
        let refStart = calendar.startOfDay(for: referenceDate)
        let refYear = calendar.component(.year, from: refStart)

        if let regex = try? NSRegularExpression(pattern: pattern1),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
           let range = Range(match.range, in: text),
           let day = Int(nsText.substring(with: match.range(at: 1))) {
            let monStr = nsText.substring(with: match.range(at: 2)).lowercased()
            if let month = monthNumber(monStr, in: months),
               let date = resolveDate(year: refYear, month: month, day: day, after: refStart, calendar: calendar) {
                return (date, range)
            }
        }

        if let regex = try? NSRegularExpression(pattern: pattern2),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
           let range = Range(match.range, in: text),
           let day = Int(nsText.substring(with: match.range(at: 2))) {
            let monStr = nsText.substring(with: match.range(at: 1)).lowercased()
            if let month = monthNumber(monStr, in: months),
               let date = resolveDate(year: refYear, month: month, day: day, after: refStart, calendar: calendar) {
                return (date, range)
            }
        }
        return nil
    }

    private static func monthNumber(_ str: String, in table: [(String, Int)]) -> Int? {
        for (pat, num) in table {
            if pat.split(separator: "|").contains(Substring(str)) {
                return num
            }
        }
        return nil
    }

    private static func resolveDate(year: Int, month: Int, day: Int, after refStart: Date, calendar: Calendar) -> Date? {
        var comps = DateComponents(year: year, month: month, day: day)
        guard var candidate = calendar.date(from: comps) else { return nil }
        if candidate < refStart {
            comps.year = year + 1
            candidate = calendar.date(from: comps) ?? candidate
        }
        return candidate
    }

    private static func matchWeekday(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> (date: Date, range: Range<String.Index>)? {
        let map: [(pattern: String, weekday: Int)] = [
            (#"(?i)\b(?:(?:on|this|next)\s+)?(?:sunday|sun)\b"#, 1),
            (#"(?i)\b(?:(?:on|this|next)\s+)?(?:monday|mon)\b"#, 2),
            (#"(?i)\b(?:(?:on|this|next)\s+)?(?:tuesday|tues|tue)\b"#, 3),
            (#"(?i)\b(?:(?:on|this|next)\s+)?(?:wednesday|wed)\b"#, 4),
            (#"(?i)\b(?:(?:on|this|next)\s+)?(?:thursday|thur|thu)\b"#, 5),
            (#"(?i)\b(?:(?:on|this|next)\s+)?(?:friday|fri)\b"#, 6),
            (#"(?i)\b(?:(?:on|this|next)\s+)?(?:saturday|sat)\b"#, 7)
        ]

        for entry in map {
            if let range = text.range(of: entry.pattern, options: .regularExpression) {
                let startToday = calendar.startOfDay(for: referenceDate)
                let currentWeekday = calendar.component(.weekday, from: startToday)
                var delta = entry.weekday - currentWeekday
                if delta <= 0 {
                    delta += 7
                }
                if let resolved = calendar.date(byAdding: .day, value: delta, to: startToday) {
                    return (resolved, range)
                }
            }
        }
        return nil
    }

    private static func matchExplicitTime(in text: String) -> (hour: Int, minute: Int, range: Range<String.Index>)? {
        let nsText = text as NSString
        let ampmRegex = try? NSRegularExpression(
            pattern: #"(?:^|\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#,
            options: [.caseInsensitive]
        )
        if let match = ampmRegex?.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
           let range = Range(match.range, in: text) {
            let hourRaw = Int(nsText.substring(with: match.range(at: 1))) ?? 0
            let minute = match.range(at: 2).location != NSNotFound ? (Int(nsText.substring(with: match.range(at: 2))) ?? 0) : 0
            let period = nsText.substring(with: match.range(at: 3)).lowercased()
            guard (1...12).contains(hourRaw), (0...59).contains(minute) else { return nil }
            var hour24 = hourRaw % 12
            if period == "pm" {
                hour24 += 12
            }
            return (hour24, minute, range)
        }

        let twentyFourRegex = try? NSRegularExpression(
            pattern: #"(?:^|\s)(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)\b"#,
            options: [.caseInsensitive]
        )
        if let match = twentyFourRegex?.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
           let range = Range(match.range, in: text) {
            let hour = Int(nsText.substring(with: match.range(at: 1))) ?? 0
            let minute = Int(nsText.substring(with: match.range(at: 2))) ?? 0
            return (hour, minute, range)
        }

        if let noonRange = text.range(of: #"(?i)(?:^|\s)(?:at\s+)?noon\b"#, options: .regularExpression) {
            return (12, 0, noonRange)
        }
        return nil
    }
}

public enum WorkspaceQuickCommand: Equatable, Sendable {
    case appendNote(String)
    case startFocus(minutes: Int)
    case translate(targetLanguage: String?, text: String)
    case snapWindow(SnapZone)

    public var previewLabel: String {
        switch self {
        case .appendNote(let text):
            return "Command · Append to note: \(text)"
        case .startFocus(let minutes):
            return "Command · Start Focus timer (\(minutes)m)"
        case .translate(let targetLanguage, let text):
            if let targetLanguage {
                return "Command · Translate to \(targetLanguage): \(text)"
            }
            return "Command · Translate: \(text)"
        case .snapWindow(let zone):
            return "Command · Snap window → \(zone.title)"
        }
    }

    public static func parse(_ rawInput: String) -> WorkspaceQuickCommand? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let noteText = matchNoteCommand(in: trimmed) {
            return .appendNote(noteText)
        }
        if let (lang, text) = matchTranslateCommand(in: trimmed) {
            return .translate(targetLanguage: lang, text: text)
        }
        if let minutes = matchFocusCommand(in: trimmed) {
            return .startFocus(minutes: minutes)
        }
        if let zone = matchSnapCommand(in: trimmed) {
            return .snapWindow(zone)
        }
        return nil
    }

    private static func matchNoteCommand(in text: String) -> String? {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^(?:note|n):\s*(.+)$"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.range(at: 1).location != NSNotFound else {
            return nil
        }
        let body = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private static func matchTranslateCommand(in text: String) -> (String?, String)? {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(
            pattern: #"^(?:tr|translate)(?:\s+([A-Za-z][A-Za-z\s-]{0,20}))?:\s*(.+)$"#,
            options: [.caseInsensitive]
        ),
        let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
        match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let body = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        var resolvedLang: String?
        if match.range(at: 1).location != NSNotFound {
            let rawLang = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawLang.isEmpty {
                resolvedLang = normalizeLanguageName(rawLang)
            }
        }
        return (resolvedLang, body)
    }

    private static func matchFocusCommand(in text: String) -> Int? {
        let nsText = text as NSString
        let patterns = [
            #"^(\d{1,3})\s*(?:m|min|mins|minute|minutes)\s+focus$"#,
            #"^focus\s+(\d{1,3})(?:\s*(?:m|min|mins|minute|minutes))?$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
               match.range(at: 1).location != NSNotFound {
                let raw = nsText.substring(with: match.range(at: 1))
                if let minutes = Int(raw), (1...180).contains(minutes) {
                    return minutes
                }
            }
        }
        return nil
    }

    private static func matchSnapCommand(in text: String) -> SnapZone? {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^snap(?::|\s+)\s*(.+)$"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.range(at: 1).location != NSNotFound else {
            return nil
        }
        let rawZone = nsText.substring(with: match.range(at: 1))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return snapAliases[rawZone]
    }

    private static let snapAliases: [String: SnapZone] = [
        "left": .leftHalf,
        "left half": .leftHalf,
        "l": .leftHalf,
        "right": .rightHalf,
        "right half": .rightHalf,
        "r": .rightHalf,
        "top": .topHalf,
        "top half": .topHalf,
        "up": .topHalf,
        "bottom": .bottomHalf,
        "bottom half": .bottomHalf,
        "down": .bottomHalf,
        "left third": .leftThird,
        "left 1/3": .leftThird,
        "center third": .centerThird,
        "middle third": .centerThird,
        "center 1/3": .centerThird,
        "right third": .rightThird,
        "right 1/3": .rightThird,
        "top left": .topLeftQuarter,
        "top left quarter": .topLeftQuarter,
        "tl": .topLeftQuarter,
        "top right": .topRightQuarter,
        "top right quarter": .topRightQuarter,
        "tr": .topRightQuarter,
        "bottom left": .bottomLeftQuarter,
        "bottom left quarter": .bottomLeftQuarter,
        "bl": .bottomLeftQuarter,
        "bottom right": .bottomRightQuarter,
        "bottom right quarter": .bottomRightQuarter,
        "br": .bottomRightQuarter,
        "max": .maximize,
        "maximize": .maximize,
        "full": .maximize,
        "fullscreen": .maximize,
        "center": .center,
        "c": .center
    ]

    private static func normalizeLanguageName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "es", "spa", "spanish": return "Spanish"
        case "fr", "fra", "fre", "french": return "French"
        case "de", "deu", "ger", "german": return "German"
        case "ja", "jp", "jpn", "japanese": return "Japanese"
        case "zh", "cn", "zho", "chi", "chinese": return "Chinese"
        case "ko", "kr", "kor", "korean": return "Korean"
        case "hi", "hin", "hindi": return "Hindi"
        case "pt", "por", "portuguese": return "Portuguese"
        case "it", "ita", "italian": return "Italian"
        case "en", "eng", "english": return "English"
        default:
            return raw.capitalized
        }
    }
}
