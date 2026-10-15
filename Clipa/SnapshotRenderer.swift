import SwiftUI
import AppKit

#if DEBUG
/// 设 CLIPA_SNAPSHOT=输出目录 时，渲染卡片条为 PNG（浅/深）后退出，用于 UI 还原自检。
enum SnapshotRenderer {
    @MainActor
    static func runIfRequested() -> Bool {
        guard let outDir = ProcessInfo.processInfo.environment["CLIPA_SNAPSHOT"] else { return false }

        let appState = AppState()
        appState.clips = mockItems()
        appState.segment = .all
        appState.selectedIndex = 1

        render(appState: appState, dark: false, to: "\(outDir)/bar_light.png")
        render(appState: appState, dark: true, to: "\(outDir)/bar_dark.png")

        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }

    @MainActor
    private static func render(appState: AppState, dark: Bool, to path: String) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // ImageRenderer 无法绘制 ScrollView/TextField，这里直接铺卡片条做视觉自检
        let items = appState.clips
        let view = HStack(spacing: Theme.Card.spacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                ClipCardView(item: item, index: idx, isFocused: idx == 1)
                    .environmentObject(appState)
            }
        }
        .padding(Theme.Space.lg)
        .frame(height: Theme.Card.height + Theme.Space.lg * 2, alignment: .center)
        .background(ClipaColor.barBG)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.locale, Locale(identifier: "en"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    @MainActor
    private static func mockItems() -> [ClipItem] {
        func mk(_ kind: ClipKind, _ preview: String, _ plain: String, _ bundle: String, _ app: String, pinned: Bool = false, ageMin: Int = 3) -> ClipItem {
            let it = ClipItem(kind: kind, previewText: preview, plainText: plain,
                              contentHash: UUID().uuidString,
                              sourceAppBundleID: bundle, sourceAppName: app)
            it.isPinned = pinned
            it.createdAt = Calendar.current.date(byAdding: .minute, value: -ageMin, to: Date()) ?? Date()
            return it
        }
        // 颜色卡
        let colorItem = ClipItem(kind: .color, previewText: "#4F46E5", plainText: "#4F46E5",
                                 contentHash: UUID().uuidString, colorHex: "#4F46E5",
                                 sourceAppBundleID: "com.apple.dt.Xcode", sourceAppName: "Xcode")
        colorItem.createdAt = Date()
        // 图片文件卡（透明 PNG，验证棋盘格 + 尺寸）
        let iconURL = URL(fileURLWithPath: "docs/assets/icon.png")
        let thumb = FileRecognition.makeThumbnail(for: iconURL)
        if let name = thumb?.name { _ = ImageCache.shared.image(for: name) }
        let dims = FileRecognition.dimensions(url: iconURL)
        let imgFile = ClipItem(kind: .file, previewText: "icon.png", plainText: iconURL.path,
                               contentHash: UUID().uuidString, thumbnailPath: thumb?.name, imageDimensions: dims,
                               imageTransparent: thumb?.transparent,
                               fileURLStrings: [iconURL.absoluteString],
                               sourceAppBundleID: "com.apple.finder", sourceAppName: "Finder")
        imgFile.createdAt = Calendar.current.date(byAdding: .minute, value: -1, to: Date())!

        return [
            colorItem, imgFile,
            mk(.text, "Release checklist\n\nShip the fix\nUpdate the changelog\nTake a walk.",
               "Release checklist", "com.apple.Notes", "Notes", pinned: true, ageMin: 3),
            mk(.code, "git commit -m \"fix: keep clipboard responsive\"", "git commit",
               "com.googlecode.iterm2", "iTerm", ageMin: 7),
            mk(.link, "https://developer.apple.com", "https://developer.apple.com",
               "com.apple.Safari", "Safari", ageMin: 9),
        ]
    }
}
#endif
