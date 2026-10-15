import SwiftUI

/// 首次启动欢迎页：告知已获赠 Pro 免费试用。
struct WelcomeView: View {
    var daysLeft: Int
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Welcome to Clipa").font(.system(size: 22, weight: .semibold))

            if daysLeft > 0 {
                Label("You've got \(daysLeft) days of Pro — free 🎁", systemImage: "gift.fill")
                    .font(Theme.Font.headline)
                    .foregroundStyle(ClipaColor.accent)
            }

            Text("Everything you copy is saved here. Press ⌘⇧V anywhere to open your clipboard history.")
                .multilineTextAlignment(.center)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Get Started") { onClose() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Divider().frame(maxWidth: 260)

            Label("Compress & extract archives — right inside Clipa", systemImage: "archivebox")
                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Space.xl)
        .frame(width: 440, height: 400)
    }
}
