import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    /// Primary buttons. Text on it is near-black: white on #EF7200 is only 2.97:1.
    static let brand = Color(hex: 0xEF7200)
    static let onBrand = Color(hex: 0x1F1000)
    static let soon = Color(hex: 0xFFD60A)
    static let onSoon = Color(hex: 0x1F1A00)
    static let alarm = Color(hex: 0xD62F3A)
    static let alarmDim = Color(hex: 0x7A1A21)
    static let alarmText = Color(hex: 0xFF7A7A)
    static let bell = Color(hex: 0xFFA347)
}

extension View {
    /// Liquid Glass on macOS 26+, frosted material before that.
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }

    /// Glass for views that float in their own transparent window (banner, alarm card).
    func windowGlass(_ radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(BlurView().clipShape(shape))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

struct BlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height >= 56 ? 20 : 14, weight: .semibold))
            .foregroundStyle(Color.onBrand)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(Color.brand.opacity(configuration.isPressed ? 0.8 : 1)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: Color.brand.opacity(0.35), radius: 10, y: 4)
            .contentShape(Capsule())
    }
}

struct GlassButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var expand = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height >= 44 ? 15 : 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, height >= 44 ? 16 : 10)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: height)
            .glassBackground(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// The GoTime mark, "Alarm G": an alarm clock whose ring opens at the top right like a G (the hand at 3 is
/// the G's bar), with bells on top and legs. Drawn in the current foreground style.
struct LogoMark: View {
    var weight: CGFloat = 9  // ring stroke, in the 100×100 design box

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let t = CGAffineTransform(translationX: (g.size.width - s) / 2, y: (g.size.height - s) / 2).scaledBy(x: s / 100, y: s / 100)
            ZStack {
                Self.bells.applying(t).fill()
                Self.clock.applying(t).stroke(style: StrokeStyle(lineWidth: weight * s / 100, lineCap: .round))
                Self.legs.applying(t).stroke(style: StrokeStyle(lineWidth: (weight - 2) * s / 100, lineCap: .round))
            }
        }
    }

    // Same geometry as the SVG on the design canvas (100×100, y down).
    static let clock = Path { p in
        // From 3 o'clock round through 6, 9 and 12 to 1:30 (y points down, so clockwise: false is clockwise on screen).
        p.addArc(center: CGPoint(x: 50, y: 50), radius: 26, startAngle: .degrees(0), endAngle: .degrees(315), clockwise: false)
        p.move(to: CGPoint(x: 50, y: 50))
        p.addLine(to: CGPoint(x: 76, y: 50))
    }
    static let bells = Path { p in
        p.move(to: CGPoint(x: 18, y: 26))
        p.addArc(center: CGPoint(x: 33.98, y: 26.82), radius: 16, startAngle: .degrees(182.94), endAngle: .degrees(292.1), clockwise: false)
        p.closeSubpath()
        p.move(to: CGPoint(x: 60, y: 12))
        p.addArc(center: CGPoint(x: 66.02, y: 26.82), radius: 16, startAngle: .degrees(247.9), endAngle: .degrees(357.06), clockwise: false)
        p.closeSubpath()
    }
    static let legs = Path { p in
        p.move(to: CGPoint(x: 32, y: 78)); p.addLine(to: CGPoint(x: 26, y: 85))
        p.move(to: CGPoint(x: 68, y: 78)); p.addLine(to: CGPoint(x: 74, y: 85))
    }
}

/// App icon artwork on the macOS grid (824-pt tile on a 1024 canvas). build.sh exports it to AppIcon.icns.
struct AppIconView: View {
    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let tile = side * 0.805
            let shape = RoundedRectangle(cornerRadius: tile * 0.2237, style: .continuous)
            ZStack {
                shape
                    .fill(LinearGradient(colors: [Color(hex: 0xFF8A24), Color(hex: 0xE56500)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.5, side * 0.004)))
                    .frame(width: tile, height: tile)
                    .shadow(color: .black.opacity(0.3), radius: side * 0.02, y: side * 0.012)
                LogoMark(weight: side < 64 ? 12 : 9)  // thicker when tiny so the G survives
                    .foregroundStyle(.white)
                    .frame(width: tile * 0.76, height: tile * 0.76)
                    .shadow(color: Color(hex: 0x7A3000).opacity(0.35), radius: side * 0.012, y: side * 0.006)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// The coloured menu bar pill, rendered to an image (status items drop colour from template images).
struct PillView: View {
    let state: BarState
    let bg: Color
    let fg: Color
    var outline: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if state.warning { Image(systemName: "exclamationmark.circle") } else { LogoMark(weight: 11).frame(width: 15, height: 15) }
            Text(state.text)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(fg)
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(Capsule().fill(bg))
        .overlay(Capsule().strokeBorder(outline ?? Color.white.opacity(0.3), lineWidth: outline == nil ? 1 : 1.5))
    }
}
