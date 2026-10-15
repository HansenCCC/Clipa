import Foundation
import Security

/// 极简钥匙串读写。钥匙串条目在 App 卸载后仍保留，用于防止重装刷免费试用。
enum Keychain {
    private static let service = "com.hansen.clipa"

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// 首启赠送 2 个月 Pro 试用；起始时间存钥匙串，重装不会重置。
final class TrialManager {
    static let shared = TrialManager()
    static let trialDays = 60
    private let key = "trialStart"

    let startDate: Date

    private init() {
        if let s = Keychain.get(key), let t = TimeInterval(s) {
            startDate = Date(timeIntervalSince1970: t)
        } else {
            let now = Date()
            startDate = now
            Keychain.set(key, String(now.timeIntervalSince1970))
        }
    }

    var endDate: Date { startDate.addingTimeInterval(Double(Self.trialDays) * 86_400) }
    var isActive: Bool { Date() < endDate }
    var daysRemaining: Int { max(0, Int(endDate.timeIntervalSinceNow / 86_400)) }
}
