import AppKit

/// 剪贴板图片落盘缓存：库里只存路径，二进制存 Application Support。
final class ImageCache {
    static let shared = ImageCache()

    private let dir: URL
    private let memory = NSCache<NSString, NSImage>()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("Clipa/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// 保存图片数据，返回文件名（相对标识）。
    func save(_ data: Data) -> String? {
        let name = UUID().uuidString + ".png"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            return nil
        }
    }

    func image(for name: String) -> NSImage? {
        if let cached = memory.object(forKey: name as NSString) { return cached }
        guard let img = NSImage(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        memory.setObject(img, forKey: name as NSString)
        return img
    }

    /// 同步返回内存缓存命中（不读盘）；未命中返回 nil，交给 loadImage 异步加载。
    func cachedImage(for name: String) -> NSImage? {
        memory.object(forKey: name as NSString)
    }

    /// 异步加载缩略图：磁盘读取放到后台线程，避免首次渲染在主线程同步读盘造成卡顿。
    @MainActor
    func loadImage(for name: String) async -> NSImage? {
        if let cached = memory.object(forKey: name as NSString) { return cached }
        let url = dir.appendingPathComponent(name)
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        guard let data, let img = NSImage(data: data) else { return nil }
        memory.setObject(img, forKey: name as NSString)
        return img
    }

    func byteSize(_ name: String) -> Int64? {
        let url = dir.appendingPathComponent(name)
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
    }

    func remove(_ name: String) {
        memory.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
}
