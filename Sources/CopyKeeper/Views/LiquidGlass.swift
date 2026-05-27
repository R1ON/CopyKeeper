import SwiftUI
import AppKit

// MARK: - Liquid Glass design system
//
// A small toolkit that approximates the macOS "Liquid Glass" look on systems
// that predate the real `.glassEffect` API. The recipe everywhere is the same:
//   1. a translucent frosted fill (real blur for big surfaces, a white sheen
//      gradient for small floating plates),
//   2. a specular rim — a bright top-leading edge that catches light and fades
//      around the shape, drawn with `.plusLighter` so it reads as glass,
//   3. a soft drop shadow so the element floats above what's behind it.

// MARK: Tunables

enum Glass {
    /// Neutral darkening kept low for legibility of white text on light desktops.
    static let contrast = 0.14
    /// Top → bottom white sheen on frosted plates.
    static let sheenTop = 0.20
    static let sheenBottom = 0.05
}

// MARK: Specular rim

/// The signature glass edge: bright top-leading highlight fading around the shape.
func glassRim(_ strength: Double = 1.0) -> LinearGradient {
    LinearGradient(
        colors: [
            Color.white.opacity(0.75 * strength),
            Color.white.opacity(0.22 * strength),
            Color.white.opacity(0.06 * strength),
            Color.white.opacity(0.30 * strength)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: Frosted fills

/// A real blurred surface (use for large panels / overlays).
struct GlassBlur: View {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .withinWindow
    var contrast: Double = Glass.contrast

    var body: some View {
        ZStack {
            VisualEffectView(material: material, blendingMode: blending)
            LinearGradient(
                colors: [Color.white.opacity(Glass.sheenTop * 0.6), .clear,
                         Color.black.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            )
            Color.black.opacity(contrast)
        }
    }
}

/// A gradient-only frosted plate (use for small floating cards/buttons — cheap,
/// and reads as a glass plate layered over the already-blurred panel behind it).
struct GlassPlate: View {
    var top: Double = Glass.sheenTop
    var bottom: Double = Glass.sheenBottom
    var body: some View {
        LinearGradient(
            colors: [Color.white.opacity(top), Color.white.opacity(bottom)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: Reusable modifier

struct LiquidGlassPlate<S: InsettableShape>: ViewModifier {
    let shape: S
    var sheenTop: Double = Glass.sheenTop
    var sheenBottom: Double = Glass.sheenBottom
    var rimStrength: Double = 1.0
    var stroke: Color? = nil          // accent override for highlighted state
    var strokeWidth: CGFloat = 1
    var shadowRadius: CGFloat = 14
    var shadowY: CGFloat = 6
    var shadowOpacity: Double = 0.30

    func body(content: Content) -> some View {
        content
            .background(GlassPlate(top: sheenTop, bottom: sheenBottom))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(glassRim(rimStrength), lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .overlay(accentStroke)
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }

    @ViewBuilder
    private var accentStroke: some View {
        if let stroke {
            shape.strokeBorder(stroke, lineWidth: strokeWidth)
        }
    }
}

extension View {
    /// Frosted glass plate (gradient sheen + specular rim + soft shadow).
    func liquidGlassPlate<S: InsettableShape>(
        _ shape: S,
        sheenTop: Double = Glass.sheenTop,
        sheenBottom: Double = Glass.sheenBottom,
        rimStrength: Double = 1.0,
        stroke: Color? = nil,
        strokeWidth: CGFloat = 1,
        shadowRadius: CGFloat = 14,
        shadowY: CGFloat = 6,
        shadowOpacity: Double = 0.30
    ) -> some View {
        modifier(LiquidGlassPlate(
            shape: shape, sheenTop: sheenTop, sheenBottom: sheenBottom,
            rimStrength: rimStrength, stroke: stroke, strokeWidth: strokeWidth,
            shadowRadius: shadowRadius, shadowY: shadowY, shadowOpacity: shadowOpacity
        ))
    }

    /// Real-blur glass surface (for overlays / sheets).
    func liquidGlassSurface(cornerRadius: CGFloat,
                            material: NSVisualEffectView.Material = .hudWindow,
                            contrast: Double = Glass.contrast,
                            rimStrength: Double = 1.0,
                            shadowRadius: CGFloat = 28,
                            shadowOpacity: Double = 0.45) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(GlassBlur(material: material, contrast: contrast))
            .clipShape(shape)
            .overlay(shape.strokeBorder(glassRim(rimStrength), lineWidth: 1)
                .blendMode(.plusLighter))
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: 12)
    }

    /// A small circular/capsule glass control (top-bar buttons, pills).
    func glassControl<S: InsettableShape>(_ shape: S,
                                          accent: Color? = nil,
                                          rimStrength: Double = 0.8) -> some View {
        liquidGlassPlate(shape,
                         sheenTop: 0.16, sheenBottom: 0.04,
                         rimStrength: rimStrength,
                         stroke: accent,
                         strokeWidth: 1,
                         shadowRadius: 5, shadowY: 2, shadowOpacity: 0.20)
    }
}
