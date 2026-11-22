import AppKit
// Renders a 1024px app icon: green gradient squircle with a white battery + leaf.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.25).cgColor)
ctx.addPath(path); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(path); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(red: 0.20, green: 0.84, blue: 0.55, alpha: 1).cgColor,
    NSColor(red: 0.05, green: 0.55, blue: 0.62, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
// battery body
let body = CGRect(x: 250, y: 370, width: 470, height: 284)
ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(34)
ctx.addPath(CGPath(roundedRect: body, cornerWidth: 70, cornerHeight: 70, transform: nil)); ctx.strokePath()
ctx.setFillColor(NSColor.white.cgColor)
ctx.addPath(CGPath(roundedRect: CGRect(x: 745, y: 452, width: 40, height: 120), cornerWidth: 18, cornerHeight: 18, transform: nil)); ctx.fillPath()
// fill at 80%
ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
ctx.addPath(CGPath(roundedRect: CGRect(x: 290, y: 410, width: 300, height: 204), cornerWidth: 40, cornerHeight: 40, transform: nil)); ctx.fillPath()
// leaf cut-out
if let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 150, weight: .bold)) {
    let tinted = NSImage(size: leaf.size); tinted.lockFocus()
    NSColor(red: 0.08, green: 0.62, blue: 0.58, alpha: 1).set()
    let r = NSRect(origin: .zero, size: leaf.size); leaf.draw(in: r); r.fill(using: .sourceAtop); tinted.unlockFocus()
    let w = leaf.size.width, h = leaf.size.height
    tinted.draw(in: NSRect(x: 440 - w / 2, y: 512 - h / 2, width: w, height: h))
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
