import AppKit
import EventKit

struct Meeting: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let link: URL?
    let service: String?
    let attendees: Int
    let color: NSColor
    /// Opens the event in Calendar; Join falls back to it when no video link was found.
    let calendarURL: URL?

    let response: Response

    /// Your answer to the invite.
    enum Response {
        case accepted, tentative, pending, declined

        init(_ status: EKParticipantStatus?) {
            switch status {
            case .none: self = .accepted  // your own event: you're not on its attendee list
            case .some(.pending): self = .pending
            case .some(.tentative): self = .tentative
            case .some(.declined): self = .declined
            default: self = .accepted
            }
        }

        var label: String? {
            switch self {
            case .accepted: return nil
            case .pending: return "Invited"
            case .tentative: return "Maybe"
            case .declined: return "Declined"
            }
        }
    }

    init(id: String, title: String, start: Date, end: Date, link: URL? = nil, service: String? = nil, attendees: Int = 0,
         color: NSColor = .systemBlue, calendarURL: URL? = nil, response: Response = .accepted) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.link = link; self.service = service; self.attendees = attendees; self.color = color
        self.calendarURL = calendarURL; self.response = response
    }

    init(event: EKEvent) {
        let found = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        self.init(
            // eventIdentifier is shared by every occurrence of a recurring event, so add the start time.
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(Int(event.startDate.timeIntervalSince1970))",
            title: (event.title?.isEmpty == false) ? event.title! : "Untitled",
            start: event.startDate,
            end: event.endDate,
            link: found?.url,
            service: found?.service,
            attendees: event.attendees?.count ?? 0,
            color: event.calendar?.color ?? .systemBlue,
            calendarURL: event.eventIdentifier
                .flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
                .flatMap { URL(string: "ical://ekevent/\($0)?method=show&options=more") },
            response: event.organizer?.isCurrentUser == true
                ? .accepted
                : Response(event.attendees?.first(where: \.isCurrentUser)?.participantStatus)
        )
    }

    var timeRange: String { "\(Fmt.time(start)) – \(Fmt.time(end))" }
    var meta: String {
        [response.label, service ?? "No video link", attendees > 1 ? "\(attendees) people" : nil].compactMap { $0 }.joined(separator: " · ")
    }
    var rowSub: String {
        [response.label, Fmt.duration(end.timeIntervalSince(start)), service ?? "No video link"].compactMap { $0 }.joined(separator: " · ")
    }
}

enum MeetingLink {
    // shortcut: covers the four big services; add patterns here for others (leits/MeetingBar keeps a long list).
    static let services: [(name: String, pattern: String)] = [
        ("Google Meet", #"https://meet\.google\.com/[a-z]{3,}-[a-z]{4,}-[a-z]{3,}"#),
        ("Zoom", #"https://(?:[\w-]+\.)?zoom(?:gov)?\.(?:us|com)/(?:j|my|w|s)/[^\s"'<>)]+|zoommtg://[^\s"'<>)]+"#),
        ("Microsoft Teams", #"https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s"'<>)]+"#),
        ("Webex", #"https://(?:[\w-]+\.)?webex\.com/(?:meet/|join/|[\w-]+/j\.php)[^\s"'<>)]*"#),
    ]

    static func find(in texts: [String?]) -> (url: URL, service: String)? {
        for text in texts.compactMap({ $0 }) {
            for s in services {
                if let r = text.range(of: s.pattern, options: [.regularExpression, .caseInsensitive]),
                   let url = URL(string: String(text[r])) {
                    return (url, s.name)
                }
            }
        }
        return nil
    }
}

enum Urgency { case calm, soon, imminent, now, action }

/// The alert ladder. Raw value = seconds before start.
enum Stage: Int, CaseIterable {
    case start = 0, oneMin = 60, fiveMin = 300, tenMin = 600

    var prefKey: String {
        switch self {
        case .tenMin: return "remind10"
        case .fiveMin: return "remind5"
        case .oneMin: return "remind1"
        case .start: return "remindStart"
        }
    }

    /// Which stage fires now. The most urgent one wins; a stage missed by more than `grace`
    /// (app launched late, Mac woke from sleep) is skipped instead of firing stale.
    static func due(remaining: TimeInterval, enabled: [Stage], fired: Set<Stage>, grace: TimeInterval = 90) -> Stage? {
        enabled
            .filter { remaining <= Double($0.rawValue) && remaining > Double($0.rawValue) - grace && !fired.contains($0) }
            .min { $0.rawValue < $1.rawValue }
    }
}

enum Fmt {
    static func urgency(_ remaining: TimeInterval) -> Urgency {
        remaining > 600 ? .calm : remaining > 120 ? .soon : remaining > 0 ? .imminent : .now
    }
    /// "42m", "1h 15m"
    static func remaining(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded(.up))
        guard m >= 60 else { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
    /// "1:42"
    static func mss(_ s: TimeInterval) -> String {
        let t = Int(abs(s).rounded(.down))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }
    static func short(_ title: String, max: Int = 24) -> String {
        title.count > max ? String(title.prefix(max - 1)) + "…" : title
    }
    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        guard m >= 60 else { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }
    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }
    static func day(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func weekday(_ d: Date) -> String { weekdayFormatter.string(from: d) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("jj:mm"); return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE d MMM"); return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEE"); return f
    }()
}
