# 简体中文版：发布与维护手册

适用仓库：`https://github.com/chloxen95/Compositor-ZH`（fork 自 `robbietilton/Compositor`）

---

## 一、分支与远端的约定

| 名称 | 作用 | 是否提交汉化代码 |
|---|---|---|
| `upstream` | 上游 `robbietilton/Compositor`，只读 | — |
| `origin` | 你的 fork `chloxen95/Compositor-ZH` | — |
| `main` | 上游的纯净镜像，只做 `git pull upstream main` | **否** |
| `hans` | 汉化分支，所有工作在这里 | 是 |
| `update-feed` | 只放 `appcast.xml`（自动更新源） | 否（只有 feed） |

`update-feed` 必须独立，因为上游每次发版都会改写它 `main` 上的 `appcast.xml`；
放在 `hans` 里会导致每次合并上游都冲突。

---

## 二、一次性设置（顺序不能颠倒）

### 1. 推送两个分支

```bash
cd "/Users/chenhanlin/WorkBuddy/Compositor 汉化/Compositor"
git push -u origin hans
git push origin update-feed
```

> **先推 `update-feed`，再运行编译出来的 App。**
> 应用启动时会去读这个地址，未推送时是 404，Sparkle 会在日志里报错（不会弹窗、不会装错东西，
> 但配置不算就绪）。

### 2. 准备 Sparkle 命令行工具

```bash
./scripts/l10n/feed.sh tools
```

下载 Sparkle 2.10.0 官方发行包里的 `generate_keys` / `sign_update` / `generate_appcast`，
解压到 `~/Library/Caches/CompositorZH/Sparkle-tools/bin`。发行包带 SHA-256 校验，
版本与 `Package.resolved` 锁定的 revision（2.10.0）一致；包被换掉会直接失败，不会静默使用。

> 这些工具在 SPM 解析后的 artifact bundle 里也有，但那要求先构建成功一次，
> 而且会随 DerivedData 被清掉。独立下载更稳，也不依赖 Xcode 是否装好。

### 3. 生成我们自己的更新签名密钥

```bash
./scripts/l10n/feed.sh key
```

幂等：钥匙串里已有密钥就复用，不覆盖。它做四件事：

1. 生成 Ed25519 密钥对，私钥存进登录钥匙串（服务 `https://sparkle-project.org`，账户 `ed25519`）；
2. 把公钥写进 `Config/Info.plist` 的 `SUPublicEDKey`——**只改这一行**，注释与键序原样保留。
   （不用 `plutil -replace`：它按字母序重排整个文件并丢掉 XML 注释，那样每次合并上游都要多解一次冲突。）
3. 导出私钥到 `~/Library/Application Support/CompositorZH/signing/ed25519-private-key.txt`（600 权限）；
4. 真签一个测试文件，再用 CryptoKit 独立验签，确认私钥与公钥确实配对。

**为什么必须换掉**：留着上游的公钥，我们既签不出自己的更新，又等于给上游的英文包开了后门。

**私钥必须另存一份离线备份**。丢了就再也签不出能通过校验的更新包，已装旧版的用户只能手动重装。
备份目录特意放在 `Application Support` 而不是 `Documents`：后者默认同步 iCloud，私钥不该进任何云端。

> `SUEnableAutomaticChecks` 沿用上游的 `<true/>`，无需改动。

### 4. 单独验证密钥（可选，`key` 已自动执行）

```bash
PUB=$(plutil -extract SUPublicEDKey raw Config/Info.plist)
printf 'selftest\n' > /tmp/selftest.bin
SIG=$("$HOME/Library/Caches/CompositorZH/Sparkle-tools/bin/sign_update" /tmp/selftest.bin \
      | sed -E 's/.*edSignature="([^"]+)".*/\1/')
xcrun swift scripts/l10n/verify-ed25519.swift "$PUB" /tmp/selftest.bin "$SIG"
```

输出「✅ 验签通过」表示钥匙串私钥与 plist 公钥是同一对。

