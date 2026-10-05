import Foundation

struct CaptureProposal: Equatable, Sendable {
    var title: String
    var personName: String?
    var assetName: String?
    var dueAt: Date?
    var priority: ActionPriority
    var status: ActionStatus
    var alertKind: ActionAlertKind
    var confidence: Double
    var originalText: String
    var timingPhrase: String?
    var interpretationNotes: [String]
}

struct TurnoverDraft: Equatable, Sendable {
    var title: String
    var rawTranscript: String
    var overview: String
    var unitStatus: String
    var events: String
    var abnormalConditions: String
    var completedWork: String
    var openActions: String
    var waitingOn: String
    var upcomingWork: String
    var safetyNotes: String
    var uncertainties: String
    var actionCandidates: [TurnoverActionCandidate]
}

struct TurnoverActionCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var dueAt: Date?
    var personName: String?
    var isSelected: Bool

    init(id: UUID = UUID(), title: String, dueAt: Date? = nil, personName: String? = nil, isSelected: Bool = true) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.personName = personName
        self.isSelected = isSelected
    }
}

protocol IntelligenceService: Sendable {
    func proposeAction(from text: String, people: [String], assets: [String], now: Date) async -> CaptureProposal
    func organizeTurnover(from text: String, people: [String], now: Date) async -> TurnoverDraft
}

struct LocalRuleIntelligenceService: IntelligenceService {
    func proposeAction(from text: String, people: [String], assets: [String], now: Date = .now) async -> CaptureProposal {
        let clean = Self.normalizedWhitespace(text)
        let lower = clean.lowercased()
        let person = Self.detectPerson(in: clean, knownPeople: people)
        let asset = assets.first { lower.contains($0.lowercased()) }
        let timing = Self.detectDate(in: lower, now: now)
        let isWaiting = lower.contains("waiting") || lower.contains("check with") || lower.contains("follow up")
        let immediate = lower.contains("urgent") || lower.contains("immediately") || lower.contains("right now")
        let requestedAlarm = lower.contains("alarm") || lower.contains("wake me")
        let requestedReminder = lower.contains("remind") || lower.contains("make sure") || timing.date != nil
        let alertKind: ActionAlertKind = requestedAlarm ? .prominentAlarm : (requestedReminder ? .reminder : .none)

        var notes = timing.notes
        if timing.date == nil, Self.containsTimingLanguage(lower) {
            notes.append("Cailyn found timing language but could not resolve it. Choose a date and time before approving an alert.")
        }
        if let date = timing.date, date <= now {
            notes.append("The interpreted time has already passed. Choose a future time before approving an alert.")
        }
        if let person, !people.contains(where: { $0.caseInsensitiveCompare(person) == .orderedSame }) {
            notes.append("\(person) is not linked to a saved Cailyn person. The name will remain in the action text.")
        }

        let extracted = [person != nil, asset != nil, timing.date != nil].filter { $0 }.count
        return CaptureProposal(
            title: Self.actionTitle(from: clean),
            personName: person,
            assetName: asset,
            dueAt: timing.date,
            priority: immediate ? .immediate : (timing.date != nil ? .today : .planned),
            status: isWaiting ? .waiting : .open,
            alertKind: alertKind,
            confidence: min(0.92, 0.58 + Double(extracted) * 0.1),
            originalText: clean,
            timingPhrase: timing.phrase,
            interpretationNotes: notes
        )
    }

    func organizeTurnover(from text: String, people: [String], now: Date = .now) async -> TurnoverDraft {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = Self.sentences(from: text)
        var buckets: [TurnoverSection: [String]] = [:]

        for sentence in sentences {
            let cleaned = Self.conservativeCleanup(sentence)
            guard !cleaned.isEmpty else { continue }
            buckets[Self.section(for: cleaned), default: []].append(cleaned)
        }

        let open = buckets[.openActions, default: []]
        var candidates: [TurnoverActionCandidate] = []
        for item in open {
            let proposal = await proposeAction(from: item, people: people, assets: [], now: now)
            candidates.append(TurnoverActionCandidate(title: proposal.title, dueAt: proposal.dueAt, personName: proposal.personName))
        }

        let overviewItems = buckets[.overview, default: []]
        let overview = overviewItems.isEmpty
            ? "\(sentences.count) shift statement\(sentences.count == 1 ? "" : "s") captured for review."
            : Self.lines(overviewItems)

        return TurnoverDraft(
            title: "Shift Turnover — \(now.formatted(date: .abbreviated, time: .shortened))",
            rawTranscript: raw,
            overview: overview,
            unitStatus: Self.lines(buckets[.unitStatus, default: []]),
            events: Self.lines(buckets[.events, default: []]),
            abnormalConditions: Self.lines(buckets[.abnormal, default: []]),
            completedWork: Self.lines(buckets[.completed, default: []]),
            openActions: Self.lines(open),
            waitingOn: Self.lines(buckets[.waiting, default: []]),
            upcomingWork: Self.lines(buckets[.upcoming, default: []]),
            safetyNotes: Self.lines(buckets[.safety, default: []]),
            uncertainties: Self.lines(buckets[.uncertain, default: []]),
            actionCandidates: candidates
        )
    }

