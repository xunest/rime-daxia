import SwiftUI
import AppKit
import CoreText

/// 应用图标：优先用 Resources/AppIcon.png，缺失时回退到代码绘制
enum AppIcon {

    /// 缓存原图，避免每次取图标都读盘解码
    private static let bundled: NSImage? = {
        var candidates: [URL] = []

        // 打包后的 .app：Contents/Resources/AppIcon.png
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") {
            candidates.append(url)
        }
        // build.sh 里以裸可执行文件跑 --export-icons 时，资源在同级目录
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("AppIcon.png"))

        for url in candidates {
            if let img = NSImage(contentsOf: url) { return img }
        }
        return nil
    }()

    static func current(size: CGFloat = 128) -> NSImage {
        render(size: size)
    }

    /// 按目标尺寸产出图标；有内嵌 PNG 就缩放它，否则代码绘制
    static func render(size: CGFloat) -> NSImage {
        guard let src = bundled else { return drawDefault(size: size) }

        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        src.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                 from: .zero,
                 operation: .sourceOver,
                 fraction: 1)
        out.unlockFocus()
        return out
    }

    /// 「侠」字印章图标（回退方案）
    /// 深墨底 + 金色描边 + 朱红印章质感，呼应武侠主题
    static func drawDefault(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        defer { img.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.225          // 贴近 macOS 原生圆角比例
        let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        clip.addClip()

        // 背景：深墨蓝到墨黑的斜向渐变
        let bg = NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.29, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1)
        ])
        bg?.draw(in: rect, angle: -60)

        // 顶部高光，增加立体感
        let glossRect = NSRect(x: 0, y: size * 0.55, width: size, height: size * 0.45)
        let gloss = NSGradient(colors: [
            NSColor(white: 1, alpha: 0.10),
            NSColor(white: 1, alpha: 0.0)
        ])
        gloss?.draw(in: glossRect, angle: -90)

        // 朱红印章底
        let sealSize = size * 0.62
        let sealRect = NSRect(
            x: (size - sealSize) / 2,
            y: (size - sealSize) / 2,
            width: sealSize,
            height: sealSize
        )
        let sealPath = NSBezierPath(
            roundedRect: sealRect,
            xRadius: sealSize * 0.16,
            yRadius: sealSize * 0.16
        )
        NSColor(calibratedRed: 0.80, green: 0.16, blue: 0.16, alpha: 1).setFill()
        sealPath.fill()

        // 印章金边
        NSColor(calibratedRed: 0.91, green: 0.75, blue: 0.42, alpha: 0.95).setStroke()
        sealPath.lineWidth = max(size * 0.018, 1)
        sealPath.stroke()

        // 「侠」字：用 CoreText 取字形实际轮廓来居中
        // NSAttributedString 的 size()/boundingRect() 返回的是排版框，
        // 楷体字形在框内本身有偏移，用排版框居中会明显偏右下
        drawCenteredGlyph("侠",
                          in: NSRect(x: 0, y: 0, width: size, height: size),
                          fontSize: sealSize * 0.68,
                          color: NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.90, alpha: 1))

        return img
    }

    /// 把单个字按其字形轮廓精确居中绘制到指定矩形
    private static func drawCenteredGlyph(_ text: String,
                                          in rect: NSRect,
                                          fontSize: CGFloat,
                                          color: NSColor) {
        let font = NSFont(name: "STKaiti", size: fontSize)
            ?? NSFont(name: "Kaiti SC", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .semibold)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let ctFont = font as CTFont
        var glyph = CGGlyph()
        var char = UniChar(text.utf16.first ?? 0)
        guard CTFontGetGlyphsForCharacters(ctFont, &char, &glyph, 1) else { return }

        // 字形相对基线原点的实际边界
        var glyphRect = CGRect.zero
        withUnsafePointer(to: glyph) { gp in
            glyphRect = CTFontGetBoundingRectsForGlyphs(
                ctFont, .horizontal, gp, nil, 1
            )
        }
        guard !glyphRect.isEmpty else { return }

        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        let position = CGPoint(
            x: rect.midX - glyphRect.midX,
            y: rect.midY - glyphRect.midY
        )
        withUnsafePointer(to: glyph) { gp in
            withUnsafePointer(to: position) { pp in
                CTFontDrawGlyphs(ctFont, gp, pp, 1, ctx)
            }
        }
        ctx.restoreGState()
    }

    /// 生成 .icns 需要的多尺寸 PNG，供构建脚本使用
    static func exportIconSet(to dir: URL) throws {
        let sizes: [(Int, String)] = [
            (16, "icon_16x16"), (32, "icon_16x16@2x"),
            (32, "icon_32x32"), (64, "icon_32x32@2x"),
            (128, "icon_128x128"), (256, "icon_128x128@2x"),
            (256, "icon_256x256"), (512, "icon_256x256@2x"),
            (512, "icon_512x512"), (1024, "icon_512x512@2x")
        ]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (px, name) in sizes {
            let img = render(size: CGFloat(px))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    /// 导出输入法菜单栏图标（矢量 PDF）
    ///
    /// 系统设置的输入法列表与菜单栏用的是同一个 PDF。这里必须是
    /// 纯矢量路径：把 PNG 用 sips 转出来的 PDF 内嵌的是位图，
    /// 系统按原始像素尺寸渲染，会把列表行高撑到极大且显示不出内容。
    ///
    /// 画法参考微信输入法：实心圆底 + 反白的「侠」字。
    /// 菜单栏图标是模板图（只认覆盖区域，颜色由系统按深浅色决定），
    /// 所以「反白」要靠 even-odd 填充把字形从圆里挖空，
    /// 挖空处透出背景色，视觉上就是黑底白字。
    static func exportMenuBarPDF(to url: URL) throws {
        // 16pt 是菜单栏图标的标准尺寸，矢量可无损放大
        let side: CGFloat = 16
        var box = CGRect(x: 0, y: 0, width: side, height: side)

        guard let data = CFDataCreateMutable(nil, 0),
              let consumer = CGDataConsumer(data: data),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "AppIcon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法创建 PDF 上下文"
            ])
        }

        ctx.beginPDFPage(nil)

        let combined = CGMutablePath()

        // 圆底占满画布：微信输入法的图标也是 16x16 满画布，
        // 之前留 2% 边距导致视觉上比邻居小一圈
        combined.addEllipse(in: box)

        // 字形轮廓作为挖空区。用黑体而非楷体：楷体笔画细，
        // 缩到 16pt 反白后笔画会被圆底吃掉，看不出是什么字。
        //
        // 字号不等于墨迹大小：汉字实际轮廓通常只占字号的 7 成左右，
        // 所以这里先按字号取轮廓，再按实测 boundingBox 缩放到目标墨迹尺寸，
        // 否则字看起来会明显偏小。
        let font = NSFont(name: "PingFangSC-Semibold", size: side)
            ?? NSFont(name: "STHeitiSC-Medium", size: side)
            ?? NSFont.systemFont(ofSize: side, weight: .semibold)
        let ctFont = font as CTFont

        // 目标墨迹边长占画布的比例。圆的内接正方形边长是直径的 0.707，
        // 取 0.62 让字尽量大又不触碰圆边（留出反白需要的圆环）
        let inkRatio: CGFloat = 0.62

        var glyph = CGGlyph()
        var char = UniChar(("侠".utf16.first) ?? 0)
        if CTFontGetGlyphsForCharacters(ctFont, &char, &glyph, 1),
           let path = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
            let b = path.boundingBox
            let longest = max(b.width, b.height)
            if longest > 0 {
                let scale = side * inkRatio / longest
                // 先缩放，再按缩放后的轮廓居中
                var scaleT = CGAffineTransform(scaleX: scale, y: scale)
                if let scaled = path.copy(using: &scaleT) {
                    let sb = scaled.boundingBox
                    var moveT = CGAffineTransform(
                        translationX: box.midX - sb.midX,
                        y: box.midY - sb.midY
                    )
                    if let centered = scaled.copy(using: &moveT) {
                        combined.addPath(centered)
                    }
                }
            }
        }

        ctx.addPath(combined)
        ctx.setFillColor(NSColor.black.cgColor)
        // even-odd：圆与字形的重叠部分相互抵消，字被挖成透明
        ctx.fillPath(using: .evenOdd)

        ctx.endPDFPage()
        ctx.closePDF()

        try (data as Data).write(to: url)
    }
}
