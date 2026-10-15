import AppKit
import Foundation

// Minimal production-type spies. The harness compiles these together with
// Clipa/Services/ClipboardMonitor.swift and never uses the user's general board.
enum ClipKind: Equatable { case text, link, code, color, rtf, image, file }

struct RetentionPeriod { let days: Int? = nil }

@MainActor
final class AppSettings {
    var excludedBundleIDs: [String] = []
    var effectiveMaxItems: Int { 100 }
    var retentionPeriod: RetentionPeriod { RetentionPeriod() }
}

final class ClipItem {
    var kind: ClipKind
    var previewText: String
    var plainText: String
    var contentHash: String
    var rtfData: Data?
    var colorHex: String?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var imageFilePath: String?
    var imageDimensions: String?
    var imageTransparent: Bool?
    var thumbnailPath: String?
    var fileURLStrings: [String]?

    init(kind: ClipKind, previewText: String, plainText: String, contentHash: String,
         rtfData: Data? = nil, imageFilePath: String? = nil, thumbnailPath: String? = nil,
         colorHex: String? = nil, imageDimensions: String? = nil,
         imageTransparent: Bool? = nil, fileURLStrings: [String] = [],
         sourceAppBundleID: String? = nil, sourceAppName: String? = nil) {
        self.kind = kind; self.previewText = previewText; self.plainText = plainText
        self.contentHash = contentHash; self.rtfData = rtfData; self.colorHex = colorHex
        self.sourceAppBundleID = sourceAppBundleID; self.sourceAppName = sourceAppName
        self.imageFilePath = imageFilePath; self.imageDimensions = imageDimensions
        self.imageTransparent = imageTransparent; self.thumbnailPath = thumbnailPath
        self.fileURLStrings = fileURLStrings
    }
    var fileURLs: [NSURL] { (fileURLStrings ?? []).compactMap(URL.init(string:)).map { $0 as NSURL } }
}

@MainActor
final class StorageService {
    struct Event { let kind: ClipKind; let text: String; let onMain: Bool }
    private(set) var events: [Event] = []
    private var hashes = Set<String>()

    @discardableResult
    func insertOrTouch(_ make: () -> ClipItem, hash: String) -> (item: ClipItem, isNew: Bool) {
        precondition(Thread.isMainThread)
        if hashes.contains(hash) { return (make(), false) }
        hashes.insert(hash)
        let item = make()
        events.append(Event(kind: item.kind, text: item.plainText, onMain: Thread.isMainThread))
        return (item, true)
    }
    func touch(_ item: ClipItem) { precondition(Thread.isMainThread) }
    func cleanup(maxItems: Int, retentionDays: Int?) { precondition(Thread.isMainThread) }
}

struct ParsedColor { let label: String }
enum ColorParser { static func parse(_ value: String) -> ParsedColor? { nil } }
enum FileRecognition {
    static func dimensions(data: Data) -> String? { nil }
    static func dimensions(url: URL) -> String? { nil }
    static func transparency(data: Data) -> Bool? { nil }
    static func isImage(_ url: URL) -> Bool { false }
    static func makeThumbnail(for url: URL) -> (name: String, transparent: Bool)? { nil }
    static func generateQLThumbnail(url: URL, completion: @escaping (String?) -> Void) { completion(nil) }
}
final class ImageCache {
    static let shared = ImageCache()
    func save(_ data: Data) -> String? { "harness-image" }
    func remove(_ path: String) {}
}

@main
@MainActor
struct ClipboardMonitorHarness {
    static func main() {
        if CommandLine.arguments.count >= 2,
           CommandLine.arguments[1] == "--provider" || CommandLine.arguments[1] == "--provider-sync" {
            providerMain()
            return
        }
        runHarness()
    }

    @MainActor
    static func runHarness() {
        let boardName = NSPasteboard.Name("com.hansen.clipa.harness.\(UUID().uuidString)")
        let board = NSPasteboard(name: boardName)
        let storage = StorageService()
        let settings = AppSettings()
        var changes = 0
        var mainHeartbeats = 0
        let mainHeartbeat = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in mainHeartbeats += 1 }
        RunLoop.main.add(mainHeartbeat, forMode: .common)
        let monitor = ClipboardMonitor(storage: storage, settings: settings, pasteboardName: boardName) { changes += 1 }
        monitor.start()
        defer { mainHeartbeat.invalidate(); monitor.stop() }