用 CryptoKit 而不是 Sparkle 自己的代码，是因为**用签名工具去验自己的签名等于没验**。
公钥配错在用户端的表现不是报错，而是静默装不上，所以必须用独立实现证一次。

### 5. 验证配置自洽

```bash
./scripts/l10n/feed.sh check
```

全部通过时应显示「结论：配置自洽」。

---

## 三、日常：编译自用

```bash
./scripts/l10n/build-zh.sh            # 首次汉化版，build = 上游 ×10 + 1
ZH_REV=2 ./scripts/l10n/build-zh.sh   # 同一上游基线上再发一版
```

产物在 `~/Library/Caches/CompositorZH/Build/Products/Release/Compositor.app`。
本机自用无需证书，脚本会打印 `open` 命令。

版本号采用「上游 build × 10 + 汉化修订号」：上游 58 的第 1 个汉化版是 581。
这样既单调递增，又能一眼看出基于哪个上游版本。**版本号由命令行注入，不写进工程文件**，
避免与上游每次发版对同一行产生冲突。

---

## 四、发布：让用户能自动更新

### 1. 打包成 DMG

需要 Developer ID 证书与公证（否则别人下载会被 Gatekeeper 拦）。
上游的 `scripts/release.sh` 里写死了他自己的 Team ID（`3E4X3B9Z9T`），
用之前必须改成你的，或复制一份改成 `scripts/l10n/release-zh.sh`。

### 2. 上传 DMG

传到 GitHub Releases，例如 tag `zh-581`，文件命名保持 `Compositor.dmg`。
没有 `gh` 命令行时可以在网页上手动拖拽上传。

### 3. 写进更新源

```bash
./scripts/l10n/feed.sh publish \
  dist/Compositor-1.5.12.dmg \
  https://github.com/chloxen95/Compositor-ZH/releases/download/zh-581/Compositor.dmg \
  581 1.5.12 \
  "首个简体中文版" "图层、蒙版、Camera Raw 面板已汉化"

git push origin update-feed
```

脚本会调用 Sparkle 的 `sign_update` 生成签名与长度，写入 `update-feed` 分支。

---

