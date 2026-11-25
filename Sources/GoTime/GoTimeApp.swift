import AppKit
import EventKit
import SwiftUI

@main
enum GoTimeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--selftest") { SelfTest.run(); return }
        if let i = CommandLine.arguments.firstIndex(of: "--export-iconset"), i + 1 < CommandLine.arguments.count {
            exportIconset(to: CommandLine.arguments[i + 1]); return
        }
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
    private var statusItem: NSStatusItem!
    private let panel = PanelController()
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var ticks = 0
    private var lastRender = ""
    private var hoverOpen: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // New items land in the menu bar's hidden overflow (behind «). Start at the right end, in the
        // always-visible part; once the user ⌘-drags it, macOS saves that spot under the same key.
        let positionKey = "NSStatusItem Preferred Position GoTime"
        if Pref.d.object(forKey: positionKey) == nil { Pref.d.set(0, forKey: positionKey) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "GoTime"

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
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
        let key = "\(state.text)|\(state.urgency)|\(state.warning)|\(flashOn)"
        guard key != lastRender else { return }
        lastRender = key
        button.setAccessibilityLabel(state.text)

        let colors: (bg: Color, fg: Color)
        switch state.urgency {
        case .calm, .action: colors = (.brand, .white)  // white by choice; only 2.97:1 on #EF7200, fine for bold 13 pt
        case .soon: colors = (.soon, .onSoon)
        case .imminent: colors = (.alarm, .white)
        case .now: colors = (flashOn ? .alarm : .alarmDim, .white)
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
        hoverOpen?.cancel(); hoverOpen = nil
        // A hover may have just opened it; don't let the click that follows close it again.
        if panel.isShown && Date().timeIntervalSince(panel.shownAt) > 0.6 {
            panel.close()
        } else {
            showPanel(focus: true)
        }
    }

    // Hover opens the panel only after a real mouse move over the item plus a short rest. A bare
    // mouseEntered also fires when the menu bar overflow (« ») slides items under a still pointer.
    @objc(mouseEntered:) func mouseEntered(_ event: NSEvent) {}

    @objc(mouseMoved:) func mouseMoved(_ event: NSEvent) {
        guard hoverOpen == nil, !panel.isShown else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverOpen = nil
            if self.isPointerOnItem { self.showPanel(focus: false) }
        }
        hoverOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @objc(mouseExited:) func mouseExited(_ event: NSEvent) {
        hoverOpen?.cancel(); hoverOpen = nil
    }

    private var isPointerOnItem: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    /// Never activates the app (that re-lays out the menu bar); `focus` makes the panel key so ⌘J / ⌘N / ⌘Q work.
    private func showPanel(focus: Bool) {
        guard let button = statusItem.button, let window = button.window else { return }
        if panel.isShown { if focus { panel.focus() }; return }
        model.refreshAccess()
        model.dayOffset = 0  // always open on today
        let itemRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let content = PanelView(model: model, center: center,
                                openSettings: { [weak self] in self?.openSettings() },
                                onResize: { [weak self] in self?.panel.fitToContent() })
        panel.show(content, below: itemRect, focus: focus)
    }

    private func openSettings() {
        panel.close()
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

/// `GoTime --export-iconset <dir>`: writes the PNGs iconutil needs to build AppIcon.icns. Runs in build.sh.
@MainActor
func exportIconset(to dir: String) {
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = CGFloat(pt * scale)
            let renderer = ImageRenderer(content: AppIconView().frame(width: px, height: px))
            let name = "icon_\(pt)x\(pt)" + (scale == 2 ? "@2x" : "") + ".png"
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("icon export failed: \(name)"); exit(1)
            }
            do { try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name)) }
            catch { print("icon export failed: \(name): \(error)"); exit(1) }
        }
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

        let midnight = Date(timeIntervalSince1970: 1_000_000)
        check(AppModel.keepMute("abc@group.calendar.google.com@1000500", since: midnight), "mute kept for a meeting later today (id containing @)")
        check(!AppModel.keepMute("abc@999000", since: midnight), "mute dropped once its day has passed")
        check(!AppModel.keepMute("no-start-time", since: midnight), "mute without a start time is dropped")
        check(Meeting.Response(nil) == .accepted && Meeting.Response(.accepted) == .accepted
              && Meeting.Response(.pending) == .pending && Meeting.Response(.tentative) == .tentative
              && Meeting.Response(.declined) == .declined, "invite response mapping")
        check(Meeting(id: "x", title: "t", start: midnight, end: midnight.addingTimeInterval(1800), response: .pending).rowSub
              == "Invited · 30 min · No video link", "invited label in the row")

        print(failures == 0 ? "selftest: all passed" : "selftest: \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
