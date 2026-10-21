import CoreGraphics
import Foundation

// Keep template artwork vector-based. Coordinates are native 28×18 menu-bar points.
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Sources/Pocket/Resources")
let radius: CGFloat = 5

func buddy(centerX: CGFloat) -> CGPath {
    var head = CGPath(ellipseIn: CGRect(x: 34, y: 18, width: 60, height: 58), transform: nil)
    for x: CGFloat in [33, 95] {
        head = head.union(CGPath(ellipseIn: CGRect(x: x - 6, y: 43, width: 12, height: 16), transform: nil), using: .winding)
    }
    let scale: CGFloat = 14 / 74
    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                                      tx: centerX - 64 * scale, ty: 9 + 47 * scale)
    let path = CGMutablePath()
    path.addPath(head.copy(using: &transform)!)
    for x in [centerX - 2, centerX + 2] {
        path.addEllipse(in: CGRect(x: x - 0.6, y: 8.4, width: 1.2, height: 1.8))
    }
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: centerX - 1.3, y: 6.65))
    smile.addLine(to: CGPoint(x: centerX, y: 5.85))
    smile.addLine(to: CGPoint(x: centerX + 1.3, y: 6.65))
    path.addPath(smile.copy(strokingWithWidth: 0.9, lineCap: .round, lineJoin: .round, miterLimit: 10))
    return path
}

for unread in [false, true] {
    let name = unread ? "capsule-unread" : "capsule"
    var bounds = CGRect(x: 0, y: 0, width: 28, height: 18)
    let context = CGContext(output.appendingPathComponent(name + ".pdf") as CFURL, mediaBox: &bounds, nil)!
    context.beginPDFPage(nil)
    let artwork = CGMutablePath()
    artwork.addRoundedRect(in: CGRect(x: 0, y: 1, width: 28, height: 16), cornerWidth: radius, cornerHeight: radius)
    artwork.addPath(buddy(centerX: unread ? 9.5 : 14))
    if unread { artwork.addEllipse(in: CGRect(x: 19, y: 6, width: 6, height: 6)) }
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.addPath(artwork)
    context.drawPath(using: .eoFill)
    context.endPDFPage()
    context.closePDF()
    print("Wrote \(name).pdf, 28×18pt, \(Int(radius))pt corners")
}
