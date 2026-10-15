import SwiftUI
import UniformTypeIdentifiers

/// 压缩/解压面板：可由 Finder 右键「用 Clipa…」/「打开方式」把文件交过来，
/// 也可从 Clipa 内部直接打开（此时先让用户拖入或选取文件/文件夹）。
/// 用户在这里选「解压」或「压缩为某格式」，再选目标位置后台执行、带进度与结果。
struct FileActionView: View {
    var onClose: () -> Void

    enum Mode: Hashable { case extract, compress }
    enum Phase { case idle, working, done, failed }

    @State private var urls: [URL]
    @State private var mode: Mode
    @State private var format: ArchiveService.Format = .zip
    @State private var password = ""            // 压缩：设置密码（可选）
    @State private var extractPassword = ""     // 解压：加密包所需密码
    @State private var extractNeedsPassword = false
    @State private var phase: Phase = .idle
    @State private var progress: Double = 0
    @State private var resultURL: URL?
    @State private var errorText: String?
    @State private var isDropTargeted = false

    private var archives: [URL] { urls.filter { ArchiveService.canExtract($0) } }
    private var hasArchive: Bool { !archives.isEmpty }

    init(urls: [URL], onClose: @escaping () -> Void) {
        self.onClose = onClose
        _urls = State(initialValue: urls)
        _mode = State(initialValue: urls.contains { ArchiveService.canExtract($0) } ? .extract : .compress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            if urls.isEmpty {
                dropZone
            } else if phase == .idle {
                controls
            } else {
                statusArea
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Space.lg)
        .frame(width: 460, height: 360)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDropped(providers); return true
        }
        .onAppear(perform: refreshEncryptionFlag)
        .onChange(of: urls) { _, _ in
            guard phase != .working else { return }   // 运行中不打断
            if phase != .idle {                       // 上一次已完成/失败：换文件即回到选择界面
                phase = .idle; resultURL = nil; errorText = nil; progress = 0
            }
            mode = hasArchive ? .extract : .compress
            refreshEncryptionFlag()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox").font(.system(size: 32)).foregroundStyle(ClipaColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText).font(Theme.Font.headline).lineLimit(1)
                Text(subtitleText).font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
            }
            Spacer()
        }
    }
    private var titleText: String {
        if urls.isEmpty { return String(localized: "Compress or Extract") }
        return urls.count == 1 ? urls[0].lastPathComponent : "Clipa"
    }
    private var subtitleText: String {
        urls.isEmpty ? String(localized: "Drag in files, or choose them below.")
                     : String(localized: "\(urls.count) items selected")
    }

    // MARK: - 空态：拖入 / 选取

    private var dropZone: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40)).foregroundStyle(ClipaColor.accent.opacity(0.8))
            Text("Drop files or folders here").font(Theme.Font.headline)
            Text("Drop an archive to extract it, or anything else to compress.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Space.sm) {
                Button("Choose Files…") { chooseInput(directories: false) }
                Button("Choose Folder…") { chooseInput(directories: true) }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(isDropTargeted ? ClipaColor.accent.opacity(0.12) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isDropTargeted ? ClipaColor.accent : ClipaColor.cardBorder,
                          style: StrokeStyle(lineWidth: 1.5, dash: [7])))
    }

    // MARK: - 选项

    @ViewBuilder private var controls: some View {
        Picker("", selection: $mode) {
            if hasArchive { Text("Extract").tag(Mode.extract) }
            Text("Compress").tag(Mode.compress)
        }
        .pickerStyle(.segmented).labelsHidden()

        if mode == .compress {
            HStack(spacing: Theme.Space.sm) {
                Text("Format")
                Picker("", selection: $format) {
                    Text(verbatim: "ZIP").tag(ArchiveService.Format.zip)
                    Text(verbatim: "TAR").tag(ArchiveService.Format.tar)
                    Text(verbatim: "TAR.GZ").tag(ArchiveService.Format.tarGzip)
                    if urls.count == 1 { Text(verbatim: "GZIP").tag(ArchiveService.Format.gzip) }
                }
                .labelsHidden().frame(width: 150)
            }
            if format == .zip {
                SecureField("Password (optional)", text: $password)
                    .textFieldStyle(.roundedBorder)
                Text("AES-256. Password-protected zips open in Keka, 7-Zip or WinRAR — the macOS Archive Utility can't open them.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Extract the selected archive(s) into a folder you choose.")
                .font(Theme.Font.body).foregroundStyle(Theme.Color.secondary)
            if extractNeedsPassword {
                SecureField("Archive password", text: $extractPassword)
                    .textFieldStyle(.roundedBorder)
                Text("This archive is password-protected.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.tertiary)
            }
        }
    }

    // MARK: - 状态

    @ViewBuilder private var statusArea: some View {
        switch phase {
        case .working:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress).progressViewStyle(.linear)
                Text(mode == .extract ? "Extracting…" : "Compressing…")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
            }
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.Color.success).font(Theme.Font.headline)
        case .failed:
            Label(errorText ?? "", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Color.danger).font(Theme.Font.body)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - 底部按钮

    @ViewBuilder private var footer: some View {
        HStack {
            // 已导入文件、且未开始执行时，左下角给一个「返回」回到拖入/选取界面。
            if phase == .idle, !urls.isEmpty {
                Button { resetSelection() } label: { Label("Back", systemImage: "chevron.left") }
            }
            Spacer()
            switch phase {
            case .idle:
                Button("Cancel") { onClose() }
                if !urls.isEmpty {
                    Button(mode == .extract ? "Extract…" : "Compress…") { chooseAndRun() }
                        .buttonStyle(.borderedProminent)
                        .disabled(mode == .extract && !hasArchive)
                }
            case .working:
                Button("Cancel") { onClose() }.disabled(true)
            case .done:
                Button("Close") { onClose() }
                Button("Show in Finder") { reveal() }.buttonStyle(.borderedProminent)
            case .failed:
                Button("Close") { onClose() }
                Button("Try Again") { phase = .idle }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 选取 / 拖入

    /// 「返回」：清空已选文件，回到拖入 / 选取的初始界面。
    private func resetSelection() {
        urls = []
        password = ""
        extractPassword = ""
    }

    private func chooseInput(directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        urls.append(contentsOf: panel.urls)
    }

    /// 读取拖入的文件 URL。用 loadDataRepresentation 拿原始字节自行解码，
    /// 绕开 loadObject(URL) 的 NSSecureCoding/XPC 解码路径（会刷 NSObject/bad-range 警告且偶尔失败）。
    private func loadDropped(_ providers: [NSItemProvider]) {
        let fileURLType = UTType.fileURL.identifier
        for p in providers {
            _ = p.loadDataRepresentation(forTypeIdentifier: fileURLType) { data, _ in
                guard let data else { return }
                let url = URL(dataRepresentation: data, relativeTo: nil)
                    ?? String(data: data, encoding: .utf8).flatMap { URL(string: $0) }
                guard let url else { return }
                Task { @MainActor in
                    if !urls.contains(url) { urls.append(url) }
                }
            }
        }
    }

    /// 解压模式下，若所选压缩包有加密条目就显示密码框。
    private func refreshEncryptionFlag() {
        let arcs = archives
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = arcs.map { ($0, $0.startAccessingSecurityScopedResource()) }
            let need = arcs.contains { ArchiveService.needsPassword($0) }
            for (u, ok) in scoped where ok { u.stopAccessingSecurityScopedResource() }
            Task { @MainActor in extractNeedsPassword = need }
        }
    }

    // MARK: - 执行

    private func chooseAndRun() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: mode == .extract ? "Extract Here" : "Save Here")
        panel.directoryURL = urls.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        run(to: dest)
    }

    private func run(to dest: URL) {
        phase = .working
        progress = 0
        let items = urls
        let arcs = archives
        let m = mode
        let fmt = format
        let pwd = mode == .extract ? extractPassword : password
        let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive"

        Task.detached(priority: .userInitiated) {
            let acc = items.map { $0.startAccessingSecurityScopedResource() }
            let da = dest.startAccessingSecurityScopedResource()
            defer {
                for (u, a) in zip(items, acc) where a { u.stopAccessingSecurityScopedResource() }
                if da { dest.stopAccessingSecurityScopedResource() }
            }
            do {
                let out: URL
                if m == .extract {
                    var last: URL?
                    for (i, a) in arcs.enumerated() {
                        last = try ArchiveService.extract(a, into: dest,
                                                          password: pwd.isEmpty ? nil : pwd) { p in
                            Task { @MainActor in self.progress = (Double(i) + p) / Double(arcs.count) }
                        }
                    }
                    out = last ?? dest
                } else {
                    out = try ArchiveService.compress(items, to: fmt, named: name, in: dest,
                                                      password: pwd.isEmpty ? nil : pwd) { p in
                        Task { @MainActor in self.progress = p }
                    }
                }
                await MainActor.run { self.resultURL = out; self.phase = .done }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { self.errorText = msg; self.phase = .failed }
            }
        }
    }

    private func reveal() {
        if let u = resultURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }
}
