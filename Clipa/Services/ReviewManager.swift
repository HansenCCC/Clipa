import AppKit
import StoreKit

/// 好评/反馈入口。
///
/// macOS 确实有「应用内评分」：`SKStoreReviewController.requestReview()` 会弹出系统原生星级评分浮层，
/// 不离开 app；系统会自动限频（每年最多约 3 次、且只在合适时机展示），不会打扰用户。
/// 这里采用「累计启动 3 次后、温和地请求一次」的策略，之后不再自动弹出，避免影响体验。
/// 手动入口（设置 → About）始终可用：直接跳转 App Store 撰写评论页，以及发送反馈邮件。
@MainActor
final class ReviewManager {
    static let shared = ReviewManager()

    private let d = UserDefaults.standard
    private let launchCountKey = "reviewLaunchCount"
    private let didAutoPromptKey = "reviewDidAutoPrompt"
    private let promptThreshold = 3

    private init() {}

    /// 记录一次启动；达到阈值且从未自动请求过时，温和地请求一次系统评分。
    func registerLaunchAndMaybePrompt() {
        let count = d.integer(forKey: launchCountKey) + 1
        d.set(count, forKey: launchCountKey)

        guard count >= promptThreshold, !d.bool(forKey: didAutoPromptKey) else { return }
        d.set(true, forKey: didAutoPromptKey)

        // 稍作延迟，避开启动瞬间，等界面就绪后再请求。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Self.requestInAppReview()
        }
    }

    /// 系统原生应用内评分浮层（自动限频，不保证一定展示）。
    static func requestInAppReview() {
        SKStoreReviewController.requestReview()
    }

    /// 手动好评：跳转 Mac App Store 的撰写评论页。
    static func openWriteReview() {
        NSWorkspace.shared.open(Links.appStoreReview)
    }

    /// 意见反馈。不依赖系统邮件客户端（很多 Mac 没配，mailto 会无反应或落到浏览器）：
    /// 直接弹窗把反馈邮箱展示给用户，并提供「复制邮箱地址」按钮，由用户自行发送。
    static func sendFeedback() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Send Feedback")
        alert.informativeText = String(localized: "Please email your feedback to us at:")
            + "\n\n" + Links.feedbackEmail
        alert.addButton(withTitle: String(localized: "Copy Email Address"))
        alert.addButton(withTitle: String(localized: "Close"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Links.feedbackEmail, forType: .string)
        }
    }
}
