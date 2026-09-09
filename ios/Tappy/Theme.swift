import SwiftUI
import TappyKit

/// Wise's system: white paper, one lime accent, and a forest-green ink that is almost black
/// but never actually black. Money is shown in the ink; the lime is reserved for the thing you
/// are meant to press. Nothing else gets colour.
enum Theme {
    static let bg = Color.white
    static let lime = Color(red: 0.624, green: 0.910, blue: 0.439)
    static let limePress = Color(red: 0.549, green: 0.847, blue: 0.361)
    static let ink = Color(red: 0.086, green: 0.200, blue: 0.000)
    static let dim = Color(red: 0.420, green: 0.451, blue: 0.420)
    static let surface = Color(red: 0.937, green: 0.937, blue: 0.933)
    static let surfaceDeep = Color(red: 0.902, green: 0.902, blue: 0.894)
    static let hairline = Color(red: 0.878, green: 0.878, blue: 0.871)
    static let up = Color(red: 0.184, green: 0.400, blue: 0.067)
    static let down = Color(red: 0.804, green: 0.169, blue: 0.169)
    static let dangerSoft = Color(red: 0.988, green: 0.902, blue: 0.902)

    static let avatars: [Color] = [
        Color(red: 0.98, green: 0.45, blue: 0.35),
        Color(red: 0.40, green: 0.55, blue: 0.98),
        Color(red: 0.95, green: 0.70, blue: 0.25),
        Color(red: 0.60, green: 0.40, blue: 0.92),
        Color(red: 0.20, green: 0.75, blue: 0.70),
        Color(red: 0.94, green: 0.40, blue: 0.65),
    ]
}

extension Font {
    /// Wise's headline voice: heavy, condensed, shouted in caps. Used only for the one line on
    /// a screen that states what the screen is for.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }
}

/// The mark. Rings closing on a point of contact — the product in one glyph.
struct TappyMark: View {
    var size: CGFloat = 88
    var color: Color = Theme.ink

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(color.opacity(1.0 - Double(ring) * 0.30), lineWidth: size * 0.055)
                    .frame(width: size * (0.40 + CGFloat(ring) * 0.28))
            }
            Circle().fill(color).frame(width: size * 0.16)
        }
        .frame(width: size, height: size)
    }
}

struct LimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(configuration.isPressed ? Theme.limePress : Theme.lime, in: Capsule())
    }
}

struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Theme.surface
    var ink: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Wise's filter row: one filled lime pill, the rest grey.
struct Chip: View {
    let label: String
    var selected = false

    var body: some View {
        Text(label)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(selected ? Theme.lime : Theme.surface, in: Capsule())
    }
}

struct Avatar: View {
    let contact: Contact
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(Theme.avatars[contact.colorIndex])
            Text(contact.initials)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// A bordered circle holding a glyph — Wise's transaction-row and header motif.
struct CircleGlyph: View {
    let systemName: String
    var size: CGFloat = 48
    var filled: Color? = nil

    var body: some View {
        ZStack {
            if let filled {
                Circle().fill(filled)
            } else {
                Circle().stroke(Theme.hairline, lineWidth: 1.5)
            }
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
    }
}
