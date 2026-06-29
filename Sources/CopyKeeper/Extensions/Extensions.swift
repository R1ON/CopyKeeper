import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - CodableColor

struct CodableColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        r = Double(converted.redComponent)
        g = Double(converted.greenComponent)
        b = Double(converted.blueComponent)
        a = Double(converted.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    var color: Color {
        Color(nsColor)
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    func dominantColor() -> NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ciImage,
                                                 kCIInputExtentKey: CIVector(cgRect: extent)]) else {
            return nil
        }
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0
        let a = CGFloat(bitmap[3]) / 255.0

        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    func resized(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(material: NSVisualEffectView.Material = .hudWindow,
         blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Hover affordance for buttons

struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.12 : 0)
            .scaleEffect(hovering ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.1), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

// MARK: - Color parsing (hex / rgb / rgba / hsl / hsla)

func looksLikeColor(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if t.hasPrefix("#"), [4, 5, 7, 9].contains(t.count),
       t.dropFirst().allSatisfy({ $0.isHexDigit }) {
        return true
    }
    if t.range(of: "^rgba?\\([0-9.,%/ ]+\\)$", options: .regularExpression) != nil { return true }
    if t.range(of: "^hsla?\\([0-9.,%/ ]+\\)$", options: .regularExpression) != nil { return true }
    return false
}

private func colorNumbers(in text: String) -> [Double] {
    var numbers: [Double] = []
    let regex = try? NSRegularExpression(pattern: "[0-9]+(?:\\.[0-9]+)?")
    let range = NSRange(text.startIndex..., in: text)
    regex?.enumerateMatches(in: text, range: range) { match, _, _ in
        if let match, let r = Range(match.range, in: text) {
            numbers.append(Double(text[r]) ?? 0)
        }
    }
    return numbers
}

func parseColorString(_ raw: String) -> NSColor? {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = s.lowercased()

    if s.hasPrefix("#") {
        var h = String(s.dropFirst())
        if h.count == 3 || h.count == 4 {
            h = h.flatMap { [String($0), String($0)] }.joined()
        }
        guard h.count == 6 || h.count == 8 else { return nil }
        var value: UInt64 = 0
        Scanner(string: h).scanHexInt64(&value)
        if h.count == 8 {
            return NSColor(srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
                           green: CGFloat((value >> 16) & 0xFF) / 255,
                           blue: CGFloat((value >> 8) & 0xFF) / 255,
                           alpha: CGFloat(value & 0xFF) / 255)
        }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    if lower.hasPrefix("rgb") {
        let n = colorNumbers(in: lower)
        guard n.count >= 3 else { return nil }
        let alpha = n.count >= 4 ? CGFloat(n[3]) : 1
        return NSColor(srgbRed: CGFloat(n[0]) / 255, green: CGFloat(n[1]) / 255,
                       blue: CGFloat(n[2]) / 255, alpha: alpha)
    }

    if lower.hasPrefix("hsl") {
        let n = colorNumbers(in: lower)
        guard n.count >= 3 else { return nil }
        let alpha = n.count >= 4 ? CGFloat(n[3]) : 1
        return NSColor.fromHSL(h: CGFloat(n[0]) / 360,
                               s: CGFloat(n[1]) / 100,
                               l: CGFloat(n[2]) / 100,
                               a: alpha)
    }

    return nil
}

extension NSColor {
    // Convert HSL to an sRGB NSColor (NSColor's HSB is not HSL).
    static func fromHSL(h: CGFloat, s: CGFloat, l: CGFloat, a: CGFloat) -> NSColor {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h * 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        switch hp {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default:    (r, g, b) = (c, 0, x)
        }
        let m = l - c / 2
        return NSColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: a)
    }

    var isLightColor: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.6
    }
}

// MARK: - timeAgo

func timeAgo(_ date: Date) -> String {
    let now = Date()
    let diff = now.timeIntervalSince(date)

    if diff < 60 {
        return Loc.s("только что", "just now")
    } else if diff < 3600 {
        let minutes = Int(diff / 60)
        return Loc.s("\(minutes)м назад", "\(minutes)m ago")
    } else if diff < 86400 {
        let hours = Int(diff / 3600)
        return Loc.s("\(hours)ч назад", "\(hours)h ago")
    } else if diff < 86400 * 2 {
        return Loc.s("вчера", "yesterday")
    } else {
        let days = Int(diff / 86400)
        return Loc.s("\(days)д назад", "\(days)d ago")
    }
}

// MARK: - RoundedCorner Shape

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: [Corner]

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                        radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                        radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                        radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                        radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}
