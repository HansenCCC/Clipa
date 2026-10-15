import StoreKit

/// StoreKit 2 内购：年订阅 + 永久买断。公益发布版保留代码但不执行收费流程。
@MainActor
final class PurchaseService: ObservableObject {
    static let yearlyID = "com.hansen.clipa.pro.yearly"
    static let lifetimeID = "com.hansen.clipa.pro.lifetime"

    @Published var yearly: Product?
    @Published var lifetime: Product?
    @Published var purchaseInProgress = false
    @Published var lastError: String?

    var yearlyPrice: String { yearly?.displayPrice ?? "$1.99" }
    var lifetimePrice: String { lifetime?.displayPrice ?? "$5.99" }

    func loadProducts() async {
        guard AppSettings.commercialFeaturesEnabled else { return }
        do {
            let products = try await Product.products(for: [Self.yearlyID, Self.lifetimeID])
            yearly = products.first { $0.id == Self.yearlyID }
            lifetime = products.first { $0.id == Self.lifetimeID }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 校验授权：拥有永久 或 年订阅有效 → 解锁。
    func refreshEntitlements(settings: AppSettings) async {
        guard AppSettings.commercialFeaturesEnabled else { return }
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == Self.lifetimeID { unlocked = true }
            if t.productID == Self.yearlyID, (t.expirationDate ?? .distantPast) > Date() { unlocked = true }
        }
        settings.isProUnlocked = unlocked
    }

    func purchase(_ product: Product?, settings: AppSettings) async {
        guard AppSettings.commercialFeaturesEnabled else { return }
        guard let product else { return }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result, case .verified(let t) = verification {
                settings.isProUnlocked = true
                await t.finish()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore(settings: AppSettings) async {
        guard AppSettings.commercialFeaturesEnabled else { return }
        do {
            try await AppStore.sync()
            await refreshEntitlements(settings: settings)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
