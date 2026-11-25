import AppKit
import EventKit
import SwiftUI

enum Pref {
    static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "remind10": true, "remind5": true, "remind1": true, "remindStart": true,
            "sound": "Glass", "repeatSound": true,
            "skipDeclined": true, "onlyVideo": false,
        ])
    }

    static var muted: Set<String> {
        get { Set(d.stringArray(forKey: "muted") ?? []) }
        set { d.set(Array(newValue), forKey: "muted") }
    }
}

struct BarState: Equatable {
    let text: String
    let urgency: Urgency
    var symbol = "calendar"
}

@MainActor
final class AppModel: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published var access: Access = .unknown
    @Published var meetings: [Meeting] = []
    @Published var now = Date()
    @Published var muted: Set<String> = Pref.muted
    /// Meetings joined or dismissed: no more alerts for them.
    @Published var acknowledged: Set<String> = []

    let store = EKEventStore()

    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        access = granted ? .granted : .denied
        reload()
    }

    /// Picks up access granted later in System Settings.
    func refreshAccess() {
        let fullAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if fullAccess && access != .granted { access = .granted; reload() }
    }

    func reload() {
        guard access == .granted else { meetings = []; return }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        // Fetch past midnight too, so a meeting at 00:05 still gets its 23:55 alert.
        let fetchEnd = max(dayEnd, now.addingTimeInterval(12 * 3600))
        let skipDeclined = Pref.d.bool(forKey: "skipDeclined")
        let onlyVideo = Pref.d.bool(forKey: "onlyVideo")

        meetings = store.events(matching: store.predicateForEvents(withStart: dayStart, end: fetchEnd, calendars: nil))
            .filter { !$0.isAllDay && $0.status != .canceled }
            .filter { !(skipDeclined && $0.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined) }
            .map(Meeting.init(event:))
            .filter { !onlyVideo || $0.link != nil }
            .sorted { $0.start < $1.start }

        if !meetings.isEmpty {
            muted.formIntersection(meetings.map(\.id))  // forget mutes for meetings that are gone
            Pref.muted = muted
        }
    }

    func toggleMute(_ m: Meeting) {
        if muted.contains(m.id) { muted.remove(m.id) } else { muted.insert(m.id) }
        Pref.muted = muted
    }

    // MARK: Derived state

    var today: [Meeting] { meetings.filter { Calendar.current.isDate($0.start, inSameDayAs: now) } }
    var leftToday: Int { today.filter { $0.end > now }.count }
    var current: Meeting? { meetings.last { $0.start <= now && now < $0.end } }

    /// Next meeting that starts later today (or within 10 min, across midnight).
    var upcoming: Meeting? {
        meetings.first { $0.start > now && (Calendar.current.isDate($0.start, inSameDayAs: now) || $0.start.timeIntervalSince(now) <= 600) }
    }

    /// Started in the last 10 min and not joined or dismissed yet: still go time.
    var goTime: Meeting? {
        meetings.first {
            $0.start <= now && now.timeIntervalSince($0.start) < 600 && now < $0.end
                && !acknowledged.contains($0.id) && !muted.contains($0.id)
        }
    }

    var upNext: Meeting? { goTime ?? upcoming }

    var bar: BarState {
        switch access {
        case .unknown: return BarState(text: "GoTime", urgency: .calm)
        case .denied: return BarState(text: "Allow calendar access", urgency: .action, symbol: "exclamationmark.circle")
        case .granted: break
        }
        if let m = goTime { return BarState(text: "Join now · " + Fmt.short(m.title), urgency: .now) }
        if let m = upcoming, m.start.timeIntervalSince(now) <= 600 { return countdownBar(m) }
        if let m = current {
            return BarState(text: Fmt.short(m.title) + " · ends in " + Fmt.remaining(m.end.timeIntervalSince(now)), urgency: .calm)
        }
        if let m = upcoming { return countdownBar(m) }
        return BarState(text: "Free for the day", urgency: .calm, symbol: "checkmark.circle")
    }

    private func countdownBar(_ m: Meeting) -> BarState {
        let r = m.start.timeIntervalSince(now)
        let u = Fmt.urgency(r)
        return BarState(text: Fmt.short(m.title) + " · " + (u == .imminent ? Fmt.mss(r) : Fmt.remaining(r)), urgency: u)
    }

    func countdownLabel(_ m: Meeting) -> String {
        let r = m.start.timeIntervalSince(now)
        if r <= 0 { return Fmt.mss(r) + " ago" }
        return "in " + (r > 600 ? Fmt.remaining(r) : Fmt.mss(r))
    }

    func countdownColor(_ m: Meeting) -> Color {
        switch Fmt.urgency(m.start.timeIntervalSince(now)) {
        case .calm, .action: return .primary
        case .soon: return .soon
        case .imminent, .now: return .alarmText
        }
    }

    var alertSummary: String {
        let mins = [Stage.tenMin, .fiveMin, .oneMin].filter { Pref.d.bool(forKey: $0.prefKey) }.map { "\($0.rawValue / 60)" }
        let atStart = Pref.d.bool(forKey: Stage.start.prefKey)
        switch (mins.isEmpty, atStart) {
        case (true, false): return "All alerts are off in Settings"
        case (true, true): return "Full-screen alarm at start"
        case (false, false): return "Alerts at \(mins.joined(separator: ", ")) min"
        case (false, true): return "Alerts at \(mins.joined(separator: ", ")) min and at start"
        }
    }
}