        // Allow the start-time asynchronous baseline read to commit before publishing a test value.
        pump(1.2)
        let baselineCount = board.changeCount
        print("DIAG baseline count=\(baselineCount) types=\(board.types?.map(\.rawValue) ?? []) heartbeats=\(mainHeartbeats)")

        board.clearContents(); board.setString("hello", forType: .string)
        let textCount = board.changeCount
        print("DIAG text-published count=\(textCount) types=\(board.types?.map(\.rawValue) ?? [])")
        let textCaptured = waitUntil { storage.events.contains { $0.kind == .text && $0.text == "hello" } }
        if !textCaptured {
            print("DIAG text-timeout count=\(board.changeCount) types=\(board.types?.map(\.rawValue) ?? []) events=\(storage.events.count) changes=\(changes) heartbeats=\(mainHeartbeats)")
        }
        check(textCaptured, "text capture")

        let advertisedSync = NSPasteboardItem()
        advertisedSync.setString("ordinary text with sync marker", forType: .string)
        advertisedSync.setData(Data([7]), forType: NSPasteboard.PasteboardType("com.apple.coredevice.dtpasteboardd.sync"))
        board.clearContents(); board.writeObjects([advertisedSync])
        let beforeGatedText = storage.events.count
        check(waitUntil { storage.events.contains { $0.text == "ordinary text with sync marker" } },
              "ordinary text with non-image advertised type capture")
        check(!storage.events.dropFirst(beforeGatedText).contains { $0.kind == .image },
              "non-image advertised type does not trigger image conversion")

        let concealed = NSPasteboardItem()
        concealed.setString("password", forType: .string)
        concealed.setData(Data([1]), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents(); board.writeObjects([concealed])
        let beforeSensitive = storage.events.count
        pump(0.8)
        check(storage.events.count == beforeSensitive, "concealed content filtered")

        let rtf = NSAttributedString(string: "rich text").rtf(from: NSRange(location: 0, length: 9), documentAttributes: [:])
        board.clearContents(); board.setData(rtf, forType: .rtf)
        check(waitUntil { storage.events.contains { $0.kind == .rtf && $0.text == "rich text" } }, "RTF capture")

        let file = URL(fileURLWithPath: "/tmp/clipa-harness-file.txt")
        board.clearContents(); board.writeObjects([file as NSURL])
        check(waitUntil { storage.events.contains { $0.kind == .file } }, "file URL capture")

        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
        image.setColor(.red, atX: 0, y: 0)
        board.clearContents(); board.setData(image.representation(using: .png, properties: [:])!, forType: .png)
        check(waitUntil { storage.events.contains { $0.kind == .image } }, "PNG capture")
        board.clearContents(); board.setData(image.tiffRepresentation!, forType: .tiff)
        let beforeTIFF = storage.events.count
        check(waitUntil { storage.events.dropFirst(beforeTIFF).contains { $0.kind == .image } }, "TIFF capture")

        // Self-write suppression: mark the current generation, then publish a value.
        board.clearContents(); board.setString("self-write", forType: .string)
        monitor.suppressNextChange(board.changeCount)
        let beforeSuppressed = storage.events.count
        pump(0.8)
        check(storage.events.count == beforeSuppressed, "self-write change suppressed")

        runDelayedProviderRegression(board: board, boardName: boardName, monitor: monitor, storage: storage)
        runDeviceSyncProviderRegression(board: board, boardName: boardName, storage: storage)

        check(storage.events.allSatisfy(\.onMain), "storage spy calls stay on main")
        check(changes > 0, "onChange delivered")
        print("PASS basic=text,sensitive,rtf,file,image,suppression,main-thread-storage")
    }

