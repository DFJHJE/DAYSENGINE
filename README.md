# DaysEngine for iOS — 原生外壳工程

把已经在 Safari 上验证过的网页版启动器（`web/daysengine-web.html`）装进一个原生 iOS App，
产出可侧载的 `.ipa`。

## ⚠️ 先读这一节：验证状态

**这份 Swift 代码我一行都没有编译过，也没有在真机跑过。**

原因：编译 iOS 二进制需要 Apple 的 `swiftc`/`clang`/`ld`/`codesign`，而 Apple 只在 macOS 上
提供这些工具。本机是 Windows，实测确认不存在：

```
swiftc / clang / ld / lipo / codesign / xcrun / xcodebuild   全部不存在
iPhoneOS*.sdk                                                未找到
.ipa / .mobileprovision / .p12                               未找到
```

所以我**无法**声称它能编译。我能做到的验证只有这些，我也确实做了：

| 验证项 | 手段 | 结果 |
| --- | --- | --- |
| Swift 词法结构 | `tools/check-swift.ps1`（自己写的分词器） | ✅ 5 文件 / 397 行，217 对分隔符全平衡，无未闭合字符串 |
| 抓到错误 1 | 同上 | ✅ `WebBridge.swift` 用了 `UIApplication.shared` 但漏了 `import UIKit`，已修 |
| 抓到错误 2 | 人工复查 Info.plist | ✅ `UIRequiredDeviceCapabilities` 原本写了 `armv7`（32 位！），会让 App 在 arm64 设备上**装不上**，已改为 `arm64` |
| 图标资产 | System.Drawing 直接绘制 + 像素校验 | ✅ 8 个 PNG，manifest 与磁盘文件一一对应、无重复 |
| Info.plist / 所有 JSON | XML、JSON 解析器 | ✅ 全部合法 |
| 网页版内核正确性 | 浏览器里与 C# 真值逐字段比对 | ✅ 147/147 项通过（989 个事件 × 10 字段） |
| 网页版功能链路 | 无头 Edge 驱动真实引擎 | ✅ 11/12（唯一失败项已确证是无头环境限制） |
| IPA 结构完整性 | CI 里 `unzip -l` 断言可执行文件与 `www/index.html` 存在 | ⏳ 首次跑 CI 才知道 |
| **Swift 能否编译** | — | ❌ **未验证，只有 Xcode 能验** |
| **真机能否运行 / 有没有声音** | — | ❌ **未验证** |

词法检查通过**不等于能编译**。Swift 的类型检查、协议一致性、重载解析都需要真正的编译器。
第一次跑 CI 或第一次用 Xcode 打开时出现编译错误，是**预期之内**的，请把错误贴给我。

---

## 1. 它是什么

```
DaysEngine.app
├── DaysEngine                  原生外壳（SwiftUI + WKWebView）
├── Info.plist                  文件共享、方向、状态栏
├── Assets.xcassets/AppIcon     从 SVG 渲染的 11 个尺寸图标
├── www/index.html              ← 与 Safari 版完全同一份启动器
└── Documents/                  你把 .GPK 和密钥放进这里
```

外壳只做四件事，**启动器逻辑 100% 还是那份 HTML**（所以 Safari 版验证过的解析器、
音频链路、界面都在这里原样复用，不存在两份实现）：
1. `WKWebView` 加载 `www/index.html`
2. 配置 `AVAudioSession`（`.playback`，静音键拨到静音也能出声）
3. 放开"必须用户手势才能播放"的限制（`mediaTypesRequiringUserActionForPlayback = []`）
4. 把读权限授予 `Documents`，让页面自己的文件选择器能读到你的 `.GPK`

---

## 2. 怎么拿到 IPA

### 路线 A：GitHub Actions（推荐，你只有 Windows 也能走完）

1. 把 `G:\DaysLauncher` 作为一个 GitHub 仓库推上去（`ios/`、`web/`、`.github/` 都要在里面）
2. 仓库 → **Actions** → 左侧 **Build unsigned IPA** → **Run workflow**
3. 等约 5–10 分钟，在 **Artifacts** 下载 `DaysEngine-unsigned-ipa`
4. 解压得到 `DaysEngine-unsigned.ipa`

CI 跑在 GitHub 免费的 `macos-15` runner 上——**这就是绕开"Windows 不能编译 iOS"的唯一办法**。

它做了这些事：重建网页版启动器并复制进 `ios/www`、跑 Swift 词法检查、`xcodegen` 生成工程、
`xcodebuild` 以 `CODE_SIGNING_ALLOWED=NO` 编译、校验 IPA 结构、上传产物。

### 路线 B：借一台 Mac

```bash
brew install xcodegen
cd ios && ./build-ipa.sh
```

产出 `ios/dist/DaysEngine-unsigned.ipa`。

---

## 3. 怎么装到 iPhone / iPad

**关键事实：未签名的 IPA，iOS 拒绝安装。** 这不是配置问题，是 iOS 的安全模型。
安装必须有 Apple 签名的身份，而这一步只能由**你的 Apple 账号**参与——我无法代做。

### 用 Sideloadly（Windows 上就能做）

