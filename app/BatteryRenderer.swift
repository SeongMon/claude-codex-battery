// Menu bar battery icon renderer — ports the widget JS's pixel canvas, font, and geometry as-is
// (Builds CGImage directly instead of PNG encoding. Pixel placement matches the JS 1:1)
import Cocoa

struct BattItem {
  let label: String // "C5"·"CW"·"CF"·"X5"·"XW"·"X" — the first letter is the group (C/X)
  let remain: Double? // remaining % (nil means an empty capsule)
}

// 4x6 pixel font (big preset)
private let FONT46: [Character: [String]] = [
  "0": ["0110", "1001", "1001", "1001", "1001", "0110"],
  "1": ["0010", "0110", "0010", "0010", "0010", "0111"],
  "2": ["0110", "1001", "0010", "0100", "1000", "1111"],
  "3": ["1110", "0001", "0110", "0001", "1001", "0110"],
  "4": ["0010", "0110", "1010", "1111", "0010", "0010"],
  "5": ["1111", "1000", "1110", "0001", "1001", "0110"],
  "6": ["0110", "1000", "1110", "1001", "1001", "0110"],
  "7": ["1111", "0001", "0010", "0100", "0100", "0100"],
  "8": ["0110", "1001", "0110", "1001", "1001", "0110"],
  "9": ["0110", "1001", "1001", "0111", "0001", "0110"],
  "C": ["0110", "1001", "1000", "1000", "1001", "0110"],
  "X": ["1001", "1001", "0110", "0110", "1001", "1001"],
]
// 3x5 classic pixel font (small preset)
private let FONT35: [Character: [String]] = [
  "0": ["111", "101", "101", "101", "111"],
  "1": ["010", "110", "010", "010", "111"],
  "2": ["111", "001", "111", "100", "111"],
  "3": ["111", "001", "111", "001", "111"],
  "4": ["101", "101", "111", "001", "001"],
  "5": ["111", "100", "111", "001", "111"],
  "6": ["111", "100", "111", "101", "111"],
  "7": ["111", "001", "001", "001", "001"],
  "8": ["111", "101", "111", "101", "111"],
  "9": ["111", "101", "111", "001", "111"],
  "C": ["111", "100", "100", "100", "111"],
  "X": ["101", "101", "010", "101", "101"],
]

// Per-preset geometry (same values as the JS PRESET)
private struct Preset {
  let font: [Character: [String]]
  let adv: (Character) -> Int // letter spacing (in big, only '1' gets 4px kerning)
  let bw, bh, capw, gap, ggap, pad, lblgap, H, dy: Int
}

private let PRESET_BIG = Preset(font: FONT46, adv: { $0 == "1" ? 4 : 5 },
                                bw: 18, bh: 10, capw: 20, gap: 5, ggap: 10, pad: 2, lblgap: 3, H: 12, dy: 3)
private let PRESET_SMALL = Preset(font: FONT35, adv: { _ in 4 },
                                  bw: 14, bh: 9, capw: 16, gap: 3, ggap: 7, pad: 1, lblgap: 2, H: 9, dy: 2)

