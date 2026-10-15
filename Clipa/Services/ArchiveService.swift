import Foundation
import Compression
import CommonCrypto
import Security
import SWCompression   // bz2 / xz / 7z 解压（纯 Swift，MIT）
import Unrar            // rar 解压（unrar C++ 封装；UnRAR 许可：仅解压不压缩）

enum ArchiveError: Error, LocalizedError {
    case unsupportedFormat
    case corrupt
    case encrypted
    case needsPassword
    case wrongPassword
    case unsafeEntry

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return String(localized: "This archive format isn't supported yet.")
        case .corrupt: return String(localized: "The archive appears to be damaged.")
        case .encrypted: return String(localized: "This archive uses an encryption method Clipa can't open yet.")
        case .needsPassword: return String(localized: "This archive is password-protected. Enter its password to extract.")
        case .wrongPassword: return String(localized: "Wrong password. Check it and try again.")
        case .unsafeEntry: return String(localized: "The archive contains an unsafe path and was blocked.")
        }
    }
}

/// 档 0 压缩/解压：只用系统 Foundation + Compression，无第三方依赖、沙盒安全。
/// 解压：zip / gzip(.gz) / tar / tar.gz(.tgz)。压缩：zip / gzip / tar / tar.gz。
/// 更多格式（bz2/xz/7z/zst/rar）需接 libarchive/unrar（档 1/2）。
enum ArchiveService {

    enum Format { case zip, gzip, tar, tarGzip }

    // MARK: - 格式判定

