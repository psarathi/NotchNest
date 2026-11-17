import SwiftUI

/// Curved top-bezel notch silhouette with concave top shoulder ears and rounded bottom corners.
struct NotchSilhouetteShape: Shape {
    var topEarRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topEarRadius, bottomCornerRadius) }
        set {
            topEarRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let ear = min(topEarRadius, width * 0.2, height * 0.45)
        let bottom = min(bottomCornerRadius, (width - ear * 2) * 0.45, height - ear)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Left concave top shoulder ear
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
            control: CGPoint(x: rect.minX + ear, y: rect.minY)
        )

        // Left vertical edge
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - bottom))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + ear, y: rect.maxY)
        )

        // Bottom horizontal edge
        path.addLine(to: CGPoint(x: rect.maxX - ear - bottom, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - ear, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - ear, y: rect.maxY)
        )

        // Right vertical edge
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))

        // Right concave top shoulder ear
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - ear, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