    private enum TurnoverSection { case overview, unitStatus, events, abnormal, completed, openActions, waiting, upcoming, safety, uncertain }

    private static func section(for sentence: String) -> TurnoverSection {
        let lower = sentence.lowercased()
        if containsAny(lower, ["not sure", "uncertain", "maybe", "possibly", "needs confirmation", "unconfirmed", "unknown"]) { return .uncertain }
        if containsAny(lower, ["safety", "hazard", "danger", "lockout", "tagout", "ppe", "permit", "injury"]) { return .safety }
        if containsAny(lower, ["waiting on", "awaiting", "pending", "hasn't responded", "has not responded"]) { return .waiting }
        if containsAny(lower, ["need to", "needs to", "must ", "follow up", "make sure", "should ", "action:", "todo", "to-do"]) { return .openActions }
        if containsAny(lower, ["tomorrow", "next shift", "upcoming", "scheduled", "expected", "will ", "due "]) { return .upcoming }
        if containsAny(lower, ["completed", "finished", "repaired", "closed", "resolved", "returned to service", "done "]) { return .completed }
        if containsAny(lower, ["alarm", "trip", "failed", "failure", "abnormal", "leak", "issue", "problem", "outage", "offline", "unavailable", "did not", "not available", "not running", "not return"]) { return .abnormal }
        if containsAny(lower, ["unit", "asset", "pump", "valve", "breaker", "turbine", "generator", "running", "available", "service"]) { return .unitStatus }
        if containsAny(lower, [" at ", " around ", "this morning", "this afternoon", "tonight", "occurred", "started", "stopped"]) { return .events }
        return .overview
    }

    static func conservativeCleanup(_ input: String) -> String {
        var value = normalizedWhitespace(input)
        let removablePrefixes = ["um, ", "uh, ", "okay, ", "so, ", "you know, ", "basically, ", "like, "]
        var changed = true
        while changed {
            changed = false
            for prefix in removablePrefixes where value.lowercased().hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                changed = true
            }
        }
        let fillerOnly = ["um", "uh", "okay", "you know", "that's all", "end of shift"]
        if fillerOnly.contains(value.lowercased().trimmingCharacters(in: .punctuationCharacters)) { return "" }
        return uppercaseFirst(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func sentences(from text: String) -> [String] {
        var output: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { output.append(sentence) }
        }
        if output.count <= 1, text.contains("\n") {
            return text.split(whereSeparator: \.isNewline).map { normalizedWhitespace(String($0)) }.filter { !$0.isEmpty }
        }
        return output.isEmpty && !text.isEmpty ? [text] : output
    }

    static func lines(_ values: [String]) -> String { values.map { "• \($0)" }.joined(separator: "\n") }

