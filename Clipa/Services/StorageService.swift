import Foundation
import SwiftData
import AppKit

/// SwiftData 之上的 CRUD / 查询 / 去重 / 清理封装。
@MainActor
final class StorageService {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() {
        let schema = Schema([ClipItem.self, ClipCollection.self])
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let isPreview = environment["CLIPA_SNAPSHOT"] != nil || environment["CLIPA_SCREENSHOTS"] != nil
        #else
        let isPreview = false
        #endif
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isPreview)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 首次失败：多为数据库损坏或模型迁移失败。备份旧库→重建一次，保证 App 始终能启动。
            // 常见的加法式模型变更由 SwiftData 自动轻量迁移，走不到这里；只有真的打不开才降级。
            Self.backupCorruptedStore(at: config.url, reason: error)
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                // 重建仍失败（环境级问题，重建无益），此时才放弃。
                fatalError("无法创建 SwiftData 容器（已尝试备份并重建）: \(error)")
            }
        }
    }

    /// 把打不开的 store（含 -wal / -shm 边车文件）改名到 CorruptedBackup/<时间戳>/，
    /// 让下一次 ModelContainer 能在干净目录上重建。数据不删除，仅备份，便于日后恢复。
    private static func backupCorruptedStore(at storeURL: URL, reason: Error) {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let backupDir = storeURL.deletingLastPathComponent()
            .appendingPathComponent("CorruptedBackup/\(stamp)", isDirectory: true)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = backupDir.appendingPathComponent(src.lastPathComponent)
            // 优先移动备份；移动失败则至少删除，确保重建路径可用。
            if (try? fm.moveItem(at: src, to: dst)) == nil { try? fm.removeItem(at: src) }
        }
        NSLog("Clipa: SwiftData 打开失败，已备份旧库到 \(backupDir.path)，原因：\(reason)")
    }

    // MARK: - 查询

    /// 临时历史（未归属任何集合）。集合条目不在此列表，避免和「库」重复。
    func fetchHistory(matching query: String = "") -> [ClipItem] {
        var descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        if query.isEmpty {
            descriptor.predicate = #Predicate { $0.collectionID == nil }
        } else {
            descriptor.predicate = #Predicate { item in
                item.collectionID == nil &&
                (item.previewText.localizedStandardContains(query)
                    || item.plainText.localizedStandardContains(query)
                    || (item.sourceAppName?.localizedStandardContains(query) ?? false))
            }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchPinned() -> [ClipItem] {
        let descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 某个集合内的条目。
    func fetchItems(inCollection id: UUID, matching query: String = "") -> [ClipItem] {
        var descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        if query.isEmpty {
            descriptor.predicate = #Predicate { $0.collectionID == id }
        } else {
            descriptor.predicate = #Predicate { item in
                item.collectionID == id &&
                (item.previewText.localizedStandardContains(query)
                    || item.plainText.localizedStandardContains(query)
                    || (item.title?.localizedStandardContains(query) ?? false))
            }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchCollections() -> [ClipCollection] {
        let d = FetchDescriptor<ClipCollection>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(d)) ?? []
    }

    var totalCount: Int {
        (try? context.fetchCount(FetchDescriptor<ClipItem>())) ?? 0
    }

    var pinnedCount: Int {
        (try? context.fetchCount(FetchDescriptor<ClipItem>(predicate: #Predicate { $0.isPinned }))) ?? 0
    }

    // MARK: - 写入（去重）

    /// 插入新条目；若内容指纹已存在则只更新 lastUsedAt 并提前。返回 (条目, 是否新建)。
    @discardableResult
    func insertOrTouch(_ make: () -> ClipItem, hash: String) -> (item: ClipItem, isNew: Bool) {
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.contentHash == hash })
        if let existing = try? context.fetch(descriptor).first {
            existing.lastUsedAt = Date()
            try? context.save()
            return (existing, false)
        }
        let item = make()
        context.insert(item)
        try? context.save()
        return (item, true)
    }

    // MARK: - 操作

    func touch(_ item: ClipItem) {
        item.lastUsedAt = Date()
        try? context.save()
    }

    func togglePin(_ item: ClipItem, maxPins: Int) -> Bool {
        if !item.isPinned, pinnedCount >= maxPins {
            return false   // 超出收藏上限（免费版）
        }
        item.isPinned.toggle()
        try? context.save()
        return true
    }

    func delete(_ item: ClipItem) {
        if let path = item.imageFilePath { ImageCache.shared.remove(path) }
        if let thumb = item.thumbnailPath { ImageCache.shared.remove(thumb) }
        context.delete(item)
        try? context.save()
    }

    // MARK: - 集合

    @discardableResult
    func createCollection(name: String, symbol: String = "folder") -> ClipCollection {
        let nextIndex = (fetchCollections().map(\.sortIndex).max() ?? -1) + 1
        let c = ClipCollection(name: name, symbol: symbol, sortIndex: nextIndex)
        context.insert(c)
        try? context.save()
        return c
    }

    func renameCollection(_ c: ClipCollection, to name: String) {
        c.name = name
        try? context.save()
    }

    /// 删除集合，连带删除其中条目（含图片/缩略图缓存）。
    func deleteCollection(_ c: ClipCollection) {
        for item in fetchItems(inCollection: c.id) {
            if let path = item.imageFilePath { ImageCache.shared.remove(path) }
            if let thumb = item.thumbnailPath { ImageCache.shared.remove(thumb) }
            context.delete(item)
        }
        context.delete(c)
        try? context.save()
    }

    /// 移入/移出集合（collectionID == nil ⇒ 移回历史），并置顶到最前。
    func setCollection(_ item: ClipItem, collectionID: UUID?) {
        item.collectionID = collectionID
        item.lastUsedAt = Date()
        try? context.save()
    }

    /// 从零新建一条集合片段（提示词等，不经过剪贴板）。
    @discardableResult
    func insertSnippet(title: String?, text: String, collectionID: UUID) -> ClipItem {
        let item = ClipItem(kind: .text, previewText: String(text.prefix(500)),
                            plainText: text, contentHash: "snippet:" + UUID().uuidString)
        item.title = normalized(title)
        item.collectionID = collectionID
        context.insert(item)
        try? context.save()
        return item
    }

    func updateSnippet(_ item: ClipItem, title: String?, text: String) {
        item.title = normalized(title)
        item.plainText = text
        item.previewText = String(text.prefix(500))
        try? context.save()
    }

    private func normalized(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }

#if DEBUG
    /// 调试用：批量插入示例文本条目（复现大列表、验证分批渲染）。
    func seedSampleClips(_ n: Int) {
        let now = Date()
        for i in 0..<n {
            let text = "Sample #\(i) — the quick brown fox jumps over the lazy dog. 示例剪贴内容第 \(i) 条，用于测试列表性能与分批加载。"
            let item = ClipItem(kind: .text, previewText: String(text.prefix(500)),
                                plainText: text, contentHash: "seed:" + UUID().uuidString)
            item.lastUsedAt = now.addingTimeInterval(Double(-i))   // 递减时间戳，保证稳定倒序
            item.createdAt = item.lastUsedAt
            context.insert(item)
        }
        try? context.save()
    }
#endif

    func clearAll(keepPinned: Bool = false) {
        let items = fetchHistory()   // 仅清空历史（未归属集合），集合内容不动
        for item in items where !(keepPinned && item.isPinned) {
            if let path = item.imageFilePath { ImageCache.shared.remove(path) }
        if let thumb = item.thumbnailPath { ImageCache.shared.remove(thumb) }
            context.delete(item)
        }
        try? context.save()
    }

    // MARK: - 清理（上限 + 保留天数，跳过收藏）

    func cleanup(maxItems: Int, retentionDays: Int?) {
        let all = (try? context.fetch(FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]))) ?? []
        let cutoff = retentionDays.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }

        var survivors: [ClipItem] = []
        for item in all {
            // 置顶与集合条目永久保留，跳过清理
            if item.isPinned || item.collectionID != nil { survivors.append(item); continue }
            // 按最近使用时间清理：超过保留周期才删
            if let cutoff, item.lastUsedAt < cutoff {
                if let path = item.imageFilePath { ImageCache.shared.remove(path) }
        if let thumb = item.thumbnailPath { ImageCache.shared.remove(thumb) }
                context.delete(item)
            } else {
                survivors.append(item)
            }
        }

        // 条数上限只约束历史条目（临时流），置顶/集合不计入、不删除。
        let ephemeral = survivors.filter { !$0.isPinned && $0.collectionID == nil }
        if ephemeral.count > maxItems {
            for item in ephemeral.suffix(ephemeral.count - maxItems) {
                if let path = item.imageFilePath { ImageCache.shared.remove(path) }
        if let thumb = item.thumbnailPath { ImageCache.shared.remove(thumb) }
                context.delete(item)
            }
        }
        try? context.save()
    }
}
