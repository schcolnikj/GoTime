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

/// The coloured menu bar pill, rendered to an image (status items drop colour from template images).
struct PillView: View {
    let state: BarState
    let bg: Color
    let fg: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbol)
            Text(state.text)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(fg)
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(Capsule().fill(bg))
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
    }
}