## 五、跟随上游

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main
git checkout hans && git merge main          # 有冲突就解，解完跑下面几条
python3 scripts/l10n/wirecheck.py --against main  # 上游有没有动 rawValue？动了才 --update
./scripts/l10n/typecheck.sh --typecheck      # 类型层；不加参数是语法层，更快
python3 scripts/l10n/harvest.py              # 重新采集 key：看新增/孤儿
python3 scripts/l10n/apply.py --init         # 把新 key 加进 TM，标 new
python3 scripts/l10n/lint.py                 # 缺译会被 E1 拦住，逐条补
python3 scripts/l10n/make_catalog.py         # 再生成 catalog，构建才会变中文
```

- 只用 **merge**，不用 rebase：rebase 要反复解同一批冲突。
- 合并后 `harvest.py` 会报新增/孤儿。孤儿不要删，是上游改了英文句子，
  用旧译文做模糊匹配比重新翻便宜（`apply.py --init` 会保留有译文的孤儿，标 `orphan`）。
- 每次合并打 tag（如 `upstream-1.5.13`），便于定位。

---

## 六、翻译：改了文字怎么落进 App

四步，顺序不能颠倒。**人只碰 `l10n/translations.csv`，其余都是生成物。**

```bash
python3 scripts/l10n/harvest.py                 # ① 问 Xcode：有哪些 key
python3 scripts/l10n/apply.py batch.json        # ② 译文写进 TM（人工/批量都走这里）
python3 scripts/l10n/make_catalog.py            # ③ TM → Localizable.xcstrings
./scripts/l10n/lint.py                          # ④ 闸门
```

| 文件 | 谁写 | 说明 |
|---|---|---|
| `l10n/source-keys.json` | `harvest.py` | 权威键表，含每个 key 的源码位置 |
| `l10n/translations.csv` | **人** | 翻译记忆库，唯一的译文来源 |
| `Compositor/Localizable.xcstrings` | `make_catalog.py` | 构建产物，**不要手改** |
| `Compositor/InfoPlist.xcstrings` | `make_catalog.py` | Finder 的「种类」列（Compositor 项目 / Adobe Photoshop 文档） |
| `l10n/keys.json` | `extract.py` | **旧的手写扫描器结果，只作盲区报告用，不是键源**。别拿它建 catalog |
| `l10n/wire-format.json` | `wirecheck.py` | 工程文件格式的指纹（60 个枚举 / 301 个取值 / 42 个 Codable 结构）。rawValue 是文件格式，改一个字符旧工程就读不了 |

### 为什么键要从 Xcode 拿，而不是自己扫源码

自己写的扫描器够用来估规模、找盲区，但它不是编译器：

- 带嵌套字符串字面量的插值 `\(cond ? "a" : "b")` 会被提前截断；
- 多参数插值在运行时是 **带位置的格式符**（`%1$lld × %2$lld px`），扫描器只能
  给出 `\(Int(w)) × \(Int(h)) px`，拿这种 key 去建 catalog 永远匹配不上；
- AppKit 的 `NSMenuItem(title:)` 之类不会出现在编译器结果里——这些正是「盲区」，
  必须先在代码里收口（改成 `String(localized:)`），而不是靠 catalog 硬塞。

`harvest.py` 走的是 `xcodebuild -exportLocalizations`：它用编译器吐出的
`.stringsdata` 合成 xliff，这一份就是 App 运行时真正会去查的 key 集合。

### `status` 三态

| 值 | 含义 | 进 catalog 吗 |
|---|---|---|
| `new` | 还没有译文 | 不进（运行时回落英文，不会出现空白） |
| `translated` | 已译 | 进 |
| `verbatim` | 专名，保持原文（Compositor、CMYK、`%lld%%`） | 进，写成 `shouldTranslate: false` |

`verbatim` 不是偷懒：它让 Xcode 与译者在界面上都看到「这条是刻意不翻的」，
比写一条和原文一模一样的译文准确。

### 闸门会拦什么

`lint.py` 现在对 770 条键是 0 ERROR / 0 WARN。它拦的是：

- **E1 覆盖率**：有 key 没译文（上游加了新句子时必然触发）；
- **E2 占位符**：`%@`、`%lld`、`%1$lld` 的数量或位置对不上——这条最要命，
  少一个 `%lld` 在运行时会直接崩，不是显示错乱；
- **E3 术语**：整条 key 就是术语表里的词（`Cancel` 必须「取消」）。术语表含
  `terms` 与 `blendModes` 两张表——后者是 Photoshop 简中的 24 个混合模式，之前没人
  校验它，现在混合模式直接显示在界面上，所以一并纳入；
  一词多义在 `glossary.termOverrides` 里登记，例如 `Type` 在画笔面板是「类型」，
  在工具栏才是「文字」；
- **E5 省略号**：原文以 `…` 结尾，译文也必须以 `…` 结尾；
- **E6 不译名**：`PNG`/`Camera Raw`/`sRGB` 等不许译丢；
- **E7 状态**：标了 `translated` 却和原文一模一样。

`E4 禁用译法` 分两档：`hard`（蒙板、撤销操作这类任何语境都错）直接 ERROR；
`soft`（透明度、设置这类看语境）只 WARN。确认无误的写进 `glossary.reviewed`
并附理由——**裁定要留痕**，否则下次谁改回去也没人知道。

### 应用内切换语言

App 菜单 › **语言** › 跟随系统 / English / 简体中文。选完菜单里出现
**重新启动 Compositor**，点它才重启。

不自动重启是有意的：可能还有没存的项目，替用户决定重启等于替他丢工作。

实现（`Compositor/App/LanguagePreference.swift`）的三条要点：

1. **写 `AppleLanguages`**。CFBundle 在进程启动时按它解析 `.lproj`，所以改动
   必然下次启动生效；热切换要重建整棵视图树并让已取到的字符串失效，Apple 自己
   也不这么做。
2. **「跟随系统」= 删键**，不是写 `["en"]`。写死英文会让用户在系统切到中文后
   仍然是英文——这是这类实现最常见的错。
3. **逻辑与界面分离**，所以能脱离 App 断言：

   ```bash
   ./scripts/l10n/selftest-language.sh    # 18 项断言，不需要 Xcode 测试宿主
   ```

> App 是**沙盒**的（`com.apple.security.app-sandbox`），偏好落在
> `~/Library/Containers/com.wonderassembly.compositor/`。
> 因此**从外部** `defaults write ... AppleLanguages` 会被沙盒挡下，
> 语言只能用菜单改——这也顺带说明为什么这条必须做进 App 里。

---

## 七、故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `feed.sh check` 报「取不到」 | `update-feed` 还没推送，或仓库不是公开的 | `git push origin update-feed` |
| 报「不是我们的公告（标题不是 …）」 | 分支名撞上了提交 SHA 前缀 | 见下节；改回 `update-feed` |
| 找不到 `generate_keys` / `sign_update` | 工具还没下载 | `./scripts/l10n/feed.sh tools`（需联网，可能要 VPN） |
| `feed.sh key` 报「验签自检失败」 | 钥匙串私钥与 plist 公钥不配对 | 重跑 `feed.sh key`；仍失败则删掉钥匙串里 `ed25519` 条目后重新生成 |
| 应用提示更新但安装失败 | `SUPublicEDKey` 还是上游的公钥 | `./scripts/l10n/feed.sh key` 后重新构建 |
| 更新装完变回英文 | `SUFeedURL` 指到了上游 | `feed.sh check` 核对 |
| 合并上游时 `appcast.xml` 冲突 | feed 被放进了 `hans` | 把该文件移回 `update-feed` 分支 |
| `xcodebuild` 报「a required plug-in failed to load」 | Xcode 首启动组件没装（缺 CoreSimulator） | `sudo xcodebuild -runFirstLaunch`，需管理员密码 |

### 分支名为什么不能叫 `feed`

`raw.githubusercontent.com/{owner}/{repo}/{段}/{路径}` 的第三段**既可以是分支名，
也可以是提交 SHA 的前缀**。`feed` 全由十六进制字符组成，恰好匹配 2026-09-21 的提交
`feedc263fc…`，于是 `/feed/appcast.xml` 会静默返回那份旧公告（Version 1.1.8、build 14、
指向上游的 DMG）。

危害不在于那份公告本身（build 14 低于我们的 58，不会触发安装），而在于**应用会去读一份我们
不控制的文件**。哪天命中一个版本号更高的旧公告，就会把上游的英文包装进来。

凡是只由 `0-9a-f` 组成的名字都有这个问题：`feed`、`dead`、`beef`、`cafe`、`face`、`decade`。
`update-feed` 含 `u`、`p`、`t`、`-`，不可能与 SHA 前缀混淆。
`feed.sh check` 会核对频道标题必须是 `Compositor 简体中文`，专门用来抓这类劫持。

---

## 八、本机构建

```bash
./scripts/l10n/build-zh.sh          # Release 构建，产物在 ~/Library/Caches/CompositorZH/Build/Products/Release/
ZH_REV=2 ./scripts/l10n/build-zh.sh # 同一上游基线上再出一版
```

脚本做四件事：读上游的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`、把 build 号注入成
`上游 × 10 + 汉化修订`、构建、再回头核对产物 `Info.plist` 里的版本与更新源。

