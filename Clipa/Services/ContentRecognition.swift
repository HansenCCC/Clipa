import AppKit
import ImageIO
import QuickLookThumbnailing

/// 颜色识别：#hex / 裸 hex / rgb()/rgba()/hsl()/hsla() → 规范化色值。
enum ColorParser {
    /// 返回 (规范化展示串, NSColor)；非颜色返回 nil。
    static func parse(_ raw: String) -> (label: String, color: NSColor)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count <= 32, !s.contains("\n") else { return nil }

        if let c = parseHex(s) { return c }
        if let c = parseFunc(s) { return c }
        return nil
    }

    private static func parseHex(_ s: String) -> (String, NSColor)? {
        var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        // 裸 hex 只接受 6 位（避免 123 之类误判），带 # 接受 3/4/6/8
        let allowed: Set<Int> = s.hasPrefix("#") ? [3, 4, 6, 8] : [6]
        guard allowed.contains(hex.count) else { return nil }

        if hex.count == 3 || hex.count == 4 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
        let r, g, b, a: CGFloat
        if hex.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        let label = "#" + hex.uppercased()
        return (label, NSColor(srgbRed: r, green: g, blue: b, alpha: a))
    }

    private static func parseFunc(_ s: String) -> (String, NSColor)? {
        let lower = s.lowercased()
        func nums(_ inner: String) -> [Double] {
            inner.split(whereSeparator: { ",/ ".contains($0) })
                .compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        }
        if lower.hasPrefix("rgb"), let l = s.firstIndex(of: "("), let r = s.firstIndex(of: ")"), l < r {
            let v = nums(String(s[s.index(after: l)..<r]))
            guard v.count >= 3 else { return nil }
            let a = v.count >= 4 ? v[3] : 1
            return (s, NSColor(srgbRed: v[0]/255, green: v[1]/255, blue: v[2]/255, alpha: a))
        }
        if lower.hasPrefix("hsl"), let l = s.firstIndex(of: "("), let r = s.firstIndex(of: ")"), l < r {
            let v = nums(String(s[s.index(after: l)..<r]))
            guard v.count >= 3 else { return nil }
            let a = v.count >= 4 ? v[3] : 1
            return (s, NSColor(hue: v[0]/360, saturation: v[1]/100, brightness: lToB(v[1], v[2]), alpha: a))
        }
        return nil
    }

    // 粗略 HSL→HSB 亮度换算（够色块预览用）
    private static func lToB(_ s: Double, _ l: Double) -> CGFloat { CGFloat(min(1, l/100 + (s/100) * min(l/100, 1 - l/100))) }
}

/// 图片文件识别 + 缩略图。
enum FileRecognition {
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"]

    static func isImage(_ url: URL) -> Bool { imageExts.contains(url.pathExtension.lowercased()) }

    /// 像素尺寸 "W × H"（高效读取，不整图解码）。
    static func dimensions(url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return "\(w) × \(h)"
    }

    static func dimensions(data: Data) -> String? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
    }

    /// 为图片文件生成缩略图（ImageIO，兼容性强），返回 (缓存名, 是否含真实透明)。
    static func makeThumbnail(for url: URL, maxSize: CGFloat = 600) -> (name: String, transparent: Bool)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]),
              let name = ImageCache.shared.save(png) else { return nil }
        return (name, looksTransparent(rep))
    }

    /// 用 QuickLook 为任意文件生成内容缩略图（txt/pdf/psd/sketch/office…）。异步，主线程回调缓存名。
    static func generateQLThumbnail(url: URL, maxSize: CGFloat = 600, completion: @escaping (String?) -> Void) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: url,
                                               size: CGSize(width: maxSize, height: maxSize),
                                               scale: scale,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let cg = rep?.cgImage else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            let png = bitmap.representation(using: .png, properties: [:])
            DispatchQueue.main.async { completion(png.flatMap { ImageCache.shared.save($0) }) }
        }
    }

    static func transparency(data: Data) -> Bool {
        guard let rep = NSBitmapImageRep(data: data) else { return false }
        return looksTransparent(rep)
    }

    /// 采样像素 alpha 判断是否真有透明（非靠扩展名/通道存在与否）。
    static func looksTransparent(_ rep: NSBitmapImageRep) -> Bool {
        guard rep.hasAlpha else { return false }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return false }
        let stepX = max(1, w / 40), stepY = max(1, h / 40)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent < 0.98 { return true }
                x += stepX
            }
            y += stepY
        }
        return false
    }
}
