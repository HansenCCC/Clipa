import SwiftUI
import Combine

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var labelKey: LocalizedStringKey {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum PasteBehavior: String, CaseIterable, Identifiable {
    case auto, manual
    var id: String { rawValue }
    var labelKey: LocalizedStringKey {
        switch self {
        case .auto: return "Auto-paste (requires Accessibility)"
        case .manual: return "I'll paste manually with ⌘V"
        }
    }
}

enum RetentionPeriod: String, CaseIterable, Identifiable {
    case day, week, month, unlimited
    var id: String { rawValue }
    var labelKey: LocalizedStringKey {
        switch self {
        case .day: return "1 Day"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .unlimited: return "Unlimited"
        }
    }
    /// 保留天数；unlimited 返回 nil（不按时间清理）。
    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .unlimited: return nil
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case zhHK = "zh-HK"
    case ja, ko, fr, es
    case ptPT = "pt-PT"
    case ru, tr, ar
    var id: String { rawValue }
    // 每个语言以其自身的名称显示（自称/endonym），不做翻译。
    var labelKey: LocalizedStringKey {
        switch self {
        case .system: return "Follow System"
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .zhHK: return "繁體中文（香港）"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .es: return "Español"
        case .ptPT: return "Português (Portugal)"
        case .ru: return "Русский"
        case .tr: return "Türkçe"
        case .ar: return "العربية"
        }
    }
    var code: String? { self == .system ? nil : rawValue }
}

/// 全局偏好设置：@Published 驱动 UI，didSet 持久化到 UserDefaults。
final class AppSettings: ObservableObject {
    /// 公益发布版：所有功能默认开放，不展示或执行任何收费流程。
    /// 关闭后即可恢复既有 StoreKit 付费逻辑；Debug 构建仍保留会员态开关用于回归。
    static let publicFreeRelease = true
    static var commercialFeaturesEnabled: Bool {
        #if DEBUG
        return true
        #else
        return !publicFreeRelease
        #endif
    }

    static let freeMaxItems = 20
    static let freeMaxPins = 5
    static let freeMaxCollections = 1
    private let d = UserDefaults.standard

    /// 是否按完整功能用户处理：公益版始终开放全部功能；商业版沿用购买/试用判断。
    var isPro: Bool {
        #if DEBUG
        return debugIsMember
        #else
        return !Self.commercialFeaturesEnabled || isProUnlocked || TrialManager.shared.isActive
        #endif
    }

    @Published var maxHistoryCount: Int { didSet { d.set(maxHistoryCount, forKey: "maxHistoryCount") } }
    @Published var retentionPeriod: RetentionPeriod { didSet { d.set(retentionPeriod.rawValue, forKey: "retentionPeriodRaw") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var pasteBehavior: PasteBehavior { didSet { d.set(pasteBehavior.rawValue, forKey: "pasteBehaviorRaw") } }
    @Published var appearance: AppearanceMode { didSet { d.set(appearance.rawValue, forKey: "appearanceRaw") } }
    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "languageRaw"); applyLanguage() } }
    @Published var showPermissionStatusInMenuBar: Bool { didSet { d.set(showPermissionStatusInMenuBar, forKey: "showPermissionStatusInMenuBar") } }
    @Published var excludedBundleIDs: [String] { didSet { d.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    @Published var isProUnlocked: Bool { didSet { d.set(isProUnlocked, forKey: "isProUnlocked") } }
    @Published var hotKeyKeyCode: Int { didSet { d.set(hotKeyKeyCode, forKey: "hotKeyKeyCode") } }
    @Published var hotKeyModifiers: Int { didSet { d.set(hotKeyModifiers, forKey: "hotKeyModifiers") } }
    @Published var scrollSensitivity: Double { didSet { d.set(scrollSensitivity, forKey: "scrollSensitivity") } }

    #if DEBUG
    /// 调试开关：直接控制「当前是不是会员」。开=Pro，关=免费。默认开（对齐首启试用）。
    @Published var debugIsMember: Bool { didSet { d.set(debugIsMember, forKey: "debugIsMember") } }
    #endif

    init() {
        let d = UserDefaults.standard
        func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) == nil ? def : d.integer(forKey: k) }
        func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        func dbl(_ k: String, _ def: Double) -> Double { d.object(forKey: k) == nil ? def : d.double(forKey: k) }

        maxHistoryCount = int("maxHistoryCount", 200)
        retentionPeriod = RetentionPeriod(rawValue: d.string(forKey: "retentionPeriodRaw") ?? "") ?? .month
        launchAtLogin = bool("launchAtLogin", false)
        pasteBehavior = PasteBehavior(rawValue: d.string(forKey: "pasteBehaviorRaw") ?? "") ?? .manual
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearanceRaw") ?? "") ?? .system
        language = AppLanguage(rawValue: d.string(forKey: "languageRaw") ?? "") ?? .system
        showPermissionStatusInMenuBar = bool("showPermissionStatusInMenuBar", true)
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? []
        isProUnlocked = bool("isProUnlocked", false)
        hotKeyKeyCode = int("hotKeyKeyCode", 9)            // V
        hotKeyModifiers = int("hotKeyModifiers", 0x0300)   // cmd+shift
        scrollSensitivity = dbl("scrollSensitivity", 4.5)
        #if DEBUG
        debugIsMember = bool("debugIsMember", true)
        #endif
    }

    /// 免费版历史条数上限；完整功能用户使用用户配置值。
    var effectiveMaxItems: Int {
        isPro ? maxHistoryCount : min(maxHistoryCount, Self.freeMaxItems)
    }

    var effectiveMaxPins: Int {
        isPro ? Int.max : Self.freeMaxPins
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    /// 应用语言覆盖（写入 AppleLanguages，重启后生效）。
    func applyLanguage() {
        if let code = language.code {
            d.set([code], forKey: "AppleLanguages")
        } else {
            d.removeObject(forKey: "AppleLanguages")
        }
    }
}
