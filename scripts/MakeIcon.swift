import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// A dark/light aperture: the same split circle as the grayscale menu bar state.
let files: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x")
]
guard CommandLine.arguments.count == 2 else { exit(2) }
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let paper = CGColor(red: 0.96, green: 0.952, blue: 0.93, alpha: 1)
let ink = CGColor(red: 0.115, green: 0.122, blue: 0.138, alpha: 1)
let aperture = CGRect(x: 276, y: 276, width: 472, height: 472)
let tile = CGRect(x: 104, y: 104, width: 816, height: 816)
for (size, name) in files {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 190, cornerHeight: 190, transform: nil))
    ctx.clip()
    for (right, background, mark) in [(false, paper, ink), (true, ink, paper)] {
        ctx.saveGState()
        let half = CGRect(x: right ? 512 : 0, y: 0, width: 512, height: 1024)
        ctx.clip(to: half)
        ctx.setFillColor(background)
        ctx.fill(half)
        ctx.setStrokeColor(mark)
        ctx.setFillColor(mark)
        if right {
            ctx.fillEllipse(in: aperture.insetBy(dx: -23, dy: -23))
        } else {
            ctx.setLineWidth(46)
            ctx.strokeEllipse(in: aperture)
        }
        ctx.restoreGState()
    }
    let path = out.appendingPathComponent("icon_\(name).png")
    guard let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil),
          let image = ctx.makeImage() else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
}
