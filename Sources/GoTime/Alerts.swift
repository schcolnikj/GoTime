import AppKit
import SwiftUI

/// Runs the alert ladder: banners at 10/5/1 min, then a full-screen alarm at start.
@MainActor
final class AlertCenter {
    let model: AppModel
    let banner = BannerController()
    let alarm = AlarmController()
    private var fired: [String: Set<Stage>] = [:]
    private var snoozedUntil: [String: Date] = [:]
    private var lastAlarmSound = Date.distantPast

    init(model: AppModel) { self.model = model }

    func tick(now: Date) {
        let enabled = Stage.allCases.filter { Pref.d.bool(forKey: $0.prefKey) }
        for m in model.meetings where !model.muted.contains(m.id) && !model.acknowledged.contains(m.id) {
            if let s = Stage.due(remaining: m.start.timeIntervalSince(now), enabled: enabled, fired: fired[m.id, default: []]) {
                // Firing a stage also retires the earlier, less urgent ones.
                fired[m.id, default: []].formUnion(Stage.allCases.filter { $0.rawValue >= s.rawValue })
                fire(s, m, now: now)
            }
            if let until = snoozedUntil[m.id], now >= until { showAlarm(m) }
        }
        if alarm.isShown, Pref.d.bool(forKey: "repeatSound"), now.timeIntervalSince(lastAlarmSound) >= 10 {
            play(); lastAlarmSound = now
        }
    }

    private func fire(_ s: Stage, _ m: Meeting, now: Date) {
        let mins = max(1, Int((m.start.timeIntervalSince(now) / 60).rounded(.up)))
        switch s {
        case .tenMin: banner.show(m, kind: .heads, minutes: mins, center: self)
        case .fiveMin: banner.show(m, kind: .ready, minutes: mins, center: self); play()
        case .oneMin: banner.show(m, kind: .lastCall, minutes: mins, center: self); play()
        case .start: showAlarm(m)
        }
    }

    func showAlarm(_ m: Meeting) {
        snoozedUntil[m.id] = nil
        banner.close()
        alarm.show(m, center: self)
        play(); lastAlarmSound = Date()
    }

    func join(_ m: Meeting) {
        if let url = m.link ?? m.calendarURL { NSWorkspace.shared.open(url) }
        acknowledge(m)
    }

    func dismiss(_ m: Meeting) { acknowledge(m) }

    func snooze(_ m: Meeting, minutes: Int) {
        snoozedUntil[m.id] = Date().addingTimeInterval(Double(minutes) * 60)
        banner.close(); alarm.close()
    }

    func closeBanner() { banner.close() }

    func testAlarm() {
        let now = Date()
        showAlarm(Meeting(id: "test-\(now.timeIntervalSince1970)", title: "Test alarm", start: now, end: now.addingTimeInterval(1800),
                          link: URL(string: "https://meet.google.com/"), service: "Google Meet"))
    }

    private func acknowledge(_ m: Meeting) {
        model.acknowledged.insert(m.id)
        snoozedUntil[m.id] = nil
        banner.close(); alarm.close()
    }

    func play() {
        NSSound(named: NSSound.Name(Pref.d.string(forKey: "sound") ?? "Glass"))?.play()
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(rect: NSRect, level: NSWindow.Level, activating: Bool) {
        super.init(contentRect: rect, styleMask: activating ? [.borderless] : [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Show on every Space and over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
}

/// The today panel under the menu bar item. A non-activating panel rather than an NSPopover: activating
/// the app makes macOS re-lay out the menu bar (the « overflow), which moved the item and closed the popover.
@MainActor
final class PanelController {
    private var panel: FloatingPanel?
    private var monitors: [Any] = []
    private var appSwitch: NSObjectProtocol?
    private var top: CGFloat = 0
    private(set) var shownAt = Date.distantPast
    var isShown: Bool { panel != nil }

    func show<V: View>(_ content: V, below item: NSRect, focus: Bool) {
        close()
        let host = NSHostingView(rootView: content.windowGlass(22).padding(14).environment(\.colorScheme, .dark))
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(item) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let x = min(max(item.midX - size.width / 2, vf.minX), vf.maxX - size.width)
        let p = FloatingPanel(rect: NSRect(x: x, y: item.minY - size.height + 10, width: size.width, height: size.height),
                              level: .popUpMenu, activating: false)
        p.contentView = host
        if focus { p.makeKeyAndOrderFront(nil) } else { p.orderFrontRegardless() }  // hover must not steal typing
        panel = p
        top = p.frame.maxY
        shownAt = Date()

        // Close on a click in another app, on Esc, or when another app comes forward (e.g. Join opened the browser).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) { monitors.append(m) }
        appSwitch = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func focus() { panel?.makeKeyAndOrderFront(nil) }

    /// Grow or shrink to the content (e.g. after switching days), keeping the top edge under the menu bar.
    /// AppKit may already have resized the window from its bottom edge, so re-anchor to the saved top.
    func fitToContent() {
        guard let p = panel, let host = p.contentView else { return }
        let size = host.fittingSize
        let target = NSRect(x: p.frame.minX, y: top - size.height, width: size.width, height: size.height)
        if p.frame != target { p.setFrame(target, display: true) }
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let o = appSwitch { NSWorkspace.shared.notificationCenter.removeObserver(o); appSwitch = nil }
        panel?.close()
        panel = nil
    }
}

@MainActor
final class BannerController {
    enum Kind { case heads, ready, lastCall }
    private var panel: FloatingPanel?
    private var hide: DispatchWorkItem?

    // shortcut: one banner at a time; a second meeting's banner replaces the first.
    func show(_ m: Meeting, kind: Kind, minutes: Int, center: AlertCenter) {
        close()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let host = NSHostingView(rootView: BannerView(meeting: m, kind: kind, minutes: minutes, center: center))
        let size = host.fittingSize
        let vf = screen.visibleFrame
        let p = FloatingPanel(rect: NSRect(x: vf.maxX - size.width, y: vf.maxY - size.height, width: size.width, height: size.height),
                              level: .statusBar, activating: false)
        p.contentView = host
        p.orderFrontRegardless()
        panel = p
        if kind != .lastCall {  // the 1-minute alert stays until you choose
            let work = DispatchWorkItem { [weak self] in self?.close() }
            hide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (kind == .heads ? 5 : 8), execute: work)
        }
    }

    func close() {
        hide?.cancel(); hide = nil
        panel?.close(); panel = nil
    }
}

@MainActor
final class AlarmController {
    private var panels: [FloatingPanel] = []
    var isShown: Bool { !panels.isEmpty }

    func show(_ m: Meeting, center: AlertCenter) {
        close()
        for screen in NSScreen.screens {
            let p = FloatingPanel(rect: screen.frame, level: .screenSaver, activating: true)
            p.contentView = NSHostingView(rootView: AlarmView(meeting: m, center: center))
            p.setFrame(screen.frame, display: true)
            p.orderFrontRegardless()
            panels.append(p)
        }
        NSApp.activate()  // so Return joins and Esc dismisses
        panels.first?.makeKey()
    }

    func close() {
        panels.forEach { $0.close() }
        panels = []
    }
}
