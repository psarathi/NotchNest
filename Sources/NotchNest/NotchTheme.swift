import SwiftUI

enum NotchTheme {
    // Main obsidian & surface tokens matching the macOS notch aesthetic
    static let notchBlack = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let obsidianBg = Color(red: 0.055, green: 0.059, blue: 0.075)
    static let cardSurface = Color(red: 0.095, green: 0.102, blue: 0.125)
    static let elevatedSurface = Color(red: 0.14, green: 0.15, blue: 0.185)
    static let hairlineStroke = Color.white.opacity(0.11)

    // Signature matte sage-green Today board tokens
    static let sagePaper = Color(red: 0.765, green: 0.827, blue: 0.741) // #C3D3BD
    static let sagePaperSoft = Color(red: 0.72, green: 0.79, blue: 0.695)
    static let sageInk = Color(red: 0.095, green: 0.145, blue: 0.102)
    static let sageMuted = Color(red: 0.25, green: 0.33, blue: 0.26)
    static let sageBadgeFill = Color(red: 0.14, green: 0.20, blue: 0.15)
    static let sageRowFill = Color.black.opacity(0.055)
    static let sageInputFill = Color.black.opacity(0.07)

    // Subtle slate-lavender accent tokens for mascot & workspace contrast
    static let lavenderCard = Color(red: 0.145, green: 0.137, blue: 0.195)
    static let lavenderAccent = Color(red: 0.61, green: 0.57, blue: 0.75)
    static let lavenderSoft = Color(red: 0.71, green: 0.68, blue: 0.84)

    // Workspace pastel matte lavender Focus card palette
    static let lavenderPaper = Color(red: 0.710, green: 0.667, blue: 0.753)
    static let lavenderInk = Color(red: 0.114, green: 0.102, blue: 0.145)
    static let lavenderPaperMuted = Color(red: 0.30, green: 0.27, blue: 0.36)
    static let lavenderPaperButton = Color(red: 0.36, green: 0.32, blue: 0.43)
    static let lavenderPaperPill = Color.black.opacity(0.085)

    // Workspace matte warm sand/yellow Notepad palette
    static let yellowPaper = Color(red: 0.824, green: 0.761, blue: 0.545)
    static let yellowInk = Color(red: 0.135, green: 0.118, blue: 0.072)
    static let yellowInkNS = NSColor(srgbRed: 0.135, green: 0.118, blue: 0.072, alpha: 1.0)
    static let yellowMuted = Color(red: 0.36, green: 0.32, blue: 0.21)
    static let yellowPillFill = Color.black.opacity(0.07)

    // Signature misty steel-blue 7-day calendar timeline card tokens
    static let steelBluePaper = Color(red: 0.655, green: 0.725, blue: 0.776) // #A7B9C6
    static let steelBlueInk = Color(red: 0.086, green: 0.125, blue: 0.165)
    static let steelBlueMuted = Color(red: 0.24, green: 0.31, blue: 0.37)
    static let steelBlueRowFill = Color.black.opacity(0.075)
    static let steelBlueSelectedCircle = Color(red: 0.11, green: 0.145, blue: 0.185)
    static let calendarHeroCard = Color(red: 0.165, green: 0.184, blue: 0.212)

    // Functional highlight accents
    static let peachAction = Color(red: 0.93, green: 0.64, blue: 0.36)
    static let mintComplete = Color(red: 0.13, green: 0.77, blue: 0.45)
    static let skyWave = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let coralAlert = Color(red: 0.98, green: 0.44, blue: 0.44)
}

extension Color {
    static let amberGlow = Color(red: 0.98, green: 0.75, blue: 0.24)

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// Squircle avatar wrapping OwlMascotView cleanly for the header and Live Activity cards.
struct OwlBadgeView: View {
    var size: CGFloat = 24
    var isFocusing: Bool = false
    var isHovering: Bool = false
    var pulse: Bool = false
    var animationsEnabled: Bool = true
    var showAlertDot: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            NotchTheme.lavenderSoft.opacity(0.95),
                            NotchTheme.lavenderAccent.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    OwlMascotView(
                        size: size * 0.80,
                        isFocusing: isFocusing,
                        isHovering: isHovering,
                        pulse: pulse,
                        animationsEnabled: animationsEnabled
                    )
                )

            if showAlertDot {
                Circle()
                    .fill(NotchTheme.peachAction)
                    .frame(width: max(6, size * 0.28), height: max(6, size * 0.28))
                    .overlay(
                        Circle()
                            .stroke(NotchTheme.notchBlack, lineWidth: 1.5)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }
}

/// Compact 3-bar cyan/mint audio waveform used alongside active focus timer & ambient sound.
struct AnimatedWaveformView: View {
    var isActive: Bool
    var barColor: Color = NotchTheme.skyWave
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 12
    var spacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    let factor: CGFloat = isActive
                        ? CGFloat(0.35 + 0.65 * abs(sin(t * 4.2 + Double(index) * 1.15)))
                        : 0.28
                    Capsule()
                        .fill(barColor)
                        .frame(width: barWidth, height: max(3, maxHeight * factor))
                }
            }
            .frame(height: maxHeight, alignment: .center)
        }
    }
}
