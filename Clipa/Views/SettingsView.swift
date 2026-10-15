import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ExcludedAppsSettings().tabItem { Label("Excluded Apps", systemImage: "nosign") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
            #if DEBUG
            DebugSettings().tabItem { Label { Text(verbatim: "Debug") } icon: { Image(systemName: "ladybug") } }
            #endif
        }
        .frame(width: 580, height: 520)
        .environmentObject(appState)
        .environmentObject(appState.settings)
    }
}

// MARK: - General（含 历史 / 外观 / 语言 / 粘贴）

private struct GeneralSettings: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Global Shortcut") { ShortcutRecorder() }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, v in LaunchAtLoginService.set(v) }
                Picker("Language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.labelKey).tag($0) }
                }
                Text("Restart Clipa to apply the language change.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
                HStack {
                    Text("Scroll sensitivity")
                    Slider(value: $settings.scrollSensitivity, in: 1...8)
                }
            }

            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.labelKey).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.appearance) { _, _ in settings.applyAppearance() }
            }

            Section("History") {
                Picker("Max items", selection: limitBinding) {
                    Text("50").tag(50)
                    Text("200").tag(200)
                    Text("500").tag(500)
                    Text("Unlimited").tag(Int.max)
                    Text("Custom").tag(-1)
                }
                if showCustom {
                    TextField("Custom count", value: $settings.maxHistoryCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                if !settings.isPro {
                    Text("Free version keeps up to \(AppSettings.freeMaxItems) items. Unlock Pro for unlimited.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
                }
                Picker("Auto-clear after", selection: $settings.retentionPeriod) {
                    ForEach(RetentionPeriod.allCases) { Text($0.labelKey).tag($0) }
                }
                Button("Clear All History", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Clear all clipboard history?", isPresented: $confirmClear) {
                        Button("Clear All", role: .destructive) {
                            appState.clearAllHistory()
                        }
                    }
            }

            // 自动粘贴（Auto-paste）功能暂时隐藏：当前仅支持手动 ⌘V 粘贴。
            // 如需恢复，把下方 Paste Section 取消注释即可。
            /*
            Section("Paste") {
                Picker("When you select a clip", selection: $settings.pasteBehavior) {
                    ForEach(PasteBehavior.allCases) { Text($0.labelKey).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.pasteBehavior) { _, v in
                    if v == .auto, !appState.paste.hasAccessibility { appState.paste.requestAccessibility() }
                }
                if settings.pasteBehavior == .auto {
                    Toggle("Show permission status in menu bar", isOn: $settings.showPermissionStatusInMenuBar)
                    if !appState.paste.hasAccessibility {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Color.warning)
                            Text("Accessibility not granted — auto-paste falls back to manual ⌘V.")
                                .font(Theme.Font.caption)
                            Button("Grant…") { appState.paste.requestAccessibility() }
                        }
                    }
                }
            }
            */
        }
        .formStyle(.grouped)
    }

    @State private var confirmClear = false
    @State private var customMode = false

    private static let presets = [50, 200, 500]

    private var showCustom: Bool {
        customMode || (settings.maxHistoryCount != .max && !Self.presets.contains(settings.maxHistoryCount))
    }

    private var limitBinding: Binding<Int> {
        Binding(
            get: {
                if showCustom { return -1 }
                return settings.maxHistoryCount
            },
            set: { v in
                if v == -1 { customMode = true }
                else { customMode = false; settings.maxHistoryCount = v }
            }
        )
    }
}

// MARK: - Excluded Apps

private struct ExcludedAppsSettings: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Clipboard content copied in these apps will not be recorded.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
            List {
                ForEach(settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        if let icon = AppIconProvider.icon(for: id) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(appName(id)).foregroundStyle(Theme.Color.text)
                        Spacer()
                        Button { settings.excludedBundleIDs.removeAll { $0 == id } } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.plain)
                    }
                }
                if settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps").foregroundStyle(Theme.Color.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Add App…") { addApp() }
            }
        }
        .padding()
    }

    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
           !settings.excludedBundleIDs.contains(id) {
            settings.excludedBundleIDs.append(id)
        }
    }
}

#if DEBUG
// MARK: - Debug（仅 Debug 编译，用 verbatim 文案避免污染字符串目录）

private struct DebugSettings: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var seedCount = 200

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.debugIsMember) { Text(verbatim: "会员 (Pro)") }
                Text(verbatim: "开=当前按 Pro 处理，关=按免费处理。Debug 下会员态完全以此开关为准（忽略真实试用/购买），正式包不受影响。")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
            } header: { Text(verbatim: "Membership") }

            Section {
                Button { appState.debugSimulateFirstLaunch() } label: {
                    Text(verbatim: "Simulate First Launch")
                }
                Text(verbatim: "重置首启标记，立即弹欢迎窗；关闭后会自动弹出剪贴板浮层（和真·首启一致）。")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
            } header: { Text(verbatim: "Onboarding") }

            Section {
                Stepper(value: $seedCount, in: 50...1000, step: 50) {
                    Text(verbatim: "Seed \(seedCount) sample clips")
                }
                Button { appState.debugSeedSampleClips(seedCount) } label: {
                    Text(verbatim: "Add Sample Clips")
                }
                Text(verbatim: "灌入示例条目以复现大列表 / 验证分批渲染。注意会受「最多条数」上限裁剪，测很多条时先把上限调高。")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondary)
            } header: { Text(verbatim: "Sample Data") }
        }
        .formStyle(.grouped)
    }
}
#endif

// MARK: - About

private struct AboutSettings: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            Text("Clipa").font(.system(size: 22, weight: .semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))").foregroundStyle(Theme.Color.secondary)
            // 公益发布版不展示会员/购买入口；商业版保留原有状态展示。
            if AppSettings.commercialFeaturesEnabled {
                if settings.isPro {
                    if TrialManager.shared.isActive && !settings.isProUnlocked {
                        Label("Free trial · \(TrialManager.shared.daysRemaining) days left", systemImage: "gift.fill")
                            .foregroundStyle(ClipaColor.accent)
                        Button("Unlock Pro") { appState.openPaywall() }.buttonStyle(.borderedProminent)
                    } else {
                        Label("Pro unlocked", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.Color.success)
                    }
                } else {
                    Button("Unlock Pro") { appState.openPaywall() }.buttonStyle(.borderedProminent)
                }
            }
            Divider().frame(maxWidth: 220)

            HStack(spacing: Theme.Space.md) {
                Button {
                    ReviewManager.openWriteReview()
                } label: {
                    Label("Rate Clipa", systemImage: "star")
                }
                Button {
                    ReviewManager.sendFeedback()
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }
            }

            HStack(spacing: Theme.Space.md) {
                Link("Privacy Policy", destination: Links.privacy)
                Link("Terms", destination: Links.terms)
            }.font(Theme.Font.caption)
        }
        .padding()
    }
}
