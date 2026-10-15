import Foundation
import SwiftData

enum ClipKind: String, Codable, CaseIterable {
    case text, rtf, link, image, file, code, color
}

@Model
final class ClipItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var previewText: String
    var plainText: String
    var rtfData: Data?
    var imageFilePath: String?
    /// 图片文件的缩略图缓存名（复制图片文件时生成，用于显示预览但仍按文件粘贴）。
    var thumbnailPath: String?
    /// 颜色识别命中时的规范化色值（如 "#000000"）。
    var colorHex: String?
    /// 图片像素尺寸（如 "920 × 435"）。
    var imageDimensions: String?
    /// 图片是否含真实透明（决定是否显示棋盘格）。
    var imageTransparent: Bool?
    var fileURLStrings: [String]
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var createdAt: Date
    var lastUsedAt: Date
    var isPinned: Bool
    /// 内容指纹，用于去重。
    var contentHash: String
    /// 归属集合的 id；非 nil ⇒ 已存入用户集合（永久保存，不受历史清理影响）。
    var collectionID: UUID? = nil
    /// 集合条目的可选标题（如提示词名称）；历史 clip 通常为 nil。
    var title: String? = nil

    var kind: ClipKind {
        get { ClipKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var fileURLs: [URL] { fileURLStrings.compactMap { URL(string: $0) } }

    init(
        kind: ClipKind,
        previewText: String,
        plainText: String,
        contentHash: String,
        rtfData: Data? = nil,
        imageFilePath: String? = nil,
        thumbnailPath: String? = nil,
        colorHex: String? = nil,
        imageDimensions: String? = nil,
        imageTransparent: Bool? = nil,
        fileURLStrings: [String] = [],
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.previewText = previewText
        self.plainText = plainText
        self.contentHash = contentHash
        self.rtfData = rtfData
        self.imageFilePath = imageFilePath
        self.thumbnailPath = thumbnailPath
        self.colorHex = colorHex
        self.imageDimensions = imageDimensions
        self.imageTransparent = imageTransparent
        self.fileURLStrings = fileURLStrings
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        let now = Date()
        self.createdAt = now
        self.lastUsedAt = now
        self.isPinned = false
    }
}
