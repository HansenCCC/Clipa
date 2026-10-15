import Foundation

/// 法务/支持链接。Privacy 使用自有页面，Terms 使用 Apple 标准 EULA。
enum Links {
    static let privacy = URL(string: "https://chenghengsheng.top/app/6785361561/privacy.html")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// 意见反馈邮箱。
    static let feedbackEmail = "2534550460@qq.com"

    /// Mac App Store「撰写评论」页，用于手动好评入口。
    static let appStoreReview = URL(string: "macappstore://apps.apple.com/app/id6785361561?action=write-review")!
}
