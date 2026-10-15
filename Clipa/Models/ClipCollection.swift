import Foundation
import SwiftData

/// 用户自定义集合（提示词 / 地址 / 话术…）。
/// 其中的条目永久保存，不受「保留天数」与「最多条数」等历史清理影响，只有手动删除才会消失。
@Model
final class ClipCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbol: String     // SF Symbol 名（分段 pill 图标）
    var sortIndex: Int
    var createdAt: Date

    init(name: String, symbol: String = "folder", sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }
}