    @MainActor
    static func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if predicate() { return true }
        } while Date() < deadline
        return predicate()
    }

    @MainActor
    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor
    static func runDelayedProviderRegression(board: NSPasteboard, boardName: NSPasteboard.Name,
                                             monitor: ClipboardMonitor, storage: StorageService) {
        let status = URL(fileURLWithPath: "/tmp/clipa-harness-provider-\(UUID().uuidString).txt")
        try? FileManager.default.removeItem(at: status)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--provider", boardName.rawValue, status.path]
        do { try child.run() } catch { check(false, "launch delayed provider: \(error)"); return }
        var heartbeats = 0
        var phaseHeartbeats = 0
        var lastHeartbeat = Date()
        var maxHeartbeatGap: TimeInterval = 0
        let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let now = Date()
            maxHeartbeatGap = max(maxHeartbeatGap, now.timeIntervalSince(lastHeartbeat))
            lastHeartbeat = now
            heartbeats += 1
            phaseHeartbeats += 1
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        defer {
            heartbeat.invalidate()
            if child.isRunning { child.terminate() }
            try? FileManager.default.removeItem(at: status)
        }
        check(waitUntil({ FileManager.default.fileExists(atPath: status.path) }, timeout: 4),
              "cross-process provider starts")
        // Measure only the interval in which the provider is actually blocked.
        phaseHeartbeats = 0
        maxHeartbeatGap = 0
        lastHeartbeat = Date()
        pump(0.8)
        let before = storage.events.count
        board.clearContents(); board.setString("newer-value", forType: .string)
        check(waitUntil({ storage.events.contains { $0.text == "newer-value" } }, timeout: 5),
              "change during delayed image read captures newer value")
        check(!storage.events.dropFirst(before).contains { $0.kind == .image },
              "stale delayed image result discarded")
        check(waitUntil({ (try? String(contentsOf: status, encoding: .utf8))?.contains("end") == true }, timeout: 5),
              "delayed provider completes")
        let providerLines = (try? String(contentsOf: status, encoding: .utf8).split(separator: "\n")) ?? []
        check(providerLines.filter { $0 == "start" }.count == 1, "no overlapping provider requests")
        print("OBSERVED delayed-provider heartbeats=\(phaseHeartbeats) maxGap=\(String(format: "%.3f", maxHeartbeatGap))s totalHeartbeats=\(heartbeats)")
        check(phaseHeartbeats >= 15, "main run-loop heartbeat continues during delayed read")
        check(maxHeartbeatGap < 0.5, "main run-loop heartbeat gap stays below 0.5s")
        check(child.isRunning, "provider remains independent while monitor reads")
    }

    @MainActor
    static func runDeviceSyncProviderRegression(board: NSPasteboard, boardName: NSPasteboard.Name,
                                                storage: StorageService) {
        let status = URL(fileURLWithPath: "/tmp/clipa-harness-sync-provider-\(UUID().uuidString).txt")
        try? FileManager.default.removeItem(at: status)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--provider-sync", boardName.rawValue, status.path]
        do { try child.run() } catch { check(false, "launch sync provider: \(error)"); return }
        defer {
            if child.isRunning { child.terminate() }
            try? FileManager.default.removeItem(at: status)
        }
        check(waitUntil({
            let types = board.types ?? []
            return types.contains(.tiff) && types.contains(NSPasteboard.PasteboardType("com.apple.coredevice.dtpasteboardd.sync"))
        }, timeout: 4), "sync provider publishes TIFF plus device-sync type")
        // Give several polling intervals for an accidental TIFF request to reach the provider.
        pump(3.0)
        check(!FileManager.default.fileExists(atPath: status.path),
              "device-sync TIFF skips lazy image data request")
        let before = storage.events.count
        board.clearContents(); board.setString("sync-followup-text", forType: .string)
        check(waitUntil({ storage.events.dropFirst(before).contains { $0.text == "sync-followup-text" } }, timeout: 4),
              "text capture resumes after device-sync TIFF")
    }

    static func check(_ condition: Bool, _ name: String) {
        guard condition else { fputs("FAIL \(name)\n", stderr); exit(1) }
        print("PASS \(name)")
    }

    static func providerMain() {
        guard CommandLine.arguments.count >= 4 else { exit(2) }
        let name = NSPasteboard.Name(CommandLine.arguments[2])
        let status = URL(fileURLWithPath: CommandLine.arguments[3])
        let sync = CommandLine.arguments[1] == "--provider-sync"
        let provider = DelayedPNGProvider(statusURL: status)
        let board = NSPasteboard(name: name)
        board.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [sync ? .tiff : .png])
        if sync {
            item.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.apple.coredevice.dtpasteboardd.sync"))
        }
        board.writeObjects([item])
        RunLoop.main.run(until: Date().addingTimeInterval(8))
    }
}

final class DelayedPNGProvider: NSObject, NSPasteboardItemDataProvider {
    let statusURL: URL
    init(statusURL: URL) { self.statusURL = statusURL }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        try? "start\n".data(using: .utf8)?.write(to: statusURL, options: .atomic)
        Thread.sleep(forTimeInterval: 2.5)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
        rep.setColor(.blue, atX: 0, y: 0)
        item.setData(rep.representation(using: .png, properties: [:])!, forType: type)
        try? "start\nend\n".data(using: .utf8)?.write(to: statusURL, options: .atomic)
    }
}
