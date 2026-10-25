import Foundation
import CoreGraphics
import ImageIO

struct Command: Decodable { let op: String; let values: [Double] }
struct Layer: Decodable { let commands: [Command]; let fill: String; let stroke: String; let width: Double; let evenOdd: Bool }
struct Artwork: Decodable { let background: String; let paths: [Layer] }
func color(_ hex: String) -> CGColor {
    let raw = String(hex.dropFirst())
    let value = UInt64(raw, radix: 16)!
    let a = raw.count == 8 ? CGFloat((value >> 24) & 255) / 255 : 1
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, a])!
}
let input = try JSONDecoder().decode(Artwork.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(color(input.background)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
// Adaptive Android masks use the central 72 of 108 units. Let iOS apply its own corner mask.
context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1024 / 72, y: -1024 / 72); context.translateBy(x: -18, y: -18)
for layer in input.paths {
    let path = CGMutablePath()
    for command in layer.commands {
        let v = command.values
        switch command.op {
        case "M": path.move(to: CGPoint(x: v[0], y: v[1]))
        case "L": path.addLine(to: CGPoint(x: v[0], y: v[1]))
        case "Q": path.addQuadCurve(to: CGPoint(x: v[2], y: v[3]), control: CGPoint(x: v[0], y: v[1]))
        case "C": path.addCurve(to: CGPoint(x: v[4], y: v[5]), control1: CGPoint(x: v[0], y: v[1]), control2: CGPoint(x: v[2], y: v[3]))
        case "Z": path.closeSubpath()
        default: fatalError("Unsupported path")
        }
    }
    context.setFillColor(color(layer.fill)); context.addPath(path); context.fillPath(using: layer.evenOdd ? .evenOdd : .winding)
    if layer.width > 0 {
        context.setStrokeColor(color(layer.stroke)); context.setLineWidth(layer.width)
        context.setLineCap(.butt); context.addPath(path); context.strokePath()
    }
}
let image = context.makeImage()!
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
