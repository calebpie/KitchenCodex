// px <png> <scale> row <y_pt> [x0_pt x1_pt] [tol]   -> color runs along a row, in points
// px <png> <scale> col <x_pt> [y0_pt y1_pt] [tol]   -> color runs along a column
// px <png> <scale> at <x_pt> <y_pt>                 -> pixel color (sRGB hex) at the pixel containing that point
import Foundation
import CoreGraphics
import ImageIO

let a = CommandLine.arguments
guard a.count >= 5, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil), let scale = Double(a[2]) else { print("usage"); exit(1) }
let W = img.width, H = img.height
var buf = [UInt8](repeating: 0, count: W * H * 4)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
func px(_ x: Int, _ y: Int) -> (Int, Int, Int) { let i = (y * W + x) * 4; return (Int(buf[i]), Int(buf[i+1]), Int(buf[i+2])) }
func hex(_ c: (Int, Int, Int)) -> String { String(format: "#%02X%02X%02X", c.0, c.1, c.2) }
func dist(_ p: (Int, Int, Int), _ q: (Int, Int, Int)) -> Int { max(abs(p.0-q.0), abs(p.1-q.1), abs(p.2-q.2)) }
func pt(_ p: Int) -> String { String(format: "%.1f", Double(p) / scale) }
let mode = a[3]
if mode == "at" {
    let x = Int(Double(a[4])! * scale), y = Int(Double(a[5])! * scale); print(hex(px(x, y))); exit(0)
}
let fixed = Int(Double(a[4])! * scale)
let len = mode == "row" ? W : H
let lo = a.count > 6 ? max(0, Int(Double(a[5])! * scale)) : 0
let hi = a.count > 6 ? min(len, Int(Double(a[6])! * scale)) : len
let tol = a.count > 7 ? Int(a[7])! : 6
var start = lo; var ref = mode == "row" ? px(lo, fixed) : px(fixed, lo)
func emit(_ s: Int, _ e: Int, _ c: (Int, Int, Int)) { print("\(pt(s))–\(pt(e)) pt  (\(e - s) px)  \(hex(c))") }
for i in (lo + 1)..<hi {
    let c = mode == "row" ? px(i, fixed) : px(fixed, i)
    if dist(c, ref) > tol { emit(start, i, ref); start = i; ref = c }
}
emit(start, hi, ref)