1. 装 [Sideloadly](https://sideloadly.io/) 和 [iTunes](https://www.apple.com/itunes/)（提供驱动）
2. 数据线连接 iPad，Sideloadly 里选那个 `.ipa`
3. **Apple ID 填你自己的**（普通免费账号即可）
4. 点 Start，输入 Apple ID 密码（用于生成签名证书，凭据只发给 Apple）
5. iPad 上：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
6. 打开 App

### 用 AltStore / SideStore

类似流程，AltStore 可以在设备上自动续签，更适合长期使用。

### 必须知道的限制

| 限制 | 说明 |
| --- | --- |
| **7 天过期** | 免费 Apple ID 签的 App **7 天后失效**，要重新签一次（AltStore 可自动续） |
| 需开发者账号才能 1 年 | 有 $99/年 的开发者账号则签 1 年 |
| 换 Apple ID 会丢数据 | App 的 Documents 会随之清空，先导出 `.GPK` |
| 上架 App Store 不可能 | 审核条款 1.1.4 明确拒绝成人内容，只能侧载 |

---

## 4. 首次运行怎么用

**推荐做法**（App 的 Documents 就是沙箱，文件从这里读最省事）：

1. 电脑上跑 `DaysLauncher.exe --gpkkey "游戏目录"` 生成 `daysengine-key.json`
2. iPad：**文件 App → 我的 iPhone/iPad → DaysEngine**，把 `daysengine-key.json` 和
   `BGM.GPK`、`SysSe.GPK` 拖进去
3. 打开 App → 「设置」→ 选密钥文件 → 回「游戏库」选 `.GPK`
4. 点一次屏幕（解锁音频）→ 有声音

放进 `Documents` 之外的位置也行，App 内选文件时会调系统选择器，能选到 iCloud Drive 里的文件。

> **不要放 `Movie0x.GPK`**（单支 1.7–2.7 GB，iOS 内存回收会把 App 杀掉）。
> 网页版内核会主动跳过 >320 MB 的文件并给出提示。

---

## 5. 已知问题与不确定项

因为无法验证，我把我**知道有风险的地方**列出来，而不是等你踩：

| 项目 | 风险 | 说明 |
| --- | --- | --- |
| `import UIKit` 缺失 | ✅ 已修 | 词法检查抓到，已补 |
| `armv7` 设备能力声明 | ✅ 已修 | 原本会让 App 在 64 位设备上不可安装，已改为 `arm64` |
| `onChange(of:perform:)` | ⚠️ 会有弃用警告 | iOS 17 弃用了单参数版本，两参数版本要 iOS 17+。此处保留单参数以支持 iOS 15，**只警告不报错** |
| `UIApplication.shared.windows` | ⚠️ 弃用警告 | 代码里 newer API 优先，旧 API 只作回退 |
| 工具栏可能不显示 | ⚠️ 中等 | `.toolbar` 在 `NavigationView` 内应立即生效；若真机上没看到，改 `NavigationStack`（需把部署目标提到 iOS 16） |
| 分享面板 | ⚠️ 中等 | 用 `UIActivityViewController` + `popoverPresentationController`，iPad 上必须有 anchor，已配置 |
| 网页里 `<input type="file" webkitdirectory>` | ⚠️ 低 | iOS 不支持目录选择；界面已把该按钮标注为"桌面浏览器"，并提供"选择 .GPK 文件" |
| 图标资产目录 | ✅ 已核 | iOS 17+ 读 1024 单尺寸条目；其余 7 个填经典槽位，manifest 与磁盘已校验一致 |
| 编译错误 | ⚠️ **预期会有** | 首次 CI 结果为准，请把错误贴给我 |

### 图标生成的实现说明

第一版用无头 Edge 渲染 SVG 转 PNG，实测**不可靠**：`--screenshot` 在一批渲染中途反复挂起
（进程堆到 22 个、输出停在 5/8）。已改为 `System.Drawing` 直接绘制，**确定性、秒级完成**，
不再依赖任何外部进程。若你要改图标，改 `tools/make-icon.ps1` 里的坐标即可。

---

## 6. 文件说明

```
.github/workflows/ios-ipa.yml    GitHub Actions：在 macOS runner 上出未签名 IPA
ios/
  project.yml                    XcodeGen 工程描述（不手写 .pbxproj，避免手写损坏）
  build-ipa.sh                   Mac 上一键构建（xcodegen + xcodebuild + 打包）
  DaysEngine/
    DaysEngineApp.swift          入口，配置 AudioSession
    ContentView.swift            外壳 UI：工具栏 + 错误横幅
    WebView.swift                WKWebView 封装（音频、读权限、导航策略、JS 对话框）
    WebBridge.swift              外壳与网页的共享状态、分享面板
    AudioSessionController.swift 音频会话（.playback，静音键不影响）
    Info.plist                   文件共享 / 方向 / 状态栏
    Assets.xcassets/AppIcon      11 个尺寸图标
  www/index.html                 与 Safari 版同一份启动器（构建时同步）
  tools/
    make-icon.ps1                从 SVG 用 Edge 渲染图标
    check-swift.ps1              Swift 词法检查器（分隔符/字符串/注释平衡）
```

## 7. 为什么工程里没有 `.xcodeproj`

`project.pbxproj` 是个 UUID 满天飞的大文件，手写极易损坏，而**我在 Windows 上无法用 Xcode
验证它是否有效**。XcodeGen 从 30 行的 `project.yml` 生成它，Mac 上和 CI 上都能生成——
把"我猜的 UUID"换成"机器生成的正确文件"。

## 8. 许可与署名

- 形态参照官方「DaysEngine for Android」发布说明；数据格式依据 superboo07/DaysEngine（MIT）。
- 音频使用系统 Web Audio 解码，不捆绑 FFmpeg。
- **不附带、不分发任何游戏本体、影片、音乐或语音资源。**
- *School Days* / *Shiny Days* / *Cross Days* 为各自权利人商标，本项目与其无关。
