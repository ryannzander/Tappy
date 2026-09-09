import SwiftUI

/// One light surface throughout. The chat sets the tone — plain, familiar, unintimidating —
/// and the wallet and the approval borrow it so the app never feels like two products stapled
/// together. Weight and scale carry the seriousness instead of darkness: the approval screen is
/// the only place with 56pt type.
enum Theme {
    static let bg = Color.white
    static let surface = Color(red: 0.965, green: 0.965, blue: 0.972)
    static let surfaceAlt = Color(red: 0.937, green: 0.937, blue: 0.949)
    static let hairline = Color(red: 0.898, green: 0.898, blue: 0.914)

    static let ink = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let dim = Color(red: 0.545, green: 0.545, blue: 0.565)

    /// Deep enough to pass as text and as a button fill on white — the Phantom lavender is
    /// beautiful on black and unreadable here.
    static let accent = Color(red: 0.42, green: 0.30, blue: 0.94)
    static let accentSoft = Color(red: 0.929, green: 0.914, blue: 0.996)

    static let up = Color(red: 0.06, green: 0.64, blue: 0.29)
    static let down = Color(red: 0.86, green: 0.15, blue: 0.15)
}

/// The mark. A tap ripple — rings closing on a point of contact, which is the product in one
/// glyph: something touched a thing, and only then did it happen.
struct TappyMark: View {
    var size: CGFloat = 88
    var color: Color = Theme.accent

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

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var ink: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