清产物用的是 `xcodebuild clean`，**不是 `rm -rf` 派生数据目录**：后者会连带删掉
`SourcePackages`，于是每次构建都要重新联网 clone Sparkle；而且一次删两千多个文件，
在受限环境里会触发文件安全策略把整条命令拦下（本机就是这样）。

所有开关都从命令行注入，**不写进 `project.pbxproj`**，因为上游每次发版都会改那里，写进去就每次都冲突。

### 两处环境适配（脚本自动判定）

| 现象 | 原因 | 脚本的动作 |
|---|---|---|
| 构建报 `sandbox-exec: sandbox_apply: Operation not permitted`，或 `swift-plugin-server produced malformed response` | Xcode 用 `sandbox-exec` 跑包清单解析和宏插件服务；受限会话里内核拒绝 `sandbox_apply`。后者尤其误导，看着像宏坏了 | 先探测 `sandbox-exec` 能否工作，不能才关这两处沙箱 |
| 构建报 `No signing certificate "Mac Development" found` | 工程写死了上游的证书与 team id | 改 ad-hoc 签名（`-`），并**同时关掉加固运行时**，否则库校验会拒绝加载内嵌的 Sparkle.framework，App 一启动就崩 |

要分发时（需要开发者账号）：

```bash
ZH_SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" ./scripts/l10n/build-zh.sh
```

