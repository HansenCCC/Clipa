import SwiftUI

/// Pro 解锁页：年订阅 + 永久买断；含试用提示与功能对比。
struct ProUnlockView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    var onClose: () -> Void = {}

    private var purchase: PurchaseService { appState.purchase }

    private let features: [LocalizedStringKey] = [
        "Unlimited clipboard history",
        "Pin unlimited items",
        "Image & file previews",
        "Quick Look for any file",
        "Priority updates",
    ]

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
            Text("Clipa Pro").font(Theme.Font.title)
            Text("Unlock everything.").foregroundStyle(Theme.Color.secondary)

            if TrialManager.shared.isActive {
                Label("Free trial · \(TrialManager.shared.daysRemaining) days left",
                      systemImage: "gift.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(ClipaColor.accent)
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(features.indices, id: \.self) { i in
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Color.success)
                        Text(features[i]).font(Theme.Font.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
            .background(ClipaColor.cardBG, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))

            // 两档定价
            if loading {
                ProgressView().controlSize(.small).padding(.vertical, Theme.Space.sm)
            } else if purchase.lifetime == nil && purchase.yearly == nil {
                Text("In-app purchases are unavailable right now. Please try again later.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: Theme.Space.xs) {
                    Button {
                        Task { await purchase.purchase(purchase.lifetime, settings: settings); appState.refresh() }
                    } label: {
                        tierLabel(title: "Lifetime", price: purchase.lifetimePrice, sub: "One-time purchase", best: true)
                    }.buttonStyle(.plain).disabled(purchase.lifetime == nil)

                    Button {
                        Task { await purchase.purchase(purchase.yearly, settings: settings); appState.refresh() }
                    } label: {
                        tierLabel(title: "Yearly", price: purchase.yearlyPrice, sub: "Billed annually", best: false)
                    }.buttonStyle(.plain).disabled(purchase.yearly == nil)
                }
                .disabled(purchase.purchaseInProgress)
            }

            Button("Restore Purchase") {
                Task { await purchase.restore(settings: settings); appState.refresh() }
            }
            .buttonStyle(.plain).font(Theme.Font.caption)

            HStack(spacing: Theme.Space.md) {
                Link("Privacy Policy", destination: Links.privacy)
                Link("Terms of Use", destination: Links.terms)
            }.font(Theme.Font.footnote).foregroundStyle(Theme.Color.secondary)

            Button("Close") { onClose() }.buttonStyle(.plain).font(Theme.Font.caption)
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
        .task { loading = true; await purchase.loadProducts(); loading = false }
        .onChange(of: settings.isProUnlocked) { _, unlocked in if unlocked { onClose() } }
    }

    @State private var loading = true

    private func tierLabel(title: LocalizedStringKey, price: String, sub: LocalizedStringKey, best: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Text(price).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, Theme.Space.md).padding(.vertical, Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .fill(best ? ClipaColor.accent : Color(hex: 0x8E8E93))
        )
        .overlay(alignment: .topTrailing) {
            if best {
                Text("BEST VALUE")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(ClipaColor.accent)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.white, in: Capsule())
                    .offset(x: -8, y: 8)
            }
        }
    }
}