    private static func detectPerson(in text: String, knownPeople: [String]) -> String? {
        let lower = text.lowercased()
        if let known = knownPeople.first(where: { person in
            let full = person.lowercased()
            let first = full.split(separator: " ").first.map(String.init) ?? full
            return lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: first))\\b", options: .regularExpression) != nil
        }) { return known }

        let patterns = [
            #"(?i)\b(?:email|call|text|ask|notify)\s+([A-Z][A-Za-z0-9.'-]{1,30})\b"#,
            #"(?i)\b(?:follow up with|check with|waiting on)\s+([A-Z][A-Za-z0-9.'-]{1,30})\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    private struct DetectedTiming { var date: Date?; var phrase: String?; var notes: [String] }

    private static func detectDate(in text: String, now: Date) -> DetectedTiming {
        let calendar = Calendar.current
        let dayStart: Date
        var dayPhrase: String?
        if text.contains("tomorrow") {
            dayStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            dayPhrase = "tomorrow"
        } else if text.contains("today") || text.contains("tonight") {
            dayStart = calendar.startOfDay(for: now)
            dayPhrase = text.contains("tonight") ? "tonight" : "today"
        } else if let weekday = nextWeekday(in: text, now: now) {
            dayStart = calendar.startOfDay(for: weekday.date)
            dayPhrase = weekday.phrase
        } else {
            dayStart = calendar.startOfDay(for: now)
        }

        let patterns = [
            #"(?i)\b(?:at|around|by|before)?\s*(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*(a\.?m\.?|p\.?m\.?)\b"#,
            #"(?i)\b(?:at|around|by|before)\s+(1[0-9]|2[0-3]|0?[0-9])(?::([0-5][0-9]))?\s*(?:o['’]?clock)?\b"#,
            #"(?i)\b(1[0-2]|0?[1-9])\s+o['’]?clock\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let fullRange = Range(match.range(at: 0), in: text),
                  let hourRange = Range(match.range(at: 1), in: text),
                  var hour = Int(text[hourRange]) else { continue }
            var minute = 0
            if match.range(at: 2).location != NSNotFound, let range = Range(match.range(at: 2), in: text) { minute = Int(text[range]) ?? 0 }
            var meridiem: String?
            if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound, let range = Range(match.range(at: 3), in: text) { meridiem = String(text[range]).lowercased() }
            if meridiem?.hasPrefix("p") == true, hour < 12 { hour += 12 }
            if meridiem?.hasPrefix("a") == true, hour == 12 { hour = 0 }
            if meridiem == nil, hour <= 7, text.contains("tonight") { hour += 12 }
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
            let timePhrase = String(text[fullRange]).trimmingCharacters(in: .whitespaces)
            let phrase = [dayPhrase, timePhrase].compactMap { $0 }.joined(separator: " ")
            var notes: [String] = []
            if text.contains("around") || text.contains("about ") || text.contains("roughly") { notes.append("The exact time was interpreted from approximate language: “\(phrase)”.") }
            if meridiem == nil { notes.append("AM/PM was not stated. Cailyn interpreted “\(timePhrase)” as \(date?.formatted(date: .omitted, time: .shortened) ?? timePhrase).") }
            return DetectedTiming(date: date, phrase: phrase, notes: notes)
        }

        if dayPhrase != nil {
            let fallbackHour = text.contains("morning") ? 9 : (text.contains("afternoon") ? 13 : (text.contains("evening") || text.contains("tonight") ? 18 : 9))
            let date = calendar.date(bySettingHour: fallbackHour, minute: 0, second: 0, of: dayStart)
            return DetectedTiming(date: date, phrase: dayPhrase, notes: ["No exact time was stated. Cailyn selected \(date?.formatted(date: .omitted, time: .shortened) ?? "a default time"); confirm before approving."])
        }
        return DetectedTiming(date: nil, phrase: nil, notes: [])
    }

    private static func nextWeekday(in text: String, now: Date) -> (date: Date, phrase: String)? {
        let calendar = Calendar.current
        for (index, symbol) in calendar.weekdaySymbols.enumerated() where text.contains(symbol.lowercased()) {
            let target = index + 1
            let current = calendar.component(.weekday, from: now)
            var days = (target - current + 7) % 7
            if days == 0 { days = 7 }
            if let date = calendar.date(byAdding: .day, value: days, to: now) { return (date, symbol) }
        }
        return nil
    }

    private static func actionTitle(from text: String) -> String {
        var value = text
        let patterns = [
            #"(?i)^\s*(?:today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)?\s*(?:at|around|by|before)?\s*\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?|o['’]?clock)?\s*[,.-]?\s*"#,
            #"(?i)^\s*(?:remind me to|we need to make sure (?:that )?we|we need to|i need to|make sure (?:that )?we|please)\s+"#,
            #"(?i)^\s*(?:set|create)\s+(?:an?\s+)?(?:alarm|reminder)\s+(?:for\s+.+?\s+)?(?:to\s+)?"#
        ]
        for pattern in patterns { value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression) }
        value = value.replacingOccurrences(of: #"(?i)\bwork\s+flow\b"#, with: "workflow", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return uppercaseFirst(value.isEmpty ? text : value)
    }

    private static func containsTimingLanguage(_ text: String) -> Bool { containsAny(text, ["today", "tomorrow", "tonight", "morning", "afternoon", "evening", "o'clock", " at ", "around ", " by "]) }
    private static func containsAny(_ text: String, _ needles: [String]) -> Bool { needles.contains(where: text.contains) }
    private static func normalizedWhitespace(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    private static func uppercaseFirst(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}
