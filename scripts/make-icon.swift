import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.025, green: 0.035, blue: 0.05, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let cyan = NSColor.white
for i in 0..<4 {
    let ring = NSBezierPath(ovalIn: NSRect(x: 195-Double(i)*12, y: 195-Double(i)*12, width: 634+Double(i)*24, height: 634+Double(i)*24))
    cyan.withAlphaComponent(i == 0 ? 0.45 : 0.035).setStroke()
    ring.lineWidth = i == 0 ? 2 : 12
    ring.stroke()
}
for strand in 0..<9 {
    let line = NSBezierPath()
    for step in 0...200 {
        let t = Double(step)/200
        let x = 210+t*604
        let y = 512 + sin(t * Double.pi * 4 + Double(strand)*0.32) * sin(t * .pi) * 140
        if step == 0 { line.move(to: NSPoint(x: x, y: y)) } else { line.line(to: NSPoint(x: x, y: y)) }
    }
    cyan.withAlphaComponent(strand == 4 ? 1 : 0.27).setStroke(); line.lineWidth = strand == 4 ? 5 : 2; line.stroke()
}
for x in [210.0,814] {
    cyan.setFill(); NSBezierPath(ovalIn: NSRect(x: x-9,y: 503,width: 18,height: 18)).fill()
    cyan.withAlphaComponent(0.4).setStroke()
    let ring=NSBezierPath(ovalIn:NSRect(x:x-26,y:486,width:52,height:52));ring.lineWidth=2;ring.stroke()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "AirBand/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
