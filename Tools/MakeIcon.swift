import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let entries = [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32), ("icon_32x32@2x",64),
               ("icon_128x128",128), ("icon_128x128@2x",256), ("icon_256x256",256), ("icon_256x256@2x",512),
               ("icon_512x512",512), ("icon_512x512@2x",1024)]
for (name, pixels) in entries {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 205, cornerHeight: 205, transform: nil))
    context.clip()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [CGColor(red: 0.72, green: 0.35, blue: 0.22, alpha: 1),
                                       CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 700, y: 60), end: CGPoint(x: 200, y: 960), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.setStrokeColor(CGColor(red: 0.98, green: 0.976, blue: 0.96, alpha: 1))
    context.setLineWidth(57); context.setLineCap(.round); context.setLineJoin(.round)
    context.move(to: CGPoint(x: 280, y: 625)); context.addLine(to: CGPoint(x: 744, y: 625))
    context.move(to: CGPoint(x: 646, y: 723)); context.addLine(to: CGPoint(x: 744, y: 625)); context.addLine(to: CGPoint(x: 646, y: 527))
    context.move(to: CGPoint(x: 744, y: 395)); context.addLine(to: CGPoint(x: 280, y: 395))
    context.move(to: CGPoint(x: 378, y: 493)); context.addLine(to: CGPoint(x: 280, y: 395)); context.addLine(to: CGPoint(x: 378, y: 297))
    context.strokePath()
    let url = destination.appendingPathComponent(name + ".png")
    let image = context.makeImage()!
    let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { exit(1) }
}
