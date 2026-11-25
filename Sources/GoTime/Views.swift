import AppKit
import ServiceManagement
import SwiftUI

// shortcut: "New meeting" opens Google Calendar; change this URL if you use another calendar.
let newMeetingURL = URL(string: "https://calendar.google.com/calendar/r/eventedit")!

struct PanelView: View {
    @ObservedObject var model: AppModel
    let center: AlertCenter
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.access == .denied {
                accessCard
            } else {
                if let m = model.upNext { upNextCard(m) }
                todayList
            }
            footer
        }
        .padding(8)
        .frame(width: 336)
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GoTime needs calendar access").font(.system(size: 15, weight: .semibold))
            Text("Allow it in System Settings › Privacy & Security › Calendars, then open this panel again.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(12)
        .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func upNextCard(_ m: Meeting) -> some View {
        let muted = model.muted.contains(m.id)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up next · \(m.timeRange)").foregroundStyle(.secondary)
                Spacer()
                Text(model.countdownLabel(m)).fontWeight(.bold).foregroundStyle(model.countdownColor(m))
            }
            .font(.system(size: 12, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .monospacedDigit()

            Text(m.title).font(.system(size: 17, weight: .semibold)).lineLimit(2).padding(.top, 2)
            Text(m.meta).font(.system(size: 12)).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: muted ? "bell.slash" : "bell.fill").foregroundStyle(muted ? Color.secondary : Color.bell)
                Text(muted ? "Alerts off for this meeting" : model.alertSummary)
            }
            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)

            if m.link != nil {
                Button { center.join(m) } label: {
                    Label("Join \(m.service ?? "meeting")", systemImage: "video.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut("j")
                .padding(.top, 10)
            }
        }
        .padding(12)
        .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Fmt.day(model.now)) · \(model.leftToday) left").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)

            if model.today.isEmpty {
                Text(model.access == .granted ? "No meetings today" : "Loading your calendar…")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(8)
            }
            ForEach(model.today) { row($0) }
        }
        .padding(.bottom, 4)
    }

    private func row(_ m: Meeting) -> some View {
        let past = m.end <= model.now
        let isNext = m.id == model.upNext?.id
        let muted = model.muted.contains(m.id)
        return HStack(spacing: 8) {
            Text(Fmt.time(m.start)).font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(past ? .tertiary : .secondary)
                .frame(width: 40, alignment: .leading)
            Circle().fill(Color(nsColor: m.color)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.title).font(.system(size: 13, weight: isNext ? .semibold : .medium))
                    .foregroundStyle(past ? .tertiary : .primary).lineLimit(1)
                Text(m.rowSub).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !past {
                if m.link != nil {
                    Button("Join") { center.join(m) }
                        .buttonStyle(GlassButtonStyle(height: 26))
                        .accessibilityLabel("Join \(m.title)")
                }
                Button { model.toggleMute(m) } label: {
                    Image(systemName: muted ? "bell.slash" : "bell.fill")
                        .foregroundStyle(muted ? Color.secondary : Color.bell)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(muted ? "Turn on alerts for \(m.title)" : "Turn off alerts for \(m.title)")
                .help(muted ? "Alerts off" : "Alerts on")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(isNext ? RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.09)) : nil)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { NSWorkspace.shared.open(newMeetingURL) } label: { Label("New meeting", systemImage: "plus") }
                .buttonStyle(GlassButtonStyle())
                .keyboardShortcut("n")
            Spacer()
            Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(GlassButtonStyle())
                .accessibilityLabel("Settings")
                .keyboardShortcut(",")
            Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
                .buttonStyle(GlassButtonStyle())
                .keyboardShortcut("q")
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Divider() }
    }
}

