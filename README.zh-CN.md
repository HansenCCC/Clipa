<p align="center">
  <img src="docs/assets/icon.png" width="112" alt="Clipa 应用图标">
</p>

<h1 align="center">Clipa</h1>

<p align="center">
  <strong>复制过的内容，一个快捷键就能找回。</strong><br>
  为 macOS 打造的原生剪贴板管理器，也装下一些顺手的小工具。
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6785361561?mt=12"><img src="https://img.shields.io/badge/Mac_App_Store-免费下载-111827?style=for-the-badge&logo=apple&logoColor=white" alt="在 Mac App Store 下载"></a>
</p>

<p align="center">
  macOS 14+ · 原生 Swift · MIT<br><br>
  <a href="README.md">English</a> · 简体中文
</p>

![使用演示内容渲染的 Clipa 剪贴板卡片](docs/screenshots/clipboard-light.png)

按 **⌘⇧V** 唤出剪贴板历史，搜索并选中需要的内容，再到目标 App 按 **⌘V**
粘贴。剪贴板历史保存在你的 Mac 上，当前 Release 版本免费开放全部功能。

## 功能

| 剪贴板与整理 | 日常小工具 |
| --- | --- |
| 文本、富文本、链接、代码、图片和文件历史 | 屏幕取色 |
| 快捷键唤出、即时搜索、键盘操作 | 截图 |
| 置顶、永久集合和片段编辑 | 文件压缩与支持格式的解压 |
| 排除 App、保留期限和清空历史 | 菜单栏、开机启动与深浅色外观 |

<details>
<summary>查看深色外观</summary>

![Clipa 深色外观，内容均为演示数据](docs/screenshots/clipboard-dark.png)

</details>

## 下载与运行

普通用户可以直接[从 Mac App Store 下载 Clipa](https://apps.apple.com/app/id6785361561?mt=12)，
不需要安装 Xcode。Mac App Store 是官方分发渠道。

开发者可以独立克隆并构建本仓库，不需要私有后端或维护者的签名证书。

需要 **Xcode 26 或更新版本**及其命令行工具；应用最低支持 **macOS 14**。
Swift Package Manager 根据仓库中的 `Package.resolved` 获取依赖。

```sh
git clone https://github.com/HansenCCC/Clipa.git
cd Clipa
xcodebuild -project Clipa.xcodeproj -scheme Clipa \
  -configuration Release -derivedDataPath build \
  -disableAutomaticPackageResolution build
open build/Build/Products/Release/Clipa.app
```

工程默认使用本地 ad-hoc 签名，不绑定开发者团队或分发证书，也可以直接用 Xcode
打开 `Clipa.xcodeproj` 运行。Release 为全功能免费行为；Debug 保留了历史 StoreKit
流程的开发开关。

只有新增或移除源码文件时才需要重新生成工程：先执行 `bundle install`，再执行
`bundle exec ruby gen_project.rb`。生成器会保留依赖锁定文件。

## 隐私

- 剪贴板内容通过 SwiftData 保存在本机，不会上传到云剪贴板服务。
- 自动跳过可识别的敏感剪贴板类型；这不能保证识别所有秘密，请结合 App 排除和清空功能使用。
- 源码构建默认关闭启动统计。分发者可通过 `CLIPA_STARTUP_STATS_URL` 明确配置启用；
  该请求包含平台、应用版本和构建号，不包含剪贴板内容。
- 打开网页、App Store 操作以及明确配置的统计请求可能联网。商店分发版本的说明见
  [隐私政策](https://chenghengsheng.top/app/6785361561/privacy.html)。

日常剪贴板流程使用手动粘贴，不申请辅助功能权限。使用截图等系统功能时，macOS
可能提示授予相应权限。

## 参与开发

技术栈为 SwiftUI、AppKit、SwiftData 和 StoreKit 2。欢迎修复、翻译和文档改进。

```sh
zsh tests/run_clipboard_monitor_harness.sh
zsh tests/run_panel_controller_harness.sh
```

提交前请阅读[贡献说明](CONTRIBUTING.md)。Issue、日志和截图中请使用演示数据，
不要公开真实剪贴板数据库、密码或私人文件。安全问题见 [SECURITY.md](SECURITY.md)。
上面的图片由 Clipa 原生卡片视图和演示数据渲染，不包含真实用户的剪贴板历史。

## 许可证与致谢

Clipa 自有代码采用 [MIT 协议](LICENSE)。第三方依赖继续适用各自条款，包括底层
UnRAR 的单独许可；完整说明见[第三方声明](THIRD_PARTY_NOTICES.md)。

作者：[Hansen](https://github.com/HansenCCC)。