let SIZE_FILE = "\(STATE_DIR)/.batt-size"
func currentBattSize() -> String {
  let s = (try? String(contentsOfFile: SIZE_FILE, encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  return s == "big" ? "big" : "small"
}

private typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

// Logical pixel canvas (SCALE=2 — draws at 2x pixels for Retina)
private final class Canvas {
  static let SCALE = 2
  let wl: Int, hl: Int, w: Int, h: Int
  var buf: [UInt8]
  init(_ wl: Int, _ hl: Int) {
    self.wl = wl
    self.hl = hl
    w = wl * Canvas.SCALE
    h = hl * Canvas.SCALE
    buf = [UInt8](repeating: 0, count: w * h * 4)
  }

  func set(_ x: Int, _ y: Int, _ col: RGB) {
    if x < 0 || y < 0 || x >= wl || y >= hl { return }
    for dy in 0 ..< Canvas.SCALE {
      for dx in 0 ..< Canvas.SCALE {
        let px = ((y * Canvas.SCALE + dy) * w + (x * Canvas.SCALE + dx)) * 4
        buf[px] = col.r
        buf[px + 1] = col.g
        buf[px + 2] = col.b
        buf[px + 3] = 255
      }
    }
  }

  func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ col: RGB) {
    for j in 0 ..< rh { for i in 0 ..< rw { set(x + i, y + j, col) } }
  }

  // Rounded border leaving 1px open at the corners
  func stroke(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ col: RGB) {
    for i in 1 ..< max(1, rw - 1) {
      set(x + i, y, col)
      set(x + i, y + rh - 1, col)
    }
    for j in 1 ..< max(1, rh - 1) {
      set(x, y + j, col)
      set(x + rw - 1, y + j, col)
    }
  }
}

// Actual macOS battery indicator colors (Apple HIG system colors)
private func heatRemain(_ r: Double, dark: Bool) -> RGB {
  if r <= 20 { return dark ? (255, 69, 58) : (255, 59, 48) } // systemRed
  if r < 50 { return dark ? (255, 214, 10) : (255, 204, 0) } // systemYellow
  return dark ? (48, 209, 88) : (52, 199, 89) // systemGreen
}

// 100% remaining = golden battery (a two-tone gold distinct from the warning yellow)
func isGolden(_ remain: Double?) -> Bool { (remain ?? 0) >= 99.5 }
private func goldBase(_ dark: Bool) -> RGB { dark ? (255, 184, 0) : (255, 170, 0) }
private func goldHi(_ dark: Bool) -> RGB { dark ? (255, 226, 110) : (255, 214, 90) }

// Full span of the glint sweep — the length needed for the diagonal to fully cross the capsule
func batteryGlintSpan() -> Int {
  let p = currentBattSize() == "small" ? PRESET_SMALL : PRESET_BIG
  return p.bw + p.bh
}

// When altCol/boundaryX is set: if pixel x is left of the fill boundary, use altCol (contrast over the bright fill); if right, use col
@discardableResult
private func drawNum(_ cv: Canvas, _ p: Preset, _ x: Int, _ y: Int, _ str: String,
                     _ col: RGB, _ altCol: RGB? = nil, _ boundaryX: Int = 0) -> Int {
  var cx = x
  for ch in str {
    if let g = p.font[ch] {
      for (r, rowStr) in g.enumerated() {
        for (c, bit) in rowStr.enumerated() where bit == "1" {
          let px = cx + c
          if let alt = altCol, px < boundaryX { cv.set(px, y + r, alt) }
          else { cv.set(px, y + r, col) }
        }
      }
    }
    cx += p.adv(ch)
  }
  return cx
}

private func numW(_ p: Preset, _ s: String) -> Int { s.reduce(0) { $0 + p.adv($1) } - 1 }

// One capsule: border + remaining-fill + remaining number inside (100 included, always shown)
// 100% is two-tone gold; when glintX is set, a diagonal glint sweep passes over the gold capsule
private func drawCapsule(_ cv: Canvas, _ p: Preset, _ x: Int, _ midY: Int,
                         _ remain: Double?, _ ink: RGB, _ dark: Bool, _ glintX: Int?) {
  let by = midY - p.bh / 2
  cv.stroke(x, by, p.bw, p.bh, ink)
  cv.rect(x + p.bw, by + 3, 2, p.bh - 6, ink) // terminal
  guard let remain = remain else { return }
  let innerW = p.bw - 4
  let v = max(0, min(100, remain))
  let fw = Int((v / 100 * Double(innerW)).rounded())
  let golden = isGolden(remain)
  if fw > 0 {
    if golden {
      cv.rect(x + 2, by + 2, fw, p.bh - 4, goldBase(dark))
      cv.rect(x + 2, by + 2, fw, 2, goldHi(dark)) // top highlight
    } else {
      cv.rect(x + 2, by + 2, fw, p.bh - 4, heatRemain(remain, dark: dark))
    }
  }
  if golden, let g = glintX {
    for j in 0 ..< (p.bh - 4) {
      let gx = x + 2 + g - j // diagonal (down-left)
      if gx >= x + 2, gx < x + 2 + fw {
        cv.set(gx, by + 2 + j, (255, 255, 240))
        if gx + 1 < x + 2 + fw { cv.set(gx + 1, by + 2 + j, (255, 240, 170)) }
      }
    }
  }
  let s = String(Int(v.rounded()))
  let tx = x + (p.bw - numW(p, s)) / 2
  // Pixels over the fill (bright system color) get a dark number, over the empty background get ink → contrast is guaranteed everywhere
  drawNum(cv, p, tx, midY - p.dy, s, ink, (30, 30, 30), x + 2 + fw)
}

// Draw one cat frame into the canvas (shares ink with the batteries; accents fixed)
private func drawCat(_ cv: Canvas, _ x: Int, _ y: Int, _ style: CatStyle, _ state: CatState, _ frame: Int, _ ink: RGB) {
  let grid = catFrame(style, state, frame)
  for (r, rowStr) in grid.enumerated() {
    for (c, ch) in rowStr.enumerated() {
      switch ch {
      case "A", "z": cv.set(x + c, y + r, ink)
      case "o": cv.set(x + c, y + r, (255, 150, 50))
      case "r": cv.set(x + c, y + r, (255, 70, 60))
      case "b": cv.set(x + c, y + r, (90, 180, 255))
      case "p": cv.set(x + c, y + r, (255, 150, 170)) // Nyan-style pink blush
      default: break
      }
    }
  }
}

// N capsules + group label (C/X) → NSImage (2x pixels; the caller scales down to the display size)
// With `cat`, the pixel mascot rides alongside the batteries (see renderModernBatteryImage).
func renderBatteryImage(dark: Bool, items: [BattItem], glintX: Int? = nil,
                        cat: CatState? = nil, catFrameIndex: Int = 0) -> NSImage? {
  return renderModernBatteryImage(dark: dark, items: items, cat: cat, catFrameIndex: catFrameIndex)
}

// The mascot from CatSprite.swift, painted one square per sprite pixel so its pixel grammar
// survives next to the smooth capsules. `scale` sizes that square: the sprite grid is drawn a
// little larger than the batteries' own units so the face still reads at menu bar size. The grid
// runs top-down while the context is bottom-up, so rows are flipped.
private func drawCatSprite(_ ctx: CGContext, x: Int, canvasHeight: Int, style: CatStyle,
                           state: CatState, frame: Int, ink: NSColor, scale: CGFloat) {
  let grid = catFrame(style, state, frame)
  let baseY = (CGFloat(canvasHeight) - CGFloat(CAT_H) * scale) / 2
  ctx.saveGState()
  ctx.setShouldAntialias(false)
  for (r, row) in grid.enumerated() {
    for (c, ch) in row.enumerated() {
      let colour: NSColor
      switch ch {
      case "A", "z": colour = ink
      case "o": colour = NSColor(srgbRed: 1.0, green: 150 / 255, blue: 50 / 255, alpha: 1)
      case "r": colour = NSColor(srgbRed: 1.0, green: 70 / 255, blue: 60 / 255, alpha: 1)
      case "b": colour = NSColor(srgbRed: 90 / 255, green: 180 / 255, blue: 1.0, alpha: 1)
      case "p": colour = NSColor(srgbRed: 1.0, green: 150 / 255, blue: 170 / 255, alpha: 1)
      default: continue
      }
      ctx.setFillColor(colour.cgColor)
      ctx.fill(CGRect(x: CGFloat(x) + CGFloat(c) * scale,
                      y: baseY + CGFloat(CAT_H - 1 - r) * scale,
                      width: scale, height: scale))
    }
  }
  ctx.restoreGState()
}

// Smooth macOS-style battery indicators. Usage groups keep their C/X label, while
// the charge is communicated by the familiar rounded outline and coloured fill.
private func renderModernBatteryImage(dark: Bool, items: [BattItem],
                                      cat: CatState? = nil, catFrameIndex: Int = 0) -> NSImage? {
  let scale = 2
  let height = 18
  let labelWidth = 9
  let bodyWidth = 27
  let bodyHeight = 12
  let terminalWidth = 3
  let itemGap = 5
  let groupGap = 5
  let pad = 2
  let catGap = 3

  // The mascot leads the row, at the left edge ahead of every battery (as upstream draws it), drawn
  // well above its native grid so the face reads at this build's compact icon size. Whole device
  // pixels land on the halves (1.5 → 3, 2.0 → 4 in this 2x context); other values sample a little
  // unevenly, which is invisible at menu bar size but shows up when the artwork is magnified.
  let catStyle = currentCatStyle()
  let mascot: CatState? = catStyle == .none ? nil : cat
  let catScale: CGFloat = 1.8
  let catSpan = mascot != nil ? Int((CGFloat(CAT_W) * catScale).rounded()) + catGap : 0

  var width = pad * 2 + catSpan
  var previousGroup: Character? = nil
  for item in items {
    let group = item.label.first ?? "?"
    if group != previousGroup {
      if previousGroup != nil { width += groupGap }
      width += labelWidth
      previousGroup = group
    } else {
      width += itemGap
    }
    width += bodyWidth + terminalWidth
  }

  guard let context = CGContext(data: nil, width: width * scale, height: height * scale,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
  context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
  context.setAllowsAntialiasing(true)
  context.setShouldAntialias(true)

  let outline = dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.18, alpha: 1)
  let muted = dark ? NSColor(white: 0.72, alpha: 1) : NSColor(white: 0.38, alpha: 1)
  var x = pad
  previousGroup = nil

  if let m = mascot {
    drawCatSprite(context, x: x, canvasHeight: height, style: catStyle,
                  state: m, frame: catFrameIndex, ink: outline, scale: catScale)
    x += catSpan
  }

  for item in items {
    let group = item.label.first ?? "?"
    if group != previousGroup {
      if previousGroup != nil { x += groupGap }
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
        .foregroundColor: outline
      ]
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
      String(group).draw(at: NSPoint(x: x, y: 4), withAttributes: attributes)
      NSGraphicsContext.restoreGraphicsState()
      x += labelWidth
      previousGroup = group
    } else {
      x += itemGap
    }

    let bodyY = (height - bodyHeight) / 2
    let bodyRect = CGRect(x: x, y: bodyY, width: bodyWidth, height: bodyHeight)
    let outlinePath = CGPath(roundedRect: bodyRect, cornerWidth: 3.2, cornerHeight: 3.2, transform: nil)
    context.addPath(outlinePath)
    context.setStrokeColor(outline.cgColor)
    context.setLineWidth(1.35)
    context.strokePath()

    let terminalRect = CGRect(x: CGFloat(x + bodyWidth + 1), y: CGFloat(bodyY) + 3.5,
                              width: CGFloat(terminalWidth - 1), height: CGFloat(bodyHeight - 7))
    context.addPath(CGPath(roundedRect: terminalRect, cornerWidth: 1, cornerHeight: 1, transform: nil))
    context.setFillColor(outline.cgColor)
    context.fillPath()

    if let remaining = item.remain {
      let level = max(0, min(100, remaining))
      let inner = bodyRect.insetBy(dx: 2.4, dy: 2.4)
      let fillWidth = inner.width * CGFloat(level) / 100
      if fillWidth > 0.5 {
        let colour: NSColor = level <= 20 ? .systemRed : (level <= 40 ? .systemOrange : .systemGreen)
        let fillRect = CGRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height)
        context.addPath(CGPath(roundedRect: fillRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        context.setFillColor(colour.cgColor)
        context.fillPath()
      }
    } else {
      context.setStrokeColor(muted.cgColor)
      context.setLineWidth(1)
      context.move(to: CGPoint(x: bodyRect.minX + 7, y: bodyRect.midY))
      context.addLine(to: CGPoint(x: bodyRect.maxX - 7, y: bodyRect.midY))
      context.strokePath()
    }
    x += bodyWidth + terminalWidth
  }

  guard let cgImage = context.makeImage() else { return nil }
  return NSImage(cgImage: cgImage, size: NSSize(width: width * scale, height: height * scale))
}

private func renderLegacyBatteryImage(dark: Bool, items: [BattItem], glintX: Int? = nil,
                                      cat: CatState? = nil, catFrameIndex: Int = 0) -> NSImage? {
  let p = currentBattSize() == "small" ? PRESET_SMALL : PRESET_BIG
  let ink: RGB = dark ? (235, 235, 235) : (45, 45, 45)
  let catStyle = currentCatStyle()
  let catSpan = (cat != nil && catStyle != .none) ? CAT_W + 3 : 0
  // Compute width (including group label)
  var W = p.pad * 2 + catSpan
  var pg: Character? = nil
  for item in items {
    let g = item.label.first!
    if g != pg {
      if pg != nil { W += p.ggap }
      W += numW(p, String(g)) + p.lblgap
      pg = g
    } else { W += p.gap }
    W += p.capw
  }
  let cv = Canvas(max(W, 8), p.H)
  let midY = p.H / 2
  var x = p.pad
  if let c = cat, catStyle != .none {
    drawCat(cv, x, max(0, (p.H - CAT_H) / 2), catStyle, c, catFrameIndex, ink)
    x += catSpan
  }
  pg = nil
  for item in items {
    let g = item.label.first!
    if g != pg {
      if pg != nil { x += p.ggap }
      drawNum(cv, p, x, midY - p.dy, String(g), ink) // group label C or X
      x += numW(p, String(g)) + p.lblgap
      pg = g
    } else { x += p.gap }
    drawCapsule(cv, p, x, midY, item.remain, ink, dark, glintX)
    x += p.capw
  }
  guard let provider = CGDataProvider(data: Data(cv.buf) as CFData),
        let cg = CGImage(width: cv.w, height: cv.h, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: cv.w * 4, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false,
                         intent: .defaultIntent)
  else { return nil }
  return NSImage(cgImage: cg, size: NSSize(width: cv.w, height: cv.h))
}