struct BannerView: View {
    let meeting: Meeting
    let kind: BannerController.Kind
    let minutes: Int
    let center: AlertCenter

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.bell)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.brand.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(kind == .lastCall ? "GoTime · Time Sensitive" : "GoTime").fontWeight(.semibold)
                    Spacer()
                    Button { center.closeBanner() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(kind == .lastCall ? "\(meeting.title) starts in 1 min" : "\(meeting.title) in \(minutes) min")
                    .font(.system(size: 14, weight: .semibold))
                Text(kind == .heads ? "\(meeting.timeRange) · \(meeting.service ?? "No video link")"
                     : kind == .ready ? meeting.meta : "Stays on screen until you choose")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                if kind != .heads {
                    HStack(spacing: 8) {
                        if meeting.link != nil {
                            Button("Join") { center.join(meeting) }.buttonStyle(PrimaryButtonStyle(height: 30))
                        }
                        if kind == .lastCall {
                            Button("Snooze 1 min") { center.snooze(meeting, minutes: 1) }
                                .buttonStyle(GlassButtonStyle(height: 30, expand: true))
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .windowGlass(22)
        .padding(16)  // room for the shadow
    }
}

struct AlarmView: View {
    let meeting: Meeting
    let center: AlertCenter
    @State private var now = Date()
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            BlurView(material: .fullScreenUI).ignoresSafeArea()
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Circle().stroke(Color.alarm.opacity(0.6), lineWidth: 3)
                        .scaleEffect(pulse ? 1.8 : 1).opacity(pulse ? 0 : 1)
                    Circle().fill(Color.alarm)
                    Image(systemName: "bell.fill").font(.system(size: 36, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
                }

                Text(eyebrow)
                    .font(.system(size: 15, weight: .bold)).kerning(1.8).monospacedDigit()
                    .foregroundStyle(Color.alarmText).padding(.top, 30)
                Text(meeting.title)
                    .font(.system(size: 64, weight: .bold)).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.5).padding(.top, 10)
                Text("\(meeting.timeRange) · \(meeting.meta)")
                    .font(.system(size: 18)).foregroundStyle(.secondary).padding(.top, 12)

                Button { center.join(meeting) } label: {
                    if meeting.link == nil { Label("Got it", systemImage: "checkmark") }
                    else { Label("Join \(meeting.service ?? "meeting")", systemImage: "video.fill") }
                }
                .buttonStyle(PrimaryButtonStyle(height: 64))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 36)

                HStack(spacing: 10) {
                    Button("Snooze 1 min") { center.snooze(meeting, minutes: 1) }
                    Button("Snooze 5 min") { center.snooze(meeting, minutes: 5) }
                    Button("Dismiss") { center.dismiss(meeting) }.keyboardShortcut(.cancelAction)
                }
                .buttonStyle(GlassButtonStyle(height: 46, expand: true))
                .padding(.top, 12)

                Label(Pref.d.bool(forKey: "repeatSound") ? "Alarm repeats every 10 s until you choose" : "Return joins · Esc dismisses",
                      systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 24)
            }
            .frame(width: 504)
            .padding(48)
            .glassBackground(RoundedRectangle(cornerRadius: 44, style: .continuous))

            if let after = center.model.meetings.first(where: { $0.start > meeting.start }) {
                VStack {
                    Spacer()
                    Text("After this: \(after.title) at \(Fmt.time(after.start))")
                        .font(.system(size: 14)).foregroundStyle(.secondary).padding(.bottom, 28)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onReceive(timer) { now = $0 }
    }

    private var eyebrow: String {
        let r = meeting.start.timeIntervalSince(now)
        return r > 0 ? "STARTS IN \(Fmt.mss(r))" : "GO TIME · STARTED \(Fmt.mss(r)) AGO"
    }
}

struct SettingsView: View {
    let center: AlertCenter
    let model: AppModel
    @AppStorage("remind10") private var r10 = true
    @AppStorage("remind5") private var r5 = true
    @AppStorage("remind1") private var r1 = true
    @AppStorage("remindStart") private var r0 = true
    @AppStorage("sound") private var sound = "Glass"
    @AppStorage("repeatSound") private var repeatSound = true
    @AppStorage("skipDeclined") private var skipDeclined = true
    @AppStorage("onlyVideo") private var onlyVideo = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private static let sounds = ["Glass", "Hero", "Ping", "Funk", "Sosumi", "Submarine", "Blow", "Purr"]

    var body: some View {
        Form {
            Section("Remind me before each meeting") {
                Toggle("10 minutes before: banner", isOn: $r10)
                Toggle("5 minutes before: banner and sound", isOn: $r5)
                Toggle("1 minute before: alert that stays on screen", isOn: $r1)
                Toggle("At start time: full-screen alarm", isOn: $r0)
            }
            Section("At go time") {
                Picker("Alarm sound", selection: $sound) {
                    ForEach(Self.sounds, id: \.self) { Text($0) }
                }
                .onChange(of: sound) { center.play() }
                Toggle("Repeat every 10 s until I join, snooze or dismiss", isOn: $repeatSound)
            }
            Section("Which meetings get alerts") {
                Toggle("Skip meetings I've declined", isOn: $skipDeclined)
                    .onChange(of: skipDeclined) { model.reload() }
                Toggle("Only meetings with a video link", isOn: $onlyVideo)
                    .onChange(of: onlyVideo) { model.reload() }
            }
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                HStack {
                    Text("Turn alerts off for a single meeting with its bell in the panel.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { center.testAlarm() } label: { Label("Test alarm", systemImage: "bell.fill") }
                        .buttonStyle(PrimaryButtonStyle(height: 32))
                        .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 580)  // a grouped Form scrolls, so it has no natural height: the window collapsed without this
    }
}
