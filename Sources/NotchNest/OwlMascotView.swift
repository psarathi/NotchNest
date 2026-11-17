import SwiftUI

/// Original vector owl mascot drawn natively in SwiftUI with periodic blinking and state expressions.
struct OwlMascotView: View {
    var size: CGFloat = 22
    var isFocusing: Bool = false
    var isHovering: Bool = false
    var pulse: Bool = false
    var animationsEnabled: Bool = true

    @State private var isBlinking = false
    @State private var blinkTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isFocusing && animationsEnabled {
                Circle()
                    .fill(Color.amberGlow.opacity(0.24))
                    .frame(width: size * 1.28, height: size * 1.28)
                    .blur(radius: size * 0.16)
            }

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let cx = w / 2

                // Outer owl head silhouette with subtle ear tufts
                var head = Path()
                head.move(to: CGPoint(x: w * 0.20, y: h * 0.14))
                head.addLine(to: CGPoint(x: w * 0.34, y: h * 0.24))
                head.addQuadCurve(
                    to: CGPoint(x: w * 0.66, y: h * 0.24),
                    control: CGPoint(x: cx, y: h * 0.19)
                )
                head.addLine(to: CGPoint(x: w * 0.80, y: h * 0.14))
                head.addQuadCurve(
                    to: CGPoint(x: w * 0.86, y: h * 0.56),
                    control: CGPoint(x: w * 0.90, y: h * 0.34)
                )
                head.addQuadCurve(
                    to: CGPoint(x: cx, y: h * 0.90),
                    control: CGPoint(x: w * 0.82, y: h * 0.86)
                )
                head.addQuadCurve(
                    to: CGPoint(x: w * 0.14, y: h * 0.56),
                    control: CGPoint(x: w * 0.18, y: h * 0.86)
                )
                head.addQuadCurve(
                    to: CGPoint(x: w * 0.20, y: h * 0.14),
                    control: CGPoint(x: w * 0.10, y: h * 0.34)
                )
                head.closeSubpath()

                context.fill(head, with: .color(Color(red: 0.22, green: 0.24, blue: 0.30)))
                context.stroke(head, with: .color(.white.opacity(0.22)), lineWidth: max(0.8, w * 0.035))

                // Subtle brow/facial disc
                let eyeRadius = w * 0.155
                let eyeY = h * 0.50
                let leftEyeCenter = CGPoint(x: w * 0.36, y: eyeY)
                let rightEyeCenter = CGPoint(x: w * 0.64, y: eyeY)

                let discColor = Color(red: 0.15, green: 0.17, blue: 0.22)
                for center in [leftEyeCenter, rightEyeCenter] {
                    let discRect = CGRect(
                        x: center.x - eyeRadius * 1.28,
                        y: center.y - eyeRadius * 1.28,
                        width: eyeRadius * 2.56,
                        height: eyeRadius * 2.56
                    )
                    context.fill(Path(ellipseIn: discRect), with: .color(discColor))
                }

                // Eyes (blink or happy pulse)
                let eyeScaleY: CGFloat = (isBlinking && animationsEnabled) ? 0.12 : 1.0
                let irisColor = isFocusing ? Color.amberGlow : Color(red: 0.96, green: 0.72, blue: 0.22)

                for center in [leftEyeCenter, rightEyeCenter] {
                    if pulse && animationsEnabled {
                        var arc = Path()
                        arc.addArc(
                            center: CGPoint(x: center.x, y: center.y + eyeRadius * 0.25),
                            radius: eyeRadius * 0.82,
                            startAngle: .degrees(205),
                            endAngle: .degrees(335),
                            clockwise: false
                        )
                        context.stroke(
                            arc,
                            with: .color(irisColor),
                            style: StrokeStyle(lineWidth: max(1.4, w * 0.08), lineCap: .round)
                        )
                    } else {
                        let eh = eyeRadius * 2 * eyeScaleY
                        let irisRect = CGRect(
                            x: center.x - eyeRadius,
                            y: center.y - eh / 2,
                            width: eyeRadius * 2,
                            height: eh
                        )
                        context.fill(Path(ellipseIn: irisRect), with: .color(irisColor))

                        if eyeScaleY > 0.35 {
                            let pupilR = eyeRadius * 0.52
                            let pupilRect = CGRect(
                                x: center.x - pupilR,
                                y: center.y - pupilR,
                                width: pupilR * 2,
                                height: pupilR * 2
                            )
                            context.fill(Path(ellipseIn: pupilRect), with: .color(.black.opacity(0.88)))

                            let glintR = eyeRadius * 0.22
                            let glintRect = CGRect(
                                x: center.x - eyeRadius * 0.38,
                                y: center.y - eyeRadius * 0.42,
                                width: glintR * 2,
                                height: glintR * 2
                            )
                            context.fill(Path(ellipseIn: glintRect), with: .color(.white.opacity(0.9)))
                        }
                    }
                }

                // Small geometric beak
                var beak = Path()
                beak.move(to: CGPoint(x: cx - w * 0.065, y: h * 0.59))
                beak.addLine(to: CGPoint(x: cx + w * 0.065, y: h * 0.59))
                beak.addLine(to: CGPoint(x: cx, y: h * 0.71))
                beak.closeSubpath()
                context.fill(beak, with: .color(Color(red: 0.96, green: 0.62, blue: 0.18)))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isHovering && animationsEnabled ? -6 : 0))
            .scaleEffect(pulse && animationsEnabled ? 1.16 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: pulse)
            .animation(.easeInOut(duration: 0.11), value: isBlinking)
        }
        .onAppear { startBlinkLoop() }
        .onDisappear { blinkTask?.cancel() }
    }

    private func startBlinkLoop() {
        blinkTask?.cancel()
        blinkTask = Task {
            while !Task.isCancelled {
                let pauseNs = UInt64.random(in: 3_200_000_000...5_400_000_000)
                try? await Task.sleep(nanoseconds: pauseNs)
                guard !Task.isCancelled else { break }
                if animationsEnabled {
                    isBlinking = true
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    isBlinking = false
                }
            }
        }
    }
}