此时不要关加固运行时——整包同一个 team，库校验自然通过；脚本也只在 ad-hoc 时才关。

### 单元测试在本会话跑不起来（已查清，非工程问题）

```bash
xcodebuild test -project Compositor.xcodeproj -scheme Compositor -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual OTHER_SWIFT_FLAGS="-disable-sandbox" \
  ENABLE_HARDENED_RUNTIME=NO
```

会失败于 `The test runner hung before establishing connection`（有时报 `exited with code 0`）。

已排除的可能：沙箱（用 `ENABLE_APP_SANDBOX=NO` 重建过）、加固运行时、调试器启动器
（另建过 PosixSpawn 的 scheme）、调试 dylib（`ENABLE_DEBUG_DYLIB=NO`）、首启动组件
（`-checkFirstLaunchStatus` 返回 0）、残留实例。

采样（`sample`）给出的证据是决定性的：宿主进程正常跑在 `NSApplication.run` 的事件循环里，
`sample` 输出里**没有任何 XCTest 镜像**——测试包根本没被注入，所以不是「连不上」，
是「没开始连」。注入靠 `DYLD_INSERT_LIBRARIES`，被当前受限会话的环境策略丢弃。

**替代方案**（已落地，不是设想）：

| 想验什么 | 用什么 | 需要 Xcode 测试宿主 |
|---|---|---|
| 语言偏好逻辑 | `./scripts/l10n/selftest-language.sh`（18 项断言） | 否 |
| 更新签名密钥配对 | `scripts/l10n/verify-ed25519.swift` | 否 |
| 翻译质量 | `./scripts/l10n/lint.py` | 否 |
| 工程文件格式没被改动 | `python3 scripts/l10n/wirecheck.py` | 否 |
| catalog 与 CSV 是否同步 | `python3 scripts/l10n/make_catalog.py --check` | 否 |
| 整模块类型 | `scripts/l10n/typecheck.sh --typecheck` | 否（只要 Xcode 的 SDK） |
| 界面行为回归（104 套件） | Xcode 图形界面按 ⌘U | 是 |

前五条都能在命令行跑，退出码即结论。第六条只能在 Xcode 图形界面里跑，
因为注入测试包要靠 `DYLD_INSERT_LIBRARIES`，而受限会话的环境策略会把它丢掉。

### 界面验证：截图 + 控件树（2026-10-31 起两项权限都有）

| 权限 | 能做什么 |
|---|---|
| 屏幕录制 | 按窗口截图、区域放大读字 |
| 辅助功能 | 读控件树、点按钮、点菜单项（`scripts/l10n/ax.swift`） |

```bash
./scripts/l10n/shot.swift list                       # 窗口 id
./scripts/l10n/shot.swift capture <id> win.png       # 按窗口抓，不受遮挡、原生 2x
./scripts/l10n/shot.swift crop win.png r.png x y w h  # 精确裁剪

./scripts/l10n/ax.swift menu <pid>                   # 菜单栏全量（含快捷键与禁用状态）
./scripts/l10n/ax.swift tree <pid> 12                # 控件树（角色 / 文字 / 无障碍标识符）
./scripts/l10n/ax.swift button <pid> "创建画布"      # 点按钮
./scripts/l10n/ax.swift press <pid> Compositor 语言 English   # 点菜单项（支持多级）
```

