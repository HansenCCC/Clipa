import SwiftUI

/// 底部毛玻璃剪贴板卡片条（1:1 还原 Figma）。
struct ClipBarPanel: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var searchFocused: Bool

    /// 分批渲染窗口：切换/搜索时只先渲染这么多张卡，滚到接近末尾再无感加载下一批。
    private let pageSize = 50
    @State private var renderLimit = 50

    var body: some View {
        VStack(spacing: 0) {
            topBar
            cardArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(ClipaColor.topBorder).frame(height: 1)
        }
        .onAppear { searchFocused = true }
        .onChange(of: appState.searchFocusToken) { _, _ in searchFocused = true }
        .onChange(of: appState.segment) { _, _ in renderLimit = pageSize }      // 换段位从头渲染一小批
        .onChange(of: appState.searchText) { _, _ in renderLimit = pageSize }
        .onChange(of: appState.selectedIndex) { _, i in
            if i >= renderLimit - 4 { grow() }   // 键盘选到接近窗口末尾时扩窗
        }
    }

    private func grow() {
        let total = appState.visibleClips.count
        if renderLimit < total { renderLimit = min(total, renderLimit + pageSize) }
    }

    private var isCollection: Bool {
        if case .collection = appState.segment { return true } else { return false }
    }

    /// 浮层背景：macOS 26 用液态玻璃（Liquid Glass），旧系统回退到毛玻璃材质。
    @ViewBuilder private var panelBackground: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
                .overlay(ClipaColor.barGlassTint)
        } else {
            ZStack {
                VisualEffectView(material: .underWindowBackground)
                ClipaColor.barBG
            }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: Theme.Space.md) {
            // 品牌
            HStack(spacing: 8) {
                hamburger
                Text("Clipa").font(.system(size: 15, weight: .bold)).foregroundStyle(ClipaColor.accent)
            }

            // 搜索
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(ClipaColor.textSecondary)
                TextField("Search clipboard…", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(ClipaColor.searchBG, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClipaColor.cardBorder, lineWidth: 1))
            .frame(maxWidth: 300)

            // 分段 全部 | 置顶 | 集合… | ＋
            SegmentedPills()

            Spacer()

            // 右侧快捷键提示
            HStack(spacing: 8) {
                Text("⌘⇧V to dismiss").font(.system(size: 11)).foregroundStyle(ClipaColor.textTertiary)
                keyCap("arrow.left")
                keyCap("arrow.right")
                keyCap("return")
                Button { appState.pickColor() } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 13))
                        .foregroundStyle(ClipaColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Pick Color")
                Button { appState.takeScreenshot() } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 13))
                        .foregroundStyle(ClipaColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Screenshot")
                Button { appState.openArchiveTool() } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 13))
                        .foregroundStyle(ClipaColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Compress / Extract Files")
                Button { appState.openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(ClipaColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(height: Theme.Bar.topBarHeight)
    }

    private var hamburger: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            RoundedRectangle(cornerRadius: 1.5).frame(width: 16, height: 3)
            RoundedRectangle(cornerRadius: 1.5).frame(width: 13, height: 3)
            RoundedRectangle(cornerRadius: 1.5).frame(width: 10, height: 3)
        }
        .foregroundStyle(ClipaColor.accent.opacity(0.7))
    }

    private func keyCap(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(ClipaColor.textSecondary)
            .frame(width: 20, height: 18)
            .background(ClipaColor.keyCapBG, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ClipaColor.cardBorder, lineWidth: 0.5))
    }

    // MARK: - 卡片区

    @ViewBuilder private var cardArea: some View {
        let list = appState.visibleClips
        Group {
            if list.isEmpty {
                emptyState
            } else {
                let lead = isCollection ? 1 : 0   // 集合视图首位插入「新建片段」卡
                let shown = Array(list.prefix(renderLimit))
                CardsScrollView(
                    itemCount: shown.count + lead,
                    selectedIndex: appState.selectedIndex + lead,
                    sensitivity: appState.settings.scrollSensitivity,
                    onNearEnd: grow,
                    content: AnyView(
                        HStack(spacing: Theme.Card.spacing) {
                            if isCollection { newSnippetCard }
                            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, item in
                                ClipCardView(item: item, index: idx, isFocused: idx == appState.selectedIndex)
                                    .environmentObject(appState)
                            }
                        }
                        .padding(.horizontal, Theme.Space.lg)
                        .frame(height: Theme.Card.height + Theme.Space.md * 2)
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var emptyState: some View {
        if !appState.searchText.isEmpty {
            StateMessage(icon: "magnifyingglass", title: "No results found",
                         subtitle: "Try a different search term.")
        } else if isCollection {
            VStack(spacing: Theme.Space.sm) {
                Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(ClipaColor.textTertiary)
                Text("No items in this collection yet")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(ClipaColor.textPrimary)
                Button { addSnippet() } label: { Label("New Snippet", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            StateMessage(icon: "tray", title: emptyTitle, subtitle: emptySubtitle)
        }
    }

    /// 集合视图首位的「新建片段」卡片。
    private var newSnippetCard: some View {
        Button { addSnippet() } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundStyle(ClipaColor.accent)
                Text("New Snippet").font(.system(size: 13, weight: .medium)).foregroundStyle(ClipaColor.textSecondary)
            }
            .frame(width: Theme.Card.width, height: Theme.Card.height)
            .background(RoundedRectangle(cornerRadius: Theme.Card.radius).fill(ClipaColor.cardBG.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Card.radius)
                .strokeBorder(ClipaColor.cardBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
        }
        .buttonStyle(.plain)
    }

    private func addSnippet() {
        if case .collection(let id) = appState.segment { appState.openSnippetEditor(collectionID: id) }
    }

    private var emptyTitle: LocalizedStringKey {
        appState.segment == .pinned ? "No pinned items yet" : "No clipboard history yet"
    }
    private var emptySubtitle: LocalizedStringKey {
        appState.segment == .pinned ? "Pin items to keep them here." : "Start copying and your clips will appear here."
    }
}

/// 分段控件：全部 | 置顶 | 用户集合… | ＋（贴 Figma 风格）。
struct SegmentedPills: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 2) {
            pill(Text("All"), isOn: appState.segment == .all) { appState.segment = .all }
            pill(Text("Pinned"), isOn: appState.segment == .pinned) { appState.segment = .pinned }
            ForEach(appState.collections) { c in
                pill(Text(verbatim: c.name), isOn: appState.segment == .collection(c.id)) {
                    appState.segment = .collection(c.id)
                }
                .contextMenu {
                    Button("Rename") { appState.requestRename(c) }
                    Button("Delete", role: .destructive) { appState.confirmDeleteCollection(c) }
                }
            }
            addButton
        }
        .padding(2)
        .background(ClipaColor.segTrack, in: RoundedRectangle(cornerRadius: 8))
    }

    private func pill(_ label: Text, isOn: Bool, action: @escaping () -> Void) -> some View {
        label
            .font(.system(size: 12, weight: isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? ClipaColor.textPrimary : ClipaColor.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 6).fill(ClipaColor.segSelected)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private var addButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ClipaColor.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { appState.requestNewCollection() }
            .help("New Collection")
    }
}

/// 空态 / 无结果态通用占位。
struct StateMessage: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(ClipaColor.textTertiary)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ClipaColor.textPrimary)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(ClipaColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
