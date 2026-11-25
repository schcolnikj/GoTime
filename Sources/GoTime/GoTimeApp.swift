import AppKit
import EventKit
import SwiftUI

@main
enum GoTimeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--selftest") { SelfTest.run(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var center = AlertCenter(model: model)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var ticks = 0
    private var lastRender = ""
    private var shownAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingController(rootView: PanelView(model: model, center: center, openSettings: { [weak self] in self?.openSettings() }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        }

        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: model.store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.reload() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.reload() }
        }

        Task { await model.requestAccess() }

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)  // keep ticking while menus are open
        timer = t
        tick()
    }

    private func tick() {
        model.now = Date()
        ticks += 1
        if ticks % 300 == 0 { model.refreshAccess(); model.reload() }  // also rolls the list over at midnight
        center.tick(now: model.now)
        renderStatusItem()
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }
        let state = model.bar
        let flashOn = Int(model.now.timeIntervalSince1970) % 2 == 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let key = "\(state.text)|\(state.urgency)|\(state.symbol)|\(flashOn)"
        guard key != lastRender else { return }
        lastRender = key
        button.setAccessibilityLabel(state.text)

        let colors: (bg: Color, fg: Color)
        switch state.urgency {
        case .calm:
            button.image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.title = " " + state.text
            return
        case .soon: colors = (.soon, .onSoon)
        case .imminent: colors = (.alarm, .white)
        case .now: colors = (flashOn ? .alarm : .alarmDim, .white)
        case .action: colors = (.brand, .onBrand)
        }
        let renderer = ImageRenderer(content: PillView(state: state, bg: colors.bg, fg: colors.fg))
        renderer.scale = button.window?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = false
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    @objc private func statusItemClicked() {
        // A hover may have just opened it; don't let the click that follows close it again.
        if popover.isShown && Date().timeIntervalSince(shownAt) > 0.6 {
            popover.performClose(nil)
        } else {
            showPanel(activate: true)
        }
    }

    @objc(mouseEntered:) func mouseEntered(_ event: NSEvent) { showPanel(activate: false) }
    @objc(mouseExited:) func mouseExited(_ event: NSEvent) {}

    private func showPanel(activate: Bool) {
        if activate { NSApp.activate() }  // needed for ⌘J / ⌘N / ⌘Q; hover doesn't steal focus
        guard let button = statusItem.button, !popover.isShown else { return }
        model.refreshAccess()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        shownAt = Date()
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(center: center, model: model)))
            w.title = "GoTime Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// `GoTime --selftest`: checks the alert ladder, link detection and formatting. Runs in build.sh.
enum SelfTest {
    static func run() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            if !ok { failures += 1; print("FAIL: \(what)") }
        }
        let all = Stage.allCases

        check(Stage.due(remaining: 600, enabled: all, fired: []) == .tenMin, "10-min stage at 10:00")
        check(Stage.due(remaining: 300, enabled: all, fired: [.tenMin]) == .fiveMin, "5-min stage at 5:00")
        check(Stage.due(remaining: 250, enabled: all, fired: [.tenMin, .fiveMin]) == nil, "nothing between stages")
        check(Stage.due(remaining: 30, enabled: all, fired: []) == .oneMin, "1-min stage at 0:30")
        check(Stage.due(remaining: 0, enabled: all, fired: []) == .start, "start wins at 0:00")
        check(Stage.due(remaining: -30, enabled: all, fired: [.tenMin, .fiveMin, .oneMin]) == .start, "start fires just after start")
        check(Stage.due(remaining: -200, enabled: all, fired: []) == nil, "stale start (after sleep) is skipped")
        check(Stage.due(remaining: 400, enabled: all, fired: []) == nil, "stale 10-min banner is skipped on late launch")
        check(Stage.due(remaining: 0, enabled: [.tenMin, .fiveMin, .oneMin], fired: []) == .oneMin, "start disabled falls back to 1-min")

        let meet = MeetingLink.find(in: [nil, "Room 4", "Join with Google Meet: https://meet.google.com/abc-defg-hij\nMore phone numbers"])
        check(meet?.service == "Google Meet" && meet?.url.absoluteString == "https://meet.google.com/abc-defg-hij", "Google Meet link in notes")
        let zoom = MeetingLink.find(in: ["https://us02web.zoom.us/j/123456789?pwd=abc123 (passcode 9)"])
        check(zoom?.service == "Zoom" && zoom?.url.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc123", "Zoom link with password")
        let teams = MeetingLink.find(in: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d>"])
        check(teams?.service == "Microsoft Teams" && teams?.url.absoluteString.hasSuffix("%7b%7d") == true, "Teams link in angle brackets")
        check(MeetingLink.find(in: ["Lunch at the usual place", nil]) == nil, "no link")

        check(Fmt.remaining(42 * 60) == "42m", "42m")
        check(Fmt.remaining(75 * 60) == "1h 15m", "1h 15m")
        check(Fmt.remaining(119) == "2m", "rounds up to 2m")
        check(Fmt.mss(102.6) == "1:42", "1:42")
        check(Fmt.mss(-12) == "0:12", "0:12 after start")
        check(Fmt.short("Quarterly roadmap planning session") == "Quarterly roadmap plann…", "truncates at 24")
        check(Fmt.urgency(601) == .calm && Fmt.urgency(600) == .soon && Fmt.urgency(120) == .imminent && Fmt.urgency(0) == .now, "urgency thresholds")

        print(failures == 0 ? "selftest: all passed" : "selftest: \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