    static func format(for url: URL) -> Format? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGzip }
        if name.hasSuffix(".tar") { return .tar }
        if name.hasSuffix(".gz")  { return .gzip }
        if name.hasSuffix(".zip") { return .zip }
        return nil
    }

    static func canExtract(_ url: URL) -> Bool { extractionKind(for: url) != nil }

    /// 解压支持的所有格式（比压缩多 bz2/xz/7z——它们只解不压）。
    enum ExtractKind { case zip, gzip, tar, tarGzip, bzip2, xz, tarBzip2, tarXz, sevenZip, rar }

    static func extractionKind(for url: URL) -> ExtractKind? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz")  || name.hasSuffix(".tgz")  { return .tarGzip }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") || name.hasSuffix(".tbz") { return .tarBzip2 }
        if name.hasSuffix(".tar.xz")  || name.hasSuffix(".txz")  { return .tarXz }
        if name.hasSuffix(".tar") { return .tar }
        if name.hasSuffix(".7z")  { return .sevenZip }
        if name.hasSuffix(".rar") { return .rar }
        if name.hasSuffix(".bz2") { return .bzip2 }
        if name.hasSuffix(".xz")  { return .xz }
        if name.hasSuffix(".gz")  { return .gzip }
        if name.hasSuffix(".zip") { return .zip }
        return nil
    }

    /// 该压缩包是否需要密码（只有 zip 可能加密）。UI 据此决定是否先要密码。
    static func needsPassword(_ url: URL) -> Bool {
        if extractionKind(for: url) == .rar {
            // 头加密的 rar 直接打不开 → 视为需要密码；否则看是否有加密条目。
            guard let arc = try? Unrar.Archive(fileURL: url) else { return true }
            if arc.isHeaderEncrypted { return true }
            return ((try? arc.entries())?.contains { $0.encrypted }) ?? false
        }
        guard format(for: url) == .zip,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let entries = try? readCentralDirectory(data) else { return false }
        return entries.contains { $0.flags & 0x0001 != 0 }
    }

    // MARK: - 解压入口

    /// 后台解压到 parentDir；progress 0...1；返回解压出的目录（gzip 单文件返回该文件）。
    /// password 仅对加密 zip 有意义（AES-256 / 传统 ZipCrypto）。
    static func extract(_ archive: URL, into parentDir: URL, password: String? = nil,
                        progress: (Double) -> Void) throws -> URL {
        guard let kind = extractionKind(for: archive) else { throw ArchiveError.unsupportedFormat }
        switch kind {
        case .zip:
            return try extractZip(archive, into: parentDir, password: password, progress: progress)
        case .gzip:
            return try extractGzipFile(archive, into: parentDir, progress: progress)
        case .tar:
            let data = try Data(contentsOf: archive, options: .mappedIfSafe)
            return try extractTar(data, baseName: strip(archive, ".tar"), into: parentDir, progress: progress)
        case .tarGzip:
            let gz = try Data(contentsOf: archive, options: .mappedIfSafe)
            let tar = try gunzip(gz)
            let base = archive.lastPathComponent.lowercased().hasSuffix(".tgz") ? strip(archive, ".tgz") : strip(archive, ".tar.gz")
            return try extractTar(tar, baseName: base, into: parentDir, progress: progress)

        // 以下走 SWCompression（bz2/xz/7z）
        case .bzip2:
            return try extractSingle(archive, suffix: ".bz2", into: parentDir, progress: progress) {
                try BZip2.decompress(data: $0)
            }
        case .xz:
            return try extractSingle(archive, suffix: ".xz", into: parentDir, progress: progress) {
                try XZArchive.unarchive(archive: $0)
            }
        case .tarBzip2:
            let data = try Data(contentsOf: archive, options: .mappedIfSafe)
            let tar = try swDecompress { try BZip2.decompress(data: data) }
            return try extractTar(tar, baseName: stripTarball(archive), into: parentDir, progress: progress)
        case .tarXz:
            let data = try Data(contentsOf: archive, options: .mappedIfSafe)
            let tar = try swDecompress { try XZArchive.unarchive(archive: data) }
            return try extractTar(tar, baseName: stripTarball(archive), into: parentDir, progress: progress)
        case .sevenZip:
            return try extractSevenZip(archive, into: parentDir, progress: progress)
        case .rar:
            return try extractRar(archive, into: parentDir, password: password, progress: progress)
        }
    }

    // MARK: - RAR（unrar 封装，仅解压）

    private static func extractRar(_ archive: URL, into parentDir: URL, password: String?,
                                   progress: (Double) -> Void) throws -> URL {
        let pwd = (password ?? "").isEmpty ? nil : password
        let arc: Unrar.Archive
        do { arc = try Unrar.Archive(fileURL: archive, password: pwd) }
        catch { throw pwd == nil ? ArchiveError.needsPassword : ArchiveError.wrongPassword }

        let entries: [Unrar.Entry]
        // 头加密的 rar 在读目录时就会失败：没给密码→提示要密码，给了还失败→密码错。
        do { entries = try arc.entries() }
        catch { throw pwd == nil ? ArchiveError.needsPassword : ArchiveError.wrongPassword }

        let destDir = uniqueDir(parentDir.appendingPathComponent(strip(archive, ".rar")))
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let fm = FileManager.default
        let total = max(entries.count, 1)
        for (i, e) in entries.enumerated() {
            let name = e.fileName.replacingOccurrences(of: "\\", with: "/")   // RAR 可能用反斜杠
            guard let target = safeTarget(name, in: destDir) else { throw ArchiveError.unsafeEntry }
            if e.directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data: Data
                do { data = try arc.extract(e) }
                catch { throw e.encrypted ? (pwd == nil ? ArchiveError.needsPassword : ArchiveError.wrongPassword)
                                          : ArchiveError.corrupt }
                try data.write(to: target)
            }
            progress(Double(i + 1) / Double(total))
        }
        return destDir
    }

    // MARK: - SWCompression：bz2 / xz / 7z

    /// 单文件解压（.bz2/.xz）：解出原始字节写盘，文件名去掉后缀。
    private static func extractSingle(_ archive: URL, suffix: String, into parentDir: URL,
                                      progress: (Double) -> Void, _ decode: (Data) throws -> Data) throws -> URL {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let out = try swDecompress { try decode(data) }
        let target = uniqueFile(parentDir.appendingPathComponent(strip(archive, suffix)))
        try out.write(to: target)
        progress(1)
        return target
    }

    private static func extractSevenZip(_ archive: URL, into parentDir: URL, progress: (Double) -> Void) throws -> URL {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let entries = try swOpen { try SevenZipContainer.open(container: data) }
        let destDir = uniqueDir(parentDir.appendingPathComponent(strip(archive, ".7z")))
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let total = max(entries.count, 1)
        let fm = FileManager.default
        for (i, e) in entries.enumerated() {
            guard let target = safeTarget(e.info.name, in: destDir) else { throw ArchiveError.unsafeEntry }
            if e.info.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (e.data ?? Data()).write(to: target)
            }
            progress(Double(i + 1) / Double(total))
        }
        return destDir
    }

    /// 把 SWCompression 抛出的各种错误统一收敛成 Clipa 的「已损坏」错误。
    /// （加密的 7z/xz 也会走到这里，报「损坏」——SWCompression 不支持解密，属预期行为。）
    private static func swDecompress(_ body: () throws -> Data) throws -> Data {
        do { return try body() } catch { throw ArchiveError.corrupt }
    }
    private static func swOpen<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw ArchiveError.corrupt }
    }

    /// 去掉 .tar.bz2/.tbz2/.tbz/.tar.xz/.txz 得到目录名。
    private static func stripTarball(_ url: URL) -> String {
        let n = url.lastPathComponent
        let low = n.lowercased()
        for s in [".tar.bz2", ".tar.xz", ".tbz2", ".tbz", ".txz"] where low.hasSuffix(s) {
            return String(n.dropLast(s.count))
        }
        return n
    }

    // MARK: - 压缩入口

    /// 把 items 压缩成 <named>.<ext> 写入 destDir；password 仅对 zip 生效（AES-256）。
    static func compress(_ items: [URL], to format: Format, named: String, in destDir: URL,
                         password: String? = nil, progress: (Double) -> Void) throws -> URL {
        switch format {
        case .zip:     return try makeZip(items, named: named, in: destDir, password: password, progress: progress)
        case .tar:     return try makeTar(items, named: named, in: destDir, gzip: false, progress: progress)
        case .tarGzip: return try makeTar(items, named: named, in: destDir, gzip: true, progress: progress)
        case .gzip:    return try makeGzip(items, in: destDir)
        }
    }

    // MARK: - ZIP 解压

    private struct Entry {
        var name: String
        var method: UInt16
        var flags: UInt16
        var crc: UInt32
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
        var isAES = false
        var aesStrength: UInt8 = 0      // 1=128, 2=192, 3=256
        var actualMethod: UInt16 = 0    // AES 时的真实压缩方法
    }

    private static func extractZip(_ archive: URL, into parentDir: URL, password: String?,
                                   progress: (Double) -> Void) throws -> URL {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let entries = try readCentralDirectory(data)
        let destDir = uniqueDir(parentDir.appendingPathComponent(strip(archive, ".zip")))
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let total = max(entries.count, 1)
        for (i, e) in entries.enumerated() {
            try writeZipEntry(e, from: data, destDir: destDir, password: password)
            progress(Double(i + 1) / Double(total))
        }
        return destDir
    }

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        let n = data.count
        guard n >= 22 else { throw ArchiveError.corrupt }
        let minPos = max(0, n - 65_557)
        var eocd = -1
        var i = n - 22
        while i >= minPos {
            if byte(data, i) == 0x50, byte(data, i+1) == 0x4b, byte(data, i+2) == 0x05, byte(data, i+3) == 0x06 {
                eocd = i; break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ArchiveError.corrupt }

        let totalEntries = Int(u16(data, eocd + 10))
        var p = Int(u32(data, eocd + 16))
        var entries: [Entry] = []
        entries.reserveCapacity(totalEntries)
        for _ in 0..<totalEntries {
            guard p + 46 <= n, u32(data, p) == 0x02014b50 else { throw ArchiveError.corrupt }
            let flags = u16(data, p + 8)
            let method = u16(data, p + 10)
            let crc = u32(data, p + 16)
            let compSize = Int(u32(data, p + 20))
            let uncompSize = Int(u32(data, p + 24))
            let fnLen = Int(u16(data, p + 28))
            let exLen = Int(u16(data, p + 30))
            let cmLen = Int(u16(data, p + 32))
            let localOff = Int(u32(data, p + 42))
            let nameStart = data.startIndex + p + 46
            guard nameStart + fnLen <= data.endIndex else { throw ArchiveError.corrupt }
            let name = String(decoding: data[nameStart..<nameStart + fnLen], as: UTF8.self)
            var e = Entry(name: name, method: method, flags: flags, crc: crc,
                          compressedSize: compSize, uncompressedSize: uncompSize,
                          localHeaderOffset: localOff)
            parseAESExtra(data, at: p + 46 + fnLen, len: exLen, into: &e)   // 0x9901 → AES 参数
            entries.append(e)
            p += 46 + fnLen + exLen + cmLen
        }
        return entries
    }

    /// 扫描 extra 字段找 WinZip AES(0x9901) 头，回填强度与真实压缩方法。
    private static func parseAESExtra(_ data: Data, at off: Int, len: Int, into e: inout Entry) {
        var q = off
        let end = min(off + len, data.count)   // len 来自中央目录、不可信，须夹到实际字节数内
        while q + 4 <= end {
            let id = u16(data, q); let sz = Int(u16(data, q + 2))
            if id == 0x9901, q + 4 + 7 <= data.count {
                e.isAES = true
                e.aesStrength = byte(data, q + 4 + 4)              // 版本(2)+厂商(2) 之后
                e.actualMethod = u16(data, q + 4 + 5)
            }
            q += 4 + sz
        }
    }

    private static func writeZipEntry(_ e: Entry, from data: Data, destDir: URL, password: String?) throws {
        let encrypted = e.flags & 0x0001 != 0
        if e.compressedSize == Int(UInt32.max) || e.uncompressedSize == Int(UInt32.max) {
            throw ArchiveError.unsupportedFormat   // ZIP64 暂不支持
        }
        guard let target = safeTarget(e.name, in: destDir) else { throw ArchiveError.unsafeEntry }

        if e.name.hasSuffix("/") {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            return
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let lo = e.localHeaderOffset
        guard lo + 30 <= data.count, u32(data, lo) == 0x04034b50 else { throw ArchiveError.corrupt }
        let start = lo + 30 + Int(u16(data, lo + 26)) + Int(u16(data, lo + 28))
        let s = data.startIndex + start
        guard s + e.compressedSize <= data.endIndex else { throw ArchiveError.corrupt }
        var comp = Data(data[s..<s + e.compressedSize])

        // 解密（得到「解密后的压缩流」）——真实压缩方法随后再 inflate。
        var method = e.method
        if encrypted {
            let pwd = password ?? ""
            guard !pwd.isEmpty else { throw ArchiveError.needsPassword }
            if e.isAES {
                comp = try aesDecrypt(comp, password: pwd, strength: e.aesStrength)
                method = e.actualMethod
            } else if e.method != 99 {
                comp = try zipCryptoDecrypt(comp, password: pwd, entry: e)
            } else {
                throw ArchiveError.encrypted
            }
        }

        let out: Data
        switch method {
        case 0: out = comp
        case 8: out = try inflate(comp, expectedSize: e.uncompressedSize)
        default: throw ArchiveError.unsupportedFormat
        }
        try out.write(to: target)
    }

    // MARK: - 解密：WinZip AES-256 / 传统 ZipCrypto

    /// 还原 aesEncrypt：salt + 校验(2) + 密文 + 认证(10)。密码错抛 wrongPassword。
    private static func aesDecrypt(_ blob: Data, password: String, strength: UInt8) throws -> Data {
        let saltLen = strength == 1 ? 8 : (strength == 2 ? 12 : 16)
        let keyLen  = strength == 1 ? 16 : (strength == 2 ? 24 : 32)
        guard blob.count >= saltLen + 2 + 10 else { throw ArchiveError.corrupt }
        let salt   = Data(blob[blob.startIndex ..< blob.startIndex + saltLen])
        let verify = Data(blob[blob.startIndex + saltLen ..< blob.startIndex + saltLen + 2])
        let cipher = Data(blob[blob.startIndex + saltLen + 2 ..< blob.endIndex - 10])
        let derived = pbkdf2(password, salt: salt, length: 2 * keyLen + 2)
        guard Data(derived[(2 * keyLen)..<(2 * keyLen + 2)]) == verify else { throw ArchiveError.wrongPassword }
        return aesCTR(cipher, key: Data(derived[0..<keyLen]))   // CTR 对称，同一函数即解密
    }

    /// 传统 PKWARE ZipCrypto：12 字节加密头 + 流式 XOR。密码错时校验字节不符 → wrongPassword。
    private static func zipCryptoDecrypt(_ blob: Data, password: String, entry e: Entry) throws -> Data {
        guard blob.count >= 12 else { throw ArchiveError.corrupt }
        var k0: UInt32 = 0x1234_5678, k1: UInt32 = 0x2345_6789, k2: UInt32 = 0x3456_7890
        func upd(_ b: UInt8) {
            k0 = crcTable[Int((k0 ^ UInt32(b)) & 0xff)] ^ (k0 >> 8)
            k1 = (k1 &+ (k0 & 0xff)) &* 134_775_813 &+ 1
            k2 = crcTable[Int((k2 ^ (k1 >> 24)) & 0xff)] ^ (k2 >> 8)
        }
        func stream() -> UInt8 {
            let t = (k2 | 2) & 0xffff
            return UInt8(((t &* (t ^ 1)) >> 8) & 0xff)
        }
        for b in password.utf8 { upd(b) }
        var out = [UInt8](); out.reserveCapacity(blob.count - 12)
        var header11: UInt8 = 0
        for (i, byte) in blob.enumerated() {
            let c = byte ^ stream()
            upd(c)
            if i == 11 { header11 = c } else if i > 11 { out.append(c) }
        }
        // 无 data-descriptor 时，第 12 字节应等于 CRC 高位；不符即密码错。
        if e.flags & 0x0008 == 0, header11 != UInt8(e.crc >> 24) { throw ArchiveError.wrongPassword }
        return Data(out)
    }

    // MARK: - GZIP 解压

    /// 解开 gzip 流，返回原始字节（.gz 文件内容或 tar.gz 里的 tar）。
    private static func gunzip(_ data: Data) throws -> Data {
        let n = data.count
        guard n >= 18, byte(data, 0) == 0x1f, byte(data, 1) == 0x8b, byte(data, 2) == 0x08 else { throw ArchiveError.corrupt }
        let flg = byte(data, 3)
        var p = 10
        if flg & 0x04 != 0 {                        // FEXTRA
            let xlen = Int(u16(data, p)); p += 2 + xlen
        }
        if flg & 0x08 != 0 { while p < n, byte(data, p) != 0 { p += 1 }; p += 1 }   // FNAME
        if flg & 0x10 != 0 { while p < n, byte(data, p) != 0 { p += 1 }; p += 1 }   // FCOMMENT
        if flg & 0x02 != 0 { p += 2 }               // FHCRC
        guard p <= n - 8 else { throw ArchiveError.corrupt }
        let isize = Int(u32(data, n - 4))           // 原始大小 mod 2^32
        let s = data.startIndex + p
        let comp = data[s..<(data.endIndex - 8)]
        return try inflate(Data(comp), expectedSize: isize)
    }

    private static func extractGzipFile(_ archive: URL, into parentDir: URL, progress: (Double) -> Void) throws -> URL {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let out = try gunzip(data)
        let target = uniqueFile(parentDir.appendingPathComponent(strip(archive, ".gz")))
        try out.write(to: target)
        progress(1)
        return target
    }

    // MARK: - TAR 解压

    private static func extractTar(_ data: Data, baseName: String, into parentDir: URL,
                                   progress: (Double) -> Void) throws -> URL {
        let destDir = uniqueDir(parentDir.appendingPathComponent(baseName))
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let fm = FileManager.default
        let end = data.count
        var p = 0
        var longName: String?
        while p + 512 <= end {
            if isZeroBlock(data, p) { break }
            let name0 = cString(data, p, 100)
            let size = octal(data, p + 124, 12)
            let type = byte(data, p + 156)
            let padded = (size + 511) / 512 * 512
            p += 512
            let dataStart = p

            if type == UInt8(ascii: "L") {                 // GNU 长文件名
                guard size >= 0, dataStart + size <= end else { throw ArchiveError.corrupt }
                longName = cString(data, dataStart, size)
                p += padded; continue
            }
            if type == UInt8(ascii: "x") || type == UInt8(ascii: "g") {   // pax 扩展头：跳过，用 ustar 名
                p += padded; continue
            }

            let name = longName ?? name0
            longName = nil
            guard !name.isEmpty else { p += padded; continue }
            guard let target = safeTarget(name, in: destDir) else { throw ArchiveError.unsafeEntry }

            if type == UInt8(ascii: "5") || name.hasSuffix("/") {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else if type == UInt8(ascii: "0") || type == 0 {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let s = data.startIndex + dataStart
                guard s + size <= data.endIndex else { throw ArchiveError.corrupt }
                try Data(data[s..<s + size]).write(to: target)
            }
            // 其它类型（符号/硬链接等）v1 跳过
            p += padded
            progress(Double(p) / Double(max(end, 1)))
        }
        return destDir
    }

    // MARK: - 压缩：ZIP

    private static func makeZip(_ items: [URL], named: String, in destDir: URL,
                                password: String?, progress: (Double) -> Void) throws -> URL {
        struct CDir { var name: [UInt8]; var crc: UInt32; var comp: UInt32; var uncomp: UInt32
                      var method: UInt16; var flags: UInt16; var extra: [UInt8]; var offset: UInt32 }
        let files = collectFiles(items)
        let encrypt = !(password ?? "").isEmpty
        var out = Data()
        var dirs: [CDir] = []

        for (i, f) in files.enumerated() {
            let raw = (try? Data(contentsOf: f.url)) ?? Data()
            var comp = deflate(raw)
            var actualMethod: UInt16 = 8
            if comp.isEmpty || comp.count >= raw.count { comp = raw; actualMethod = 0 }   // 存储更划算

            var stored = comp
            var method = actualMethod
            var flags: UInt16 = 0
            var extra: [UInt8] = []
            var storedCRC = crc32(raw)
            if encrypt {
                stored = aesEncrypt(comp, password: password!)   // salt + 校验(2) + 密文 + 认证(10)
                method = 99                                       // 加密标记，真实方法在 AES 扩展字段
                flags = 0x0001
                extra = aesExtraField(actualMethod: actualMethod)
                storedCRC = 0                                     // AE-2 不存 CRC
            }

            let nameBytes = Array(f.rel.utf8)
            let offset = UInt32(out.count)
            out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(flags)); out.append(le16(method))
            out.append(le16(0)); out.append(le16(0))
            out.append(le32(storedCRC)); out.append(le32(UInt32(stored.count))); out.append(le32(UInt32(raw.count)))
            out.append(le16(UInt16(nameBytes.count))); out.append(le16(UInt16(extra.count)))
            out.append(contentsOf: nameBytes); out.append(contentsOf: extra)
            out.append(stored)

            dirs.append(CDir(name: nameBytes, crc: storedCRC, comp: UInt32(stored.count), uncomp: UInt32(raw.count),
                             method: method, flags: flags, extra: extra, offset: offset))
            progress(Double(i + 1) / Double(max(files.count, 1)))
        }

        let cdStart = out.count
        for d in dirs {
            out.append(le32(0x02014b50)); out.append(le16(20)); out.append(le16(20)); out.append(le16(d.flags)); out.append(le16(d.method))
            out.append(le16(0)); out.append(le16(0))
            out.append(le32(d.crc)); out.append(le32(d.comp)); out.append(le32(d.uncomp))
            out.append(le16(UInt16(d.name.count))); out.append(le16(UInt16(d.extra.count))); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0)); out.append(le32(0)); out.append(le32(d.offset))
            out.append(contentsOf: d.name); out.append(contentsOf: d.extra)
        }
        let cdSize = out.count - cdStart
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(dirs.count))); out.append(le16(UInt16(dirs.count)))
        out.append(le32(UInt32(cdSize))); out.append(le32(UInt32(cdStart))); out.append(le16(0))

        let url = uniqueFile(destDir.appendingPathComponent(named + ".zip"))
        try out.write(to: url)
        return url
    }

    // MARK: - WinZip AES-256 加密（AE-2）

    /// 加密一个条目：返回 salt(16) + 口令校验(2) + AES-CTR 密文 + HMAC-SHA1 认证码(10)。
    private static func aesEncrypt(_ data: Data, password: String) -> Data {
        let salt = randomBytes(16)                                   // AES-256 → 16 字节盐
        let derived = pbkdf2(password, salt: salt, length: 66)       // 32 加密 + 32 认证 + 2 校验
        let encKey = Data(derived[0..<32])
        let authKey = Data(derived[32..<64])
        let verify = Data(derived[64..<66])
        let cipher = aesCTR(data, key: encKey)
        let auth = hmacSHA1(cipher, key: authKey).prefix(10)
        var out = Data(); out.append(salt); out.append(verify); out.append(cipher); out.append(auth)
        return out
    }

    /// 0x9901 扩展字段（7 字节数据）：版本 AE-2 + 厂商 "AE" + 强度 AES-256 + 真实压缩方法。
    private static func aesExtraField(actualMethod: UInt16) -> [UInt8] {
        [0x01, 0x99, 0x07, 0x00, 0x02, 0x00, 0x41, 0x45, 0x03,
         UInt8(actualMethod & 0xff), UInt8(actualMethod >> 8)]
    }

    /// WinZip AES 的 CTR：计数器 128 位小端、从 1 开始，逐块 AES-256-ECB 加密后异或。
    private static func aesCTR(_ data: Data, key: Data) -> Data {
        let n = data.count
        if n == 0 { return Data() }
        var out = Data(count: n)
        let blocks = (n + 15) / 16
        var counter = [UInt8](repeating: 0, count: 16)
        var ks = [UInt8](repeating: 0, count: 16)
        key.withUnsafeBytes { kb in
        data.withUnsafeBytes { sb in
        out.withUnsafeMutableBytes { db in
            let k = kb.bindMemory(to: UInt8.self).baseAddress!
            let s = sb.bindMemory(to: UInt8.self).baseAddress!
            let d = db.bindMemory(to: UInt8.self).baseAddress!
            for b in 0..<blocks {
                var v = UInt64(b + 1)
                for i in 0..<8 { counter[i] = UInt8(truncatingIfNeeded: v); v >>= 8 }
                for i in 8..<16 { counter[i] = 0 }
                var moved = 0
                CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                        k, key.count, nil, counter, 16, &ks, 16, &moved)
                let off = b * 16
                let cnt = min(16, n - off)
                for i in 0..<cnt { d[off + i] = s[off + i] ^ ks[i] }
            }
        }}}
        return out
    }

    private static func pbkdf2(_ password: String, salt: Data, length: Int) -> Data {
        var out = Data(count: length)
        let pw = Array(password.utf8)
        out.withUnsafeMutableBytes { ob in
        salt.withUnsafeBytes { sb in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.count,
                    sb.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1000,
                    ob.bindMemory(to: UInt8.self).baseAddress, length)
        }}
        return out
    }

    private static func hmacSHA1(_ data: Data, key: Data) -> Data {
        var mac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        key.withUnsafeBytes { kb in data.withUnsafeBytes { db in
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), kb.baseAddress, key.count, db.baseAddress, data.count, &mac)
        }}
        return Data(mac)
    }

    private static func randomBytes(_ n: Int) -> Data {
        var d = Data(count: n)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        return d
    }

    // MARK: - 压缩：TAR / TAR.GZ

    private static func makeTar(_ items: [URL], named: String, in destDir: URL, gzip: Bool,
                                progress: (Double) -> Void) throws -> URL {
        let files = collectFiles(items)
        var tar = Data()
        for (i, f) in files.enumerated() {
            let raw = (try? Data(contentsOf: f.url)) ?? Data()
            tar.append(try tarHeader(name: f.rel, size: raw.count))
            tar.append(raw)
            let pad = (512 - raw.count % 512) % 512
            if pad > 0 { tar.append(Data(count: pad)) }
            progress(Double(i + 1) / Double(max(files.count, 1)))
        }
        tar.append(Data(count: 1024))   // 结尾两个空块

        let url = uniqueFile(destDir.appendingPathComponent(named + (gzip ? ".tar.gz" : ".tar")))
        try (gzip ? gzipData(tar) : tar).write(to: url)
        return url
    }

    private static func makeGzip(_ items: [URL], in destDir: URL) throws -> URL {
        guard items.count == 1 else { throw ArchiveError.unsupportedFormat }   // gzip 只压单文件
        let raw = try Data(contentsOf: items[0])
        let url = uniqueFile(destDir.appendingPathComponent(items[0].lastPathComponent + ".gz"))
        try gzipData(raw).write(to: url)
        return url
    }

    private static func tarHeader(name: String, size: Int) throws -> Data {
        var h = [UInt8](repeating: 0, count: 512)
        let nameBytes = Array(name.utf8)
        guard nameBytes.count <= 100 else { throw ArchiveError.unsupportedFormat }   // v1：名字 ≤100
        for (i, b) in nameBytes.enumerated() { h[i] = b }
        func oct(_ v: Int, _ off: Int, _ len: Int) {
            let s = String(v, radix: 8)
            let pad = String(repeating: "0", count: max(0, len - 1 - s.count)) + s
            for (i, c) in pad.utf8.enumerated() where i < len - 1 { h[off + i] = c }
        }
        oct(0o644, 100, 8); oct(0, 108, 8); oct(0, 116, 8); oct(size, 124, 12); oct(0, 136, 12)
        h[156] = UInt8(ascii: "0")
        for (i, b) in Array("ustar".utf8).enumerated() { h[257 + i] = b }
        h[263] = 0x30; h[264] = 0x30                       // version "00"
        for i in 148..<156 { h[i] = 0x20 }                 // 校验和字段先填空格
        var sum = 0; for b in h { sum += Int(b) }
        let cs = String(sum, radix: 8)
        let csPad = String(repeating: "0", count: max(0, 6 - cs.count)) + cs
        for (i, c) in csPad.utf8.enumerated() where i < 6 { h[148 + i] = c }
        h[154] = 0; h[155] = 0x20
        return Data(h)
    }

    private static func gzipData(_ raw: Data) -> Data {
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])   // flg=0, OS=unknown
        out.append(raw.isEmpty ? Data([0x03, 0x00]) : deflate(raw))
        out.append(le32(crc32(raw)))
        out.append(le32(UInt32(raw.count & 0xFFFFFFFF)))
        return out
    }

    // MARK: - DEFLATE 编解码（系统 Compression）

    private static func inflate(_ src: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        guard !src.isEmpty else { throw ArchiveError.corrupt }   // 空压缩流 + 期望非空 → baseAddress! 会 nil
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { d -> Int in
            src.withUnsafeBytes { s -> Int in
                compression_decode_buffer(d.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          s.bindMemory(to: UInt8.self).baseAddress!, src.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ArchiveError.corrupt }
        return dst
    }

    private static func deflate(_ src: Data) -> Data {
        if src.isEmpty { return Data() }
        let cap = src.count + src.count / 100 + 128
        var dst = Data(count: cap)
        let n = dst.withUnsafeMutableBytes { d -> Int in
            src.withUnsafeBytes { s -> Int in
                compression_encode_buffer(d.bindMemory(to: UInt8.self).baseAddress!, cap,
                                          s.bindMemory(to: UInt8.self).baseAddress!, src.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? dst.prefix(n) : Data()   // n==0：不可压缩，交由调用方回退到 store
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    // MARK: - 小工具

    private static func byte(_ d: Data, _ i: Int) -> UInt8 { d[d.startIndex + i] }
    private static func u16(_ d: Data, _ off: Int) -> UInt16 {
        UInt16(byte(d, off)) | (UInt16(byte(d, off + 1)) << 8)
    }
    private static func u32(_ d: Data, _ off: Int) -> UInt32 {
        UInt32(byte(d, off)) | (UInt32(byte(d, off + 1)) << 8)
            | (UInt32(byte(d, off + 2)) << 16) | (UInt32(byte(d, off + 3)) << 24)
    }
    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)])
    }

    private static func cString(_ d: Data, _ off: Int, _ maxLen: Int) -> String {
        var bytes = [UInt8]()
        var i = 0
        while i < maxLen {
            let b = byte(d, off + i)
            if b == 0 { break }
            bytes.append(b); i += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    private static func octal(_ d: Data, _ off: Int, _ len: Int) -> Int {
        var v = 0
        for i in 0..<len {
            let b = byte(d, off + i)
            if b >= 0x30 && b <= 0x37 { v = v * 8 + Int(b - 0x30) }
            else if b == 0x20 || b == 0 { continue }
            else { break }
        }
        return v
    }
    private static func isZeroBlock(_ d: Data, _ off: Int) -> Bool {
        for i in 0..<512 where byte(d, off + i) != 0 { return false }
        return true
    }

    /// zip-slip 防护 + 目标 URL：拒绝绝对路径与 ".."。
    private static func safeTarget(_ name: String, in destDir: URL) -> URL? {
        guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { return nil }
        return destDir.appendingPathComponent(name)
    }

    private static func strip(_ url: URL, _ suffix: String) -> String {
        let n = url.lastPathComponent
        return n.lowercased().hasSuffix(suffix) ? String(n.dropLast(suffix.count)) : n
    }

    /// 递归展开 items 为「文件 + 相对路径」；目录用其名做前缀。
    private static func collectFiles(_ items: [URL]) -> [(url: URL, rel: String)] {
        let fm = FileManager.default
        var out: [(URL, String)] = []
        for item in items {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let base = item.lastPathComponent
                let prefix = item.path.hasSuffix("/") ? item.path : item.path + "/"
                if let en = fm.enumerator(at: item, includingPropertiesForKeys: [.isDirectoryKey]) {
                    for case let f as URL in en {
                        var d: ObjCBool = false
                        fm.fileExists(atPath: f.path, isDirectory: &d)
                        if !d.boolValue {
                            let rel = base + "/" + f.path.replacingOccurrences(of: prefix, with: "")
                            out.append((f, rel))
                        }
                    }
                }
            } else {
                out.append((item, item.lastPathComponent))
            }
        }
        return out
    }

    private static func uniqueDir(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }
        var i = 2
        while true {
            let c = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent) \(i)")
            if !fm.fileExists(atPath: c.path) { return c }
            i += 1
        }
    }
    private static func uniqueFile(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var i = 2
        while true {
            let c = dir.appendingPathComponent("\(base) \(i)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !fm.fileExists(atPath: c.path) { return c }
            i += 1
        }
    }
}
