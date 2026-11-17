# 小账本 CostBook

一个用 SwiftUI 写的本地记账 App，数据只存在手机里。

## 功能

- 记支出 / 收入，一级分类 + 二级分类，可增删分类
- 按月查看，每日支出柱状图，点柱子只看那一天
- 本月结余 / 收入 / 支出 / 预算剩余
- 统计页：按分类排行 + 占比
- 每月总预算 + 分类预算
- CSV 导出（Excel / Numbers 可直接打开）
- Face ID / 密码锁

## 怎么编出 IPA

这个工程没有 `.xcodeproj`，用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成。

### 路线 A：有 Mac

```bash
brew install xcodegen
cd CostBook
xcodegen generate
open CostBook.xcodeproj
```

在 Xcode 里：

1. 选中 CostBook target → Signing & Capabilities
2. Team 选你的账号，Bundle Identifier 改成你自己的（例如 `com.你的名字.costbook`）
3. 真机连上，Cmd+R 直接跑

要出 IPA：Product → Archive → Distribute App → Ad Hoc / Development。

### 路线 B：没有 Mac（GitHub Actions）

1. 新建一个 GitHub 仓库（可以是 private）
2. 把整个 `CostBook` 目录里的文件推到仓库根目录，`.github/workflows/build.yml` 会一起上去
3. 打开仓库的 Actions 页面 → **Build unsigned IPA** → Run workflow
4. 等 3～5 分钟，`macos-15` runner 会编译出 `CostBook-unsigned.ipa`
5. 在 Actions 运行结果页底部下载 artifact，解压得到 IPA
6. 用自己的签名工具签名后安装

**注意**：仓库根目录必须直接是 `project.yml`、`CostBook/`、`.github/` 这三项，不要多套一层文件夹，否则 `xcodegen` 找不到配置。macOS 上推空目录会丢 `.github`，所以在 Mac 上用 Finder 拖文件时，记得确认 `.github` 也被提交上去了。

### 如果没有 iOS 26 SDK

`project.yml` 里 `deploymentTarget` 默认是 17.0，代码只用了 iOS 17 API，不需要改。如果你的 Xcode 更老（低于 15），把它改成 16.0，同时把 `.onChange(of:) { _, _ in }` 改成 `.onChange(of:) { _ in }`。

## 签名说明

GitHub Actions 产出的是**未签名** IPA，直接装会失败。你需要：

- 企业证书 / 开发者证书 + 描述文件，用 `codesign` 或签名工具签
- 或者用 AltStore、Sideloadly 这类工具，登录 Apple ID 自签（7 天有效）

仓库里没有放任何证书，这是有意的 —— 证书永远不要进 Git。

## 目录

```
project.yml              XcodeGen 配置（Bundle ID、版本、权限说明）
CostBook/
  CostBookApp.swift      入口
  Info.plist
  Assets.xcassets/       App 图标
  Models/
    Store.swift          数据模型 + 本地存储 + 分类/预算逻辑
    Helpers.swift        金额格式化、日期、CSV 导出
  Views/
    RootView.swift       导航 + 锁屏
    ContentView.swift    首页：汇总、柱状图、明细
    EntryEditor.swift    记账 / 编辑
    StatsView.swift      统计 + 设置
  Support/
    Lock.swift           Face ID 锁
.github/workflows/build.yml
make_icon.py             重新生成图标
```

## 数据

存在 App 沙盒的 `Application Support/costbook.json`。卸载 App 会一起删掉，请定期用 CSV 导出备份。
