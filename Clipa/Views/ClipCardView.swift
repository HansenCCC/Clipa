import SwiftUI

/// 单张剪贴卡片（1:1 还原 Figma）。
struct ClipCardView: View {
    let item: ClipItem
    var index: Int = 0
    var isFocused: Bool = false
    @EnvironmentObject var appState: AppState
    @State private var hovering = false
    @State private var showColorInfo = false

    private var typeColor: Color { ClipaColor.type(item.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            header
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Space.sm)
        .frame(width: Theme.Card.width, height: Theme.Card.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Card.radius).fill(ClipaColor.cardBG))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Card.radius)
                .stroke(isFocused ? ClipaColor.accent : ClipaColor.cardBorder,
                        lineWidth: isFocused ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Card.radius))
        .shadow(color: isFocused ? ClipaColor.accent.opacity(0.28) : .black.opacity(0.06),
                radius: isFocused ? 9 : 4, x: 0, y: 2)
        .scaleEffect(hovering && !isFocused ? 1.012 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { appState.use(item) }
        .contextMenu { contextMenu }
        .help(item.previewText)
    }

    // MARK: - 头部：类型药丸 + PIN

    private var header: some View {
        HStack(spacing: 6) {
            Text(typeBadge)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(typeColor)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            if let meta = headerMeta {
                Text(meta)
                    .font(.system(size: 10))
                    .foregroundStyle(ClipaColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            // 颜色卡片：悬停时右上角出现「更多格式」按钮，点开可复制 RGB/HSL 等
            if item.kind == .color {
                Button { showColorInfo.toggle() } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ClipaColor.textSecondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering || showColorInfo ? 1 : 0)
                .popover(isPresented: $showColorInfo, arrowEdge: .bottom) {
                    ColorFormatsPopover(color: swatchNSColor) { appState.copyText($0) }
                }
            }
            if item.isPinned {
                Text("PIN")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ClipaColor.accent.opacity(0.85))
            } else if hovering {
                Image(systemName: "pin")
                    .font(.system(size: 9))
                    .foregroundStyle(ClipaColor.textTertiary)
                    .onTapGesture { appState.togglePin(item) }
            }
        }
    }

    /// 该颜色卡片解析出的 NSColor（用于「更多格式」弹窗）。
    private var swatchNSColor: NSColor {
        ColorParser.parse(item.plainText)?.color ?? .gray
    }

    // MARK: - 内容

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .color:
            colorSwatch
        case .image:
            if let path = item.imageFilePath {
                AsyncThumb(name: path, transparent: item.imageTransparent == true) { thumbPlaceholder }
            } else {
                Image(systemName: "photo").font(.system(size: 24)).foregroundStyle(ClipaColor.textTertiary)
            }
        case .file:
            // 图片/可预览文件：显示缩略图；其余：图标 + 文件名 + 大小。
            // 若是压缩包，底部追加「解压…」按钮，直接把该文件交给压缩/解压面板。
            VStack(alignment: .leading, spacing: 6) {
                if let thumb = item.thumbnailPath {
                    AsyncThumb(name: thumb, transparent: item.imageTransparent == true) { fileFallback }
                } else {
                    fileFallback
                }
                if isExtractable { extractButton }
            }
        case .link:
            VStack(alignment: .leading, spacing: 3) {
                Text(linkTitle).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClipaColor.textPrimary).lineLimit(3)
                Text(linkDomain).font(.system(size: 10)).foregroundStyle(typeColor).lineLimit(1)
            }
        case .code:
            fillingText(item.previewText, size: 11, mono: true, maxLines: 11)
        case .text, .rtf:
            if let title = item.title, !title.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ClipaColor.textPrimary).lineLimit(1)
                    fillingText(item.previewText, size: 12, mono: false, maxLines: 9)
                }
            } else {
                fillingText(item.previewText, size: 12, mono: false, maxLines: 10)
            }
        }
    }

    /// 文本/代码内容：占满卡片可用高度、铺满后尾部省略。
    /// 卡片尺寸固定，行数按内容区高度取常量即可——避免每张卡片一个 GeometryReader 拖慢大列表布局。
    private func fillingText(_ text: String, size: CGFloat, mono: Bool, maxLines: Int) -> some View {
        Text(text)
            .font(.system(size: size, design: mono ? .monospaced : .default))
            .foregroundStyle(ClipaColor.textPrimary)
            .lineLimit(maxLines)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 缩略图加载中的中性占位（图片卡片）。
    private var thumbPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6).fill(ClipaColor.imageBG)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 当前 clip 是否为可解压的压缩包（文件类型且至少一个 URL 能解压）。
    private var isExtractable: Bool {
        item.kind == .file && item.fileURLs.contains { ArchiveService.canExtract($0) }
    }

    /// 压缩包卡片底部的「解压…」按钮，直接把文件交给压缩/解压面板。
    private var extractButton: some View {
        Button { appState.handleOpenFiles(item.fileURLs) } label: {
            Label("Extract…", systemImage: "archivebox")
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(ClipaColor.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(ClipaColor.accent)
        }
        .buttonStyle(.plain)
        .help("Extract this archive")
    }

    /// 无内容缩略图时的文件/文件夹展示：居中的大号系统真实图标（Finder 同款）+ 名称。
    private var fileFallback: some View {
        VStack(spacing: 12) {
            if let url = item.fileURLs.first {
                FileIconThumb(url: url, size: 104)
            } else {
                Image(systemName: fileIcon).font(.system(size: 68)).foregroundStyle(typeColor)
            }
            Text(item.previewText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ClipaColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    /// 顶部药丸旁的元信息（按类型）。
    private var headerMeta: String? {
        switch item.kind {
        case .text, .rtf: return String(localized: "\(item.plainText.count) chars")
        case .code: return String(localized: "\(lineCount) lines")
        case .link: return linkDomain.isEmpty ? nil : linkDomain
        case .image:
            if let s = imageByteString { return "PNG · \(s)" }
            return "PNG"
        case .file:
            let n = item.fileURLs.count
            let total = totalFileBytes
            if n > 1 { return String(localized: "\(n) files") + (total > 0 ? " · \(byteString(total))" : "") }
            return total > 0 ? byteString(total) : nil
        case .color: return nil
        }
    }

    private var lineCount: Int {
        item.plainText.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private func byteString(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private var totalFileBytes: Int64 {
        item.fileURLs.reduce(0) { acc, url in
            acc + (((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0)
        }
    }

    private var imageByteString: String? {
        if let path = item.imageFilePath, let b = ImageCache.shared.byteSize(path) { return byteString(b) }
        return nil
    }

    /// 底部左侧元信息：图片→尺寸；其余→相对时间。
    private var footerMeta: String {
        item.imageDimensions ?? RelativeTime.string(item.createdAt)
    }

    private var colorSwatch: some View {
        let nsColor = ColorParser.parse(item.plainText)?.color ?? .gray
        let color = Color(nsColor: nsColor)
        let isLight = nsColor.usingColorSpace(.sRGB).map { 0.299*$0.redComponent + 0.587*$0.greenComponent + 0.114*$0.blueComponent > 0.6 } ?? false
        return RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClipaColor.cardBorder, lineWidth: 1))
            .overlay(
                Text(item.colorHex ?? item.plainText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isLight ? .black : .white)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileIcon: String {
        switch fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z", "gz", "tar": return "doc.zipper"
        case "xls", "xlsx", "csv", "numbers": return "tablecells.fill"
        case "doc", "docx", "pages": return "doc.text.fill"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "wav", "aac", "flac": return "music.note"
        default: return "doc.fill"
        }
    }

    private var fileExtension: String {
        (item.fileURLs.first?.pathExtension ?? "").lowercased()
    }

    // MARK: - 底部：相对时间 + 来源 App 角标

    private var footer: some View {
        HStack {
            Text(footerMeta)
                .font(.system(size: 10))
                .foregroundStyle(ClipaColor.textTertiary)
            Spacer()
            if let icon = AppIconProvider.icon(for: item.sourceAppBundleID) {
                Image(nsImage: icon).resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - 文案/解析

    private var typeBadge: String {
        switch item.kind {
        case .text: return "TXT"
        case .rtf: return "RTF"
        case .link: return "URL"
        case .image: return "IMG"
        case .code: return "CODE"
        case .color: return "COLOR"
        case .file:
            let ext = fileExtension
            return ext.isEmpty ? "FILE" : ext.uppercased()
        }
    }

    private var linkTitle: String {
        if let url = URL(string: item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)),
           let host = url.host {
            let path = url.path
            return path.count > 1 ? host + path : host
        }
        return item.previewText
    }
    private var linkDomain: String {
        URL(string: item.plainText.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? ""
    }

    // MARK: - 右键菜单

    @ViewBuilder private var contextMenu: some View {
        Button("Paste") { appState.use(item) }
        if item.kind == .rtf {
            Button("Paste as Plain Text") { appState.use(item, asPlainText: true) }
        }
        Button(item.isPinned ? "Unpin" : "Pin") { appState.togglePin(item) }
        Button("Copy") { appState.copy(item) }
        // 集合：历史条目可保存到集合；集合条目可编辑 / 移出
        if item.collectionID == nil {
            Menu("Save to") {
                ForEach(appState.collections) { c in
                    Button(c.name) { appState.addToCollection(item, c.id) }
                }
                if !appState.collections.isEmpty { Divider() }
                Button("New Collection…") { appState.requestNewCollection(saving: item) }
            }
        } else {
            if item.kind == .text || item.kind == .rtf {
                Button("Edit") {
                    if let cid = item.collectionID { appState.openSnippetEditor(editing: item, collectionID: cid) }
                }
            }
            Button("Remove from Collection") { appState.removeFromCollection(item) }
        }
        if item.kind == .file {
            if isExtractable {
                Button("Extract…") { appState.handleOpenFiles(item.fileURLs) }
            }
            Button("Show in Finder") {
                if let url = item.fileURLs.first {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { appState.delete(item) }
    }
}

/// 异步缩略图：命中内存缓存立即显示（无闪烁），否则后台读盘、加载完再显示，避免首帧同步读盘卡顿。
private struct AsyncThumb<Placeholder: View>: View {
    let name: String
    let transparent: Bool
    let placeholder: () -> Placeholder
    @State private var image: NSImage?

    init(name: String, transparent: Bool, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.name = name
        self.transparent = transparent
        self.placeholder = placeholder
        _image = State(initialValue: ImageCache.shared.cachedImage(for: name))
    }

    var body: some View {
        Group {
            if let image {
                ZStack {
                    if transparent { Checkerboard() }   // 仅透明图显示棋盘格；不透明用卡片白底
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                }
                .aspectRatio(1, contentMode: .fit)        // 1:1 预览容器
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(transparent ? RoundedRectangle(cornerRadius: 6).stroke(ClipaColor.cardBorder, lineWidth: 1) : nil)
            } else {
                placeholder()
            }
        }
        .task(id: name) {
            guard image == nil else { return }
            image = await ImageCache.shared.loadImage(for: name)
        }
    }
}

/// 颜色卡片「更多格式」弹窗：列出 HEX/RGB/RGBA/HSL，点任意一行复制该格式。
private struct ColorFormatsPopover: View {
    let color: NSColor
    let onCopy: (String) -> Void
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: color))
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.12)))
                Text("Tap a value to copy").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 7)

            ForEach(formats, id: \.0) { fmt in
                Button {
                    onCopy(fmt.1); copied = fmt.0
                } label: {
                    HStack(spacing: 8) {
                        Text(fmt.0).font(.system(size: 10, weight: .bold))
                            .frame(width: 42, alignment: .leading).foregroundStyle(.secondary)
                        Text(fmt.1).font(.system(size: 12, design: .monospaced)).foregroundStyle(.primary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 6)
                        Image(systemName: copied == fmt.0 ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(copied == fmt.0 ? Color.green : Color.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 232)
        .padding(.bottom, 6)
    }

    /// HEX / RGB / RGBA / HSL 四种格式。
    private var formats: [(String, String)] {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent, a = c.alphaComponent
        let R = Int((r * 255).rounded()), G = Int((g * 255).rounded()), B = Int((b * 255).rounded())
        let hex = a < 1
            ? String(format: "#%02X%02X%02X%02X", R, G, B, Int((a * 255).rounded()))
            : String(format: "#%02X%02X%02X", R, G, B)
        let (h, s, l) = Self.hsl(r, g, b)
        return [
            ("HEX",  hex),
            ("RGB",  "rgb(\(R), \(G), \(B))"),
            ("RGBA", String(format: "rgba(%d, %d, %d, %.2f)", R, G, B, a)),
            ("HSL",  "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"),
        ]
    }

    /// sRGB → HSL（h:0-360, s/l:0-1）。
    private static func hsl(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        guard d != 0 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: CGFloat
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        return (h * 60, s, l)
    }
}

/// PS 风格透明棋盘格背景（用于区分 PNG 透明区域）。
struct Checkerboard: View {
    var cell: CGFloat = 7
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            let gray = Color(white: 0.82)
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color(gray))
                }
            }
        }
    }
}

/// 系统文件/文件夹图标（NSWorkspace，Finder 同款），异步加载 + 缓存，避免大列表首帧同步读盘。
/// 用 NSCache（线程安全）——普通字典会被后台续体与主线程并发读写而崩溃（NSTaggedPointerString 野指针）。
enum FileIconProvider {
    private static let cache = NSCache<NSString, NSImage>()

    static func cachedIcon(for path: String) -> NSImage? { cache.object(forKey: path as NSString) }

    static func loadIcon(for path: String) async -> NSImage {
        let key = path as NSString
        if let c = cache.object(forKey: key) { return c }
        let icon = await Task.detached(priority: .userInitiated) { () -> NSImage in
            let img = NSWorkspace.shared.icon(forFile: path)
            img.size = NSSize(width: 256, height: 256)   // 取高清表征，放大不糊
            return img
        }.value
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// 展示单个文件/文件夹的系统图标：命中缓存立即显示，否则后台取、加载后再显示。
private struct FileIconThumb: View {
    let url: URL
    var size: CGFloat = 54
    @State private var image: NSImage?

    init(url: URL, size: CGFloat = 54) {
        self.url = url
        self.size = size
        _image = State(initialValue: FileIconProvider.cachedIcon(for: url.path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(ClipaColor.imageBG)
            }
        }
        .frame(width: size, height: size)
        .task(id: url.path) {
            if image == nil { image = await FileIconProvider.loadIcon(for: url.path) }
        }
    }
}

/// 缓存来源 App 图标。
enum AppIconProvider {
    private static var cache: [String: NSImage] = [:]
    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
