import SwiftUI
import AppKit

#if DEBUG
/// 设 CLIPA_SCREENSHOTS=输出目录 时，渲染 App Store 营销截图（2560×1600）后退出。
enum ScreenshotRenderer {
    @MainActor
    static func runIfRequested() -> Bool {
        guard let outDir = ProcessInfo.processInfo.environment["CLIPA_SCREENSHOTS"] else { return false }

        let appState = AppState()
        let items = mockItems()

        let shots: [(LocalizedStringKey, [Color])] = [
            ("Everything you copy, one keystroke away", [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)]),
            ("Smart: colors, images, code & files",     [Color(hex: 0x2563EB), Color(hex: 0x06B6D4)]),
            ("Pin favorites, search instantly",          [Color(hex: 0x059669), Color(hex: 0x10B981)]),
            ("Local-first. Private. Never uploaded.",    [Color(hex: 0x111827), Color(hex: 0x374151)]),
        ]
        for (i, shot) in shots.enumerated() {
            render(caption: shot.0, gradient: shot.1, items: items, appState: appState,
                   to: "\(outDir)/shot\(i + 1).png")
        }
        renderPaywall(to: "\(outDir)/paywall.png")
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }

    /// 内购审核用截图：静态 Pro 付费页（价格用占位）。
    @MainActor
    private static func renderPaywall(to path: String) {
        let features: [LocalizedStringKey] = [
            "Unlimited clipboard history", "Pin unlimited items",
            "Image & file previews", "Quick Look for any file", "Priority updates",
        ]
        func tier(_ title: LocalizedStringKey, _ price: String, _ sub: LocalizedStringKey, best: Bool) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text(price).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(best ? ClipaColor.accent : Color(hex: 0x8E8E93)))
        }
        let card = VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
            Text("Clipa Pro").font(.system(size: 22, weight: .semibold))
            Text("Unlock everything.").foregroundStyle(ClipaColor.textSecondary)
            Label("Free trial · \(60) days left", systemImage: "gift.fill").foregroundStyle(ClipaColor.accent)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Color.success)
                        Text(features[i]).font(.system(size: 13))
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(ClipaColor.cardBG, in: RoundedRectangle(cornerRadius: 12))
            tier("Lifetime", "$5.99", "One-time purchase", best: true)
            tier("Yearly", "$1.99", "Billed annually", best: false)
            Text("Restore Purchase").font(.system(size: 12)).foregroundStyle(ClipaColor.textSecondary)
        }
        .padding(28).frame(width: 420)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 10)

        // 居中放进 1280×800（@2x = 2560×1600）横版画布，满足 macOS 截图尺寸
        let view = ZStack {
            LinearGradient(colors: [Color(hex: 0xE9E5FC), Color(hex: 0xDDE7FF)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            card
        }
        .frame(width: 1280, height: 800)
        .environment(\.colorScheme, .light)

        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    @MainActor
    private static func render(caption: LocalizedStringKey, gradient: [Color],
                              items: [ClipItem], appState: AppState, to path: String) {
        let view = ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 48) {
                Text(caption)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                barMockup(items: items, appState: appState)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
                    .padding(.horizontal, 70)
            }
            .padding(.vertical, 80)
        }
        .frame(width: 1280, height: 800)
        .environment(\.colorScheme, .light)

        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// 静态卡片条（不含 TextField/ScrollView，便于 ImageRenderer 渲染）。
    @MainActor
    private static func barMockup(items: [ClipItem], appState: AppState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 16, height: 3)
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 13, height: 3)
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 10, height: 3)
                    }.foregroundStyle(ClipaColor.accent.opacity(0.7))
                    Text("Clipa").font(.system(size: 15, weight: .bold)).foregroundStyle(ClipaColor.accent)
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(ClipaColor.textSecondary)
                    Text("Search clipboard…").foregroundStyle(ClipaColor.textSecondary)
                    Spacer()
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(ClipaColor.searchBG, in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 300)
                HStack(spacing: 2) {
                    Text("All").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(ClipaColor.segSelected, in: RoundedRectangle(cornerRadius: 6))
                    Text("Pinned").font(.system(size: 12)).foregroundStyle(ClipaColor.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                }
                .padding(2).background(ClipaColor.segTrack, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding(.horizontal, 20).frame(height: 48)
            Divider()
            HStack(spacing: Theme.Card.spacing) {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { idx, item in
                    ClipCardView(item: item, index: idx, isFocused: idx == 1).environmentObject(appState)
                }
            }
            .padding(20)
        }
        .background(ClipaColor.barBG)
        .frame(width: 1140)
    }

    @MainActor
    private static func mockItems() -> [ClipItem] {
        func img(_ file: String) -> (String?, Bool) {
            let r = FileRecognition.makeThumbnail(for: URL(fileURLWithPath: file)); return (r?.name, r?.transparent ?? false)
        }
        let color = ClipItem(kind: .color, previewText: "#4F46E5", plainText: "#4F46E5",
                             contentHash: UUID().uuidString, colorHex: "#4F46E5",
                             sourceAppBundleID: "com.apple.dt.Xcode", sourceAppName: "Xcode")
        let (op, _) = img("doc/icon.png")
        let opaque = ClipItem(kind: .file, previewText: "banner.png", plainText: "banner.png",
                              contentHash: UUID().uuidString, thumbnailPath: op, imageDimensions: "1024 × 1024",
                              imageTransparent: false, fileURLStrings: ["file:///banner.png"],
                              sourceAppBundleID: "com.apple.finder", sourceAppName: "Finder")
        let text = ClipItem(kind: .text, previewText: "Q3 Roadmap • Keyboard nav overhaul • Pro tier launch • Accessibility audit",
                            plainText: "Q3 Roadmap", contentHash: UUID().uuidString,
                            sourceAppBundleID: "com.apple.Notes", sourceAppName: "Notes")
        let code = ClipItem(kind: .code, previewText: "func greet() {\n  print(\"Hello, Clipa!\")\n}",
                            plainText: "func greet", contentHash: UUID().uuidString,
                            sourceAppBundleID: "com.apple.dt.Xcode", sourceAppName: "Xcode")
        let link = ClipItem(kind: .link, previewText: "developer.apple.com", plainText: "https://developer.apple.com",
                            contentHash: UUID().uuidString, sourceAppBundleID: "com.apple.Safari", sourceAppName: "Safari")
        return [color, opaque, text, code, link]
    }
}
#endif