**不要用 System Events**：那需要「自动化」权限（与辅助功能是两项独立的 TCC），
没给会报 −10004，看着像辅助功能没生效，其实不是。直接用 AX API 不需要它。

四个坑：
1. `sips --cropOffset` 的偏移相对**居中**裁剪原点，坐标不可靠，要用 `CGImage.cropping`。
2. 窗口可能开在**屏幕外**（见过 x=−1752），`optionOnScreenOnly` 看不到 → 误判「没有窗口」。
3. `kAXWindowsAttribute` 偶尔为空，要退回扫 app 子元素。
4. SwiftUI 的 `NSPopUpButton` 弹出菜单是**独立窗口**（CGWindowList 里 layer=101），不进 AX 树：
   要读就截那个窗口，要选就发方向键 + 回车。

**语言切换的端到端验证**：`open --args -AppleLanguages "(en)"` 对沙盒 App **无效**
（对普通可执行文件有效），`defaults write` 也会被容器保护挡住。正路是用应用自己的菜单：
`./scripts/l10n/ax.swift press <pid> Compositor 语言 English`，重启后界面即为英文；
再 `press <pid> Compositor Language 简体中文` 切回。往返已实测通过。

### 一条必须记住的规则：`String` 形参 = verbatim

Xcode 只抽取两条路径上的文案：`LocalizedStringKey`（含 `Text("…")` 字面量）与
`String(localized:)`。凡是形参声明成 `String` 的入口，字面量传进去就**既不进翻译表、
也不会被任何闸门发现**，而且英文界面下看起来完全正常。

| 陷阱 | 例子 | 后果 |
|---|---|---|
| 形参 `String` | `dimension(_ title: String)` → `Text(title)` | 表里有「宽度」，界面仍显示 Width |
| `switch` 返回 `String` | `"\(rawValue.capitalized) canvas"` | 整句英文，且语序不可译 |
| **链里有一处 `+`** | `("Drag to paint") + " · [ ] size…"` | **整条三元表达式统一成 `String`，20 多句一起失效** |
| AppKit 赋值 | `alert.messageText = "…"`、`panel.title = "…"`、`toolTip = "…"` | 对话框、面板标题、hover 提示全英文 |

所以：**写界面文案时，类型就是契约**。拿不准就写整句字面量交给 `Text`，或用
`String(localized:)` 显式取。不要拼接、不要先拼成 `String` 再传。

这条闸门查不出来——覆盖率闸门的分母就是 Xcode 抽到的那些键，没抽到的它不知道。
唯一可靠的检查是**截图逐字读**：把屏幕上的英文与译文表对照，分两类处理——
「表里有」说明走错路径，「表里没有」说明从未抽取。

### 另一条同样致命的规则：多参数键的形式必须与运行时一致

Xcode 抽取时把两个以上的插值写成**定位符**（`Current: %1$lld × %2$lld pixels`），
而 SwiftUI 在运行时查的是**非定位符**（`Current: %lld × %lld pixels`）。两者不相等，
后果是：译文躺在表里、覆盖率闸门显示 100%、界面却完全英文。

实测证据（不是推测）：往产物副本里同时放两条候选键，
`Current: %lld × %lld pixels` 立刻被用上，`%1$lld` 那条一次都没被查。
另一条旁证：键归一化之后，`source-keys.json` 里「拿到源码位置」的条数从
820/834 变成 834/834——因为 `.stringsdata` 里记录的正是编译器实际使用的非定位符形式。

所以 `harvest.py` 在入库时统一改写（`plain_key()`），并且只在编号恰好是 1,2,3… 时改写；
重排过参数顺序的语句无法用非定位符表达，保持原样留给 lint。

**代价**：译文的参数顺序必须与英文一致。想换语序，就要把句子拆成两句，
或者在源码里改成单参数（先拼好再插一个 `%@`）。不要试图用 `%2$@` 换回来——
运行时根本不查那样的键。

